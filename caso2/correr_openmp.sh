#!/usr/bin/env bash
export LC_ALL=C   # decimales con punto aunque el sistema esté en español
#
# correr_openmp.sh -- benchmark de OpenMP (la parte larga del documento B).
#
# Uso normal (déjalo corriendo en segundo plano):
#   nohup ./correr_openmp.sh > log.txt 2>&1 &
#   tail -f log.txt            # ver avance (Ctrl+C sale del tail, no detiene la corrida)
#
# Prueba rápida (1-2 min, para verificar que todo funciona; NO son datos reales):
#   PRUEBA=1 ./correr_openmp.sh
#
# Segunda máquina (alcance reducido: N=1000,2000,4000 y 5 repeticiones; mide su propia base):
#   LIGERO=1 nohup ./correr_openmp.sh > log.txt 2>&1 &
#
# ETAPAS (por defecto: 1, 2 y 3):
#   1  Línea base: secuencial -O2. Se salta si ya tienes resultados.csv de la primera
#      entrega (misma máquina), salvo que uses LIGERO=1 o BASE=1.
#   2  OpenMP: externo, collapse y medio con la mitad de los hilos (núcleos físicos) y con todos
#      los hilos lógicos; interno solo con todos los hilos. 6 tamaños y 10 repeticiones
#      (la interna, 3 repeticiones en N>4000).
#   3  Tablas y gráficas (analizar_entrega2.py)
#   4  (opcional) la mejor variante con 2 hilos: ETAPAS="4" ./correr_openmp.sh
#
# REANUDABLE: si se interrumpe, lanza el mismo comando y continúa donde iba.
# No uses el computador mientras corre; las etapas van una tras otra a propósito.

set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT" || exit 1

HILOS="${HILOS:-$(nproc)}"                    # hilos lógicos de esta máquina
MITAD=$(( HILOS / 2 )); [ "$MITAD" -lt 1 ] && MITAD=1   # núcleos físicos (aprox.)
if [ "$MITAD" -eq "$HILOS" ]; then WORKERS="$HILOS"; else WORKERS="$MITAD $HILOS"; fi
SZ_FULL="${SZ_FULL:-800 1000 2000 4000 6000 8000}";  REP_FULL="${REP_FULL:-10}"
OUT="."

if [ "${PRUEBA:-0}" = "1" ]; then
    echo ">>> MODO PRUEBA: tamaños y repeticiones mínimos; resultados en ./prueba_run (no son datos reales)"
    SZ_FULL="200 300"; REP_FULL=2; OUT="prueba_run"; mkdir -p "$OUT"
    [ -f resultados.csv ] && cp --update=none resultados.csv "$OUT/resultados.csv"
fi
if [ "${LIGERO:-0}" = "1" ]; then
    echo ">>> MODO LIGERO (segunda máquina): N=1000,2000,4000 y 5 repeticiones, con base propia"
    SZ_FULL="1000 2000 4000"; REP_FULL=5
fi

ETAPAS="${ETAPAS:-1 2 3}"
BASE_CSV="$OUT/resultados_secuencial.csv"
OMP_CSV="$OUT/resultados_openmp.csv"
quiere() { [[ " $ETAPAS " == *" $1 "* ]]; }
titulo() { echo; echo "################ $* ################"; date; }

if [ ! -x ./matmul_secuencial_O2 ] || [ ! -x ./matmul_openmp_collapse ]; then
    titulo "Compilando"; bash ./compilar.sh || { echo "Error al compilar"; exit 1; }
fi
inicio=$(date +%s)

# ----- Etapa 1: línea base -----
if quiere 1; then
    if [ -f "$OUT/resultados.csv" ] && [ "${LIGERO:-0}" != "1" ] && [ "${BASE:-0}" != "1" ]; then
        echo ">>> Etapa 1 omitida: se usa la base de la primera entrega ($OUT/resultados.csv)."
    else
        titulo "ETAPA 1: línea base, secuencial -O2"
        TAMANOS="$SZ_FULL" REPETICIONES="$REP_FULL" \
            bash ./benchmark.sh secuencial ./matmul_secuencial_O2 "$BASE_CSV"
    fi
fi

# ----- Etapa 2: OpenMP -----
if quiere 2; then
    titulo "ETAPA 2: OpenMP, 4 variantes (hilos: $WORKERS)"
    for v in externo collapse medio; do
        TAMANOS="$SZ_FULL" REPETICIONES="$REP_FULL" \
            bash ./benchmark.sh "openmp_$v" "./matmul_openmp_$v" "$OMP_CSV" $WORKERS
    done
    # La interna crea una región paralela por celda (n^2 regiones): la más lenta, va al final.
    SZ_A=""; SZ_B=""
    for n in $SZ_FULL; do if [ "$n" -le 4000 ]; then SZ_A="$SZ_A $n"; else SZ_B="$SZ_B $n"; fi; done
    REP_B=3; [ "$REP_FULL" -lt 3 ] && REP_B="$REP_FULL"
    [ -n "$SZ_A" ] && TAMANOS="$SZ_A" REPETICIONES="$REP_FULL" \
        bash ./benchmark.sh openmp_interno ./matmul_openmp_interno "$OMP_CSV" "$HILOS"
    [ -n "$SZ_B" ] && TAMANOS="$SZ_B" REPETICIONES="$REP_B" \
        bash ./benchmark.sh openmp_interno ./matmul_openmp_interno "$OMP_CSV" "$HILOS"
fi

# ----- Etapa 4 (opcional): la mejor variante con menos hilos -----
if quiere 4; then
    titulo "ETAPA 4: mejor variante con 2 hilos"
    MEJOR=$(awk -F, -v w="$HILOS" 'NR>1 && $3==w && ($1=="openmp_externo"||$1=="openmp_collapse"||$1=="openmp_medio") {s[$1]+=$4; c[$1]++}
         END{m=""; for(k in s){p=s[k]/c[k]; printf "  %-16s promedio %.4f s\n", k, p > "/dev/stderr"; if(m==""||p<b){m=k;b=p}} print m}' "$OMP_CSV")
    [ -z "$MEJOR" ] && { echo "Corre primero la etapa 2."; exit 1; }
    echo ">>> Mejor variante: $MEJOR"
    TAMANOS="$SZ_FULL" REPETICIONES="$REP_FULL" \
        bash ./benchmark.sh "$MEJOR" "./matmul_${MEJOR}" "$OMP_CSV" 2
fi

# ----- Etapa 3: análisis -----
if quiere 3; then
    titulo "ETAPA 3: tablas y gráficas"
    if [ -f "$OUT/resultados.csv" ] && [ "${LIGERO:-0}" != "1" ] && [ "${BASE:-0}" != "1" ]; then
        BASE_ARG="resultados.csv"
    else
        BASE_ARG="resultados_secuencial.csv"
    fi
    ( cd "$OUT" && python3 "$ROOT/analizar_entrega2.py" --paralelo "$BASE_ARG" --omp-hilos "$HILOS" )
fi

titulo "TERMINADO"
echo "Tiempo total: $(( ($(date +%s) - inicio) / 60 )) minutos"
