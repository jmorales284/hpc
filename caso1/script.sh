#!/usr/bin/env bash
#
# ejecutar_pruebas.sh
#
# Corre automáticamente las tres versiones del caso de estudio
# (secuencial, hilos, procesos) para varios tamaños de matriz y varias
# configuraciones de hilos/procesos, repitiendo cada combinación
# REPETICIONES veces, y deja todo en UN SOLO archivo CSV listo para
# abrir en Excel/LibreOffice y sacar promedios y speedup con tablas
# dinámicas.
#
# Uso:
#   ./ejecutar_pruebas.sh
#
# Requiere que ya estén compilados en el mismo directorio:
#   matmul_secuencial, matmul_hilos, matmul_procesos
#
# Salida:
#   resultados.csv con columnas: tipo,n,workers,tiempo_segundos,repeticion

set -u

MAXVAL=10
REPETICIONES=10
TAMANOS=(800 1000 2000 4000 6000 8000)
HILOS=(2 4 8 16 32)
PROCESOS=(2 4 8 16 32)

BIN_SEC=./matmul_secuencial
BIN_HILOS=./matmul_hilos
BIN_PROC=./matmul_procesos

SALIDA="resultados.csv"

# --- Verificación de que los binarios existen y son ejecutables ---
for b in "$BIN_SEC" "$BIN_HILOS" "$BIN_PROC"; do
    if [ ! -x "$b" ]; then
        echo "Error: no se encontró el ejecutable $b en este directorio." >&2
        echo "Compílalo primero, por ejemplo:" >&2
        echo "  gcc -O2 -Wall -Wextra -o matmul_secuencial matmul_secuencial.c" >&2
        echo "  gcc -O2 -Wall -Wextra -o matmul_hilos matmul_hilos.c -pthread" >&2
        echo "  gcc -O2 -Wall -Wextra -o matmul_procesos matmul_procesos.c" >&2
        exit 1
    fi
done

# Si el archivo de salida no existe, se crea con encabezado.
# Si ya existe (por ejemplo, retomando una corrida interrumpida),
# se sigue agregando al final sin volver a escribir el encabezado.
if [ ! -f "$SALIDA" ]; then
    echo "tipo,n,workers,tiempo_segundos,repeticion" > "$SALIDA"
fi

# correr TIPO BINARIO N WORKERS REP
# WORKERS vacío ("") significa "no pasar tercer argumento" (caso secuencial)
correr() {
    local tipo="$1"
    local binario="$2"
    local n="$3"
    local workers="$4"
    local rep="$5"

    local salida_bin
    if [ -z "$workers" ]; then
        salida_bin=$("$binario" "$n" "$MAXVAL")
    else
        salida_bin=$("$binario" "$n" "$MAXVAL" "$workers")
    fi

    if [ -z "$salida_bin" ]; then
        echo "  [!] $tipo n=$n workers=${workers:-1} rep=$rep no produjo salida (revisar)" >&2
        return
    fi

    # salida_bin ya viene como "n,workers,tiempo" -> se antepone el tipo
    # y se agrega el numero de repeticion al final.
    echo "${tipo},${salida_bin},${rep}" >> "$SALIDA"

    local tiempo
    tiempo=$(echo "$salida_bin" | cut -d',' -f3)
    echo "  [$tipo] n=$n workers=${workers:-1} rep=$rep -> ${tiempo}s"
}

total_inicio=$(date +%s)

for rep in $(seq 1 "$REPETICIONES"); do
    echo "=== Repetición $rep de $REPETICIONES ==="

    for n in "${TAMANOS[@]}"; do
        echo " -- n=$n --"

        correr secuencial "$BIN_SEC" "$n" "" "$rep"

        for h in "${HILOS[@]}"; do
            correr hilos "$BIN_HILOS" "$n" "$h" "$rep"
        done

        for p in "${PROCESOS[@]}"; do
            correr procesos "$BIN_PROC" "$n" "$p" "$rep"
        done
    done
done

total_fin=$(date +%s)
echo "Listo. Resultados acumulados en $SALIDA"
echo "Tiempo total del script: $((total_fin - total_inicio)) segundos"