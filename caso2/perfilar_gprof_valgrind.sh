#!/usr/bin/env bash
export LC_ALL=C   # decimales con punto aunque el sistema esté en español (evita errores en awk/CSV)
#
# perfilar_gprof_valgrind.sh -- perfilado de CPU (gprof) y de memoria (Valgrind)
# de la versión SECUENCIAL, con las mismas herramientas del documento de referencia.
#
# Uso:
#   ./perfilar_gprof_valgrind.sh [N_gprof] [N_valgrind]
#   (por defecto 2000 y 1000)
#
# IMPORTANTE sobre los tamaños:
#   - gprof casi no añade sobrecarga, pero se compila SIN optimizar (-O0) para
#     que el reporte por línea tenga sentido, así que N=2000 tarda ~1-2 min.
#   - Valgrind hace el programa 10-50 veces más lento: por eso se usa un N más
#     chico. Los tiempos medidos bajo Valgrind NO son rendimiento real.
#
# Instalación en Ubuntu:  sudo apt install valgrind binutils
#
# Salidas (en la carpeta perfilado/):
#   gprof_planas.txt   flat profile + call graph (por función)
#   gprof_lineas.txt   flat profile a nivel de LÍNEA (gprof -l)
#   memcheck.txt       errores y fugas de memoria
#   massif_heap.txt    uso del heap en el tiempo (solo malloc)
#   massif_paginas.txt uso de TODA la memoria del proceso (--pages-as-heap=yes)

set -u
NG="${1:-2000}"
NV="${2:-1000}"
MAXVAL=10
OUT="perfilado"
mkdir -p "$OUT"

# --------------------------- CPU: gprof ---------------------------
if command -v gprof >/dev/null 2>&1; then
    echo "[gprof] compilando con -O0 -g -pg ..."
    gcc -O0 -g -pg -o "$OUT/matmul_pg" matmul_secuencial.c
    echo "[gprof] ejecutando con N=$NG ..."
    ( cd "$OUT" && ./matmul_pg "$NG" "$MAXVAL" && \
      gprof -b ./matmul_pg gmon.out > gprof_planas.txt && \
      gprof -b -l ./matmul_pg gmon.out > gprof_lineas.txt )
    echo "[gprof] primeras líneas del perfil por línea:"
    head -14 "$OUT/gprof_lineas.txt"
else
    echo "Aviso: gprof no encontrado (sudo apt install binutils). Se omite CPU." >&2
fi

# ------------------------- Memoria: Valgrind -----------------------
if command -v valgrind >/dev/null 2>&1; then
    gcc -O0 -g -o "$OUT/matmul_g" matmul_secuencial.c

    echo "[memcheck] N=$NV (lento a propósito) ..."
    valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all \
        "$OUT/matmul_g" "$NV" "$MAXVAL" 2> "$OUT/memcheck.txt"
    grep -E "total heap usage|ERROR SUMMARY|All heap blocks" "$OUT/memcheck.txt"

    echo "[massif] solo heap ..."
    valgrind --tool=massif --massif-out-file="$OUT/massif_heap.out" \
        "$OUT/matmul_g" "$NV" "$MAXVAL" > /dev/null
    ms_print "$OUT/massif_heap.out" > "$OUT/massif_heap.txt"

    echo "[massif] toda la memoria del proceso (--pages-as-heap=yes) ..."
    valgrind --tool=massif --pages-as-heap=yes --massif-out-file="$OUT/massif_paginas.out" \
        "$OUT/matmul_g" "$NV" "$MAXVAL" > /dev/null
    ms_print "$OUT/massif_paginas.out" > "$OUT/massif_paginas.txt"

    echo
    echo "Memoria esperada (3 matrices de int, bloque contiguo): 3*4*N^2 bytes"
    awk -v n="$NV" 'BEGIN{printf "  N=%d -> %.2f MB (el pico de massif debería ser cercano a este valor)\n", n, 3*4*n*n/1048576}'
else
    echo "Aviso: valgrind no encontrado (sudo apt install valgrind). Se omite memoria." >&2
fi

echo "Listo. Revisa la carpeta $OUT/"
