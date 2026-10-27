#!/usr/bin/env bash
export LC_ALL=C   # decimales con punto aunque el sistema esté en español (evita errores en awk/CSV)
#
# benchmark_rapido.sh -- prueba CORTA (unos minutos) para comparar máquinas.
# Corre el secuencial -O2 y OpenMP (directiva externa) con todos los hilos lógicos,
# en N=1000 y 2000, 3 repeticiones. Úsalo en CADA máquina y compara los resúmenes.
#
# Uso:  ./benchmark_rapido.sh
# Genera rapido_<nombre-del-equipo>.csv y muestra el resumen al final.

set -u
cd "$(dirname "$0")" || exit 1

if [ ! -x ./matmul_secuencial_O2 ] || [ ! -x ./matmul_openmp_externo ]; then
    bash ./compilar.sh || { echo "Error al compilar"; exit 1; }
fi

HOST="$(hostname)"
OUT="rapido_${HOST}.csv"
NH="$(nproc)"
export TAMANOS="${TAMANOS:-1000 2000}" REPETICIONES="${REPETICIONES:-3}"

bash ./benchmark.sh secuencial_O2  ./matmul_secuencial_O2  "$OUT"
bash ./benchmark.sh openmp_externo ./matmul_openmp_externo "$OUT" "$NH"

echo
echo "=== Resumen de $HOST ($NH hilos lógicos) ==="
awk -F, 'NR>1 { k=$1","$2; s[k]+=$4; c[k]++ }
         END {
           for (k in s) { m[k]=s[k]/c[k] }
           n=split("'"$TAMANOS"'", N, " ");
           printf "%-8s %-12s %-12s %-8s\n", "N", "secuencial", "openmp", "speedup";
           for (i=1;i<=n;i++) {
             a=m["secuencial_O2," N[i]]; b=m["openmp_externo," N[i]];
             printf "%-8s %-12.4f %-12.4f %-8.2f\n", N[i], a, b, a/b
           }
         }' "$OUT"
echo "(tiempos promedio en segundos; guarda y compara este resumen entre máquinas)"
