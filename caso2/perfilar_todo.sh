#!/usr/bin/env bash
export LC_ALL=C
#
# perfilar_todo.sh -- perf + /usr/bin/time -v sobre el secuencial y las variantes de OpenMP.
# Incluye N=1000 a propósito, para investigar por qué con 8 hilos el speedup cae ahí.
#
# Uso:  ./perfilar_todo.sh                      (N=1000 y 2000)
#       PERFIL_N="1000 2000 4000" ./perfilar_todo.sh
# Resultado: perfilado.csv (una fila por configuración) y perfil_raw.txt (salida cruda)

set -u
cd "$(dirname "$0")" || exit 1
PERFIL_N="${PERFIL_N:-1000 2000}"
H="$(nproc)"; M=$(( H / 2 ))          # hilos lógicos y la mitad (núcleos físicos)

[ -x ./matmul_openmp_externo ] || bash ./compilar.sh || exit 1

for n in $PERFIL_N; do
    ./perfilar.sh secuencial_O2 ./matmul_secuencial_O2 "$n"
    for v in externo collapse medio; do
        ./perfilar.sh "openmp_$v" "./matmul_openmp_$v" "$n" "$M"
        ./perfilar.sh "openmp_$v" "./matmul_openmp_$v" "$n" "$H"
    done
done
echo "Listo. Resultados en perfilado.csv, salida cruda en perfil_raw.txt"
