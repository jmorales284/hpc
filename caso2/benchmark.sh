#!/usr/bin/env bash
export LC_ALL=C   # decimales con punto aunque el sistema esté en español (evita errores en awk/CSV)
#
# benchmark.sh -- corre UN ejecutable en todos los tamaños de N (y, si
# aplica, para varios números de hilos/procesos), repitiendo cada
# combinación, y agrega los tiempos a un CSV.
#
# Uso:
#   ./benchmark.sh <etiqueta> <binario> <salida.csv> [workers ...]
#
# Ejemplos:
#   ./benchmark.sh O3 ./matmul_secuencial_O3 resultados_flags.csv
#   ./benchmark.sh traspuesta ./matmul_traspuesta resultados_traspuesta.csv
#   ./benchmark.sh openmp ./matmul_openmp resultados_openmp.csv 2 4 8 16
#
# Variables de entorno opcionales (con sus valores por defecto):
#   TAMANOS="800 1000 2000 4000 6000 8000"
#   REPETICIONES=10
#   MAXVAL=10
#
# Ejemplo de tamizaje rápido:
#   TAMANOS="800 1000 2000" REPETICIONES=3 ./benchmark.sh O3 ./matmul_secuencial_O3 tamizaje.csv
#
# Formato del CSV (igual que tu resultados.csv original):
#   tipo,n,workers,tiempo_segundos,repeticion
# Para los programas secuenciales, workers = 1.
#
# REANUDABLE: si el script se interrumpe, vuelve a correrlo con los
# mismos argumentos y se salta las combinaciones que ya están en el CSV.

set -u

if [ $# -lt 3 ]; then
    echo "Uso: $0 <etiqueta> <binario> <salida.csv> [workers ...]" >&2
    exit 1
fi

ETIQUETA="$1"
BINARIO="$2"
SALIDA="$3"
shift 3
WORKERS=("$@")

MAXVAL="${MAXVAL:-10}"
REPETICIONES="${REPETICIONES:-10}"
read -r -a SIZES <<< "${TAMANOS:-800 1000 2000 4000 6000 8000}"

if [ ! -x "$BINARIO" ]; then
    echo "Error: $BINARIO no existe o no es ejecutable. Corre primero ./compilar_todo.sh" >&2
    exit 1
fi

# Sin workers => versión secuencial: una sola "configuración" vacía
if [ ${#WORKERS[@]} -eq 0 ]; then
    WORKERS=("")
fi

if [ ! -f "$SALIDA" ]; then
    echo "tipo,n,workers,tiempo_segundos,repeticion" > "$SALIDA"
fi

inicio=$(date +%s)

for rep in $(seq 1 "$REPETICIONES"); do
    echo "=== [$ETIQUETA] repeticion $rep de $REPETICIONES ==="
    for n in "${SIZES[@]}"; do
        for w in "${WORKERS[@]}"; do
            w_csv="${w:-1}"

            # Reanudación: si ya existe esta combinación, se salta
            if grep -q "^${ETIQUETA},${n},${w_csv},[^,]*,${rep}\$" "$SALIDA"; then
                continue
            fi

            if [ -z "$w" ]; then
                salida=$("$BINARIO" "$n" "$MAXVAL")
            else
                salida=$("$BINARIO" "$n" "$MAXVAL" "$w")
            fi

            # El programa imprime "n,workers,tiempo"; se toma el tercer campo
            tiempo=$(echo "$salida" | cut -d',' -f3)

            if [ -z "$tiempo" ]; then
                echo "  [!] sin salida: $ETIQUETA n=$n workers=$w_csv rep=$rep" >&2
                continue
            fi

            echo "${ETIQUETA},${n},${w_csv},${tiempo},${rep}" >> "$SALIDA"
            echo "  [$ETIQUETA] n=$n workers=$w_csv rep=$rep -> ${tiempo}s"
        done
    done
done

fin=$(date +%s)
echo "Listo [$ETIQUETA]. Resultados en $SALIDA (tiempo total: $((fin - inicio)) s)"
