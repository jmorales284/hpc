#!/usr/bin/env bash
#
# info_maquina.sh -- guarda las especificaciones de la máquina en un txt.
# Cada integrante lo corre en SU computador y entrega el archivo, para
# poder documentar las dos (o más) máquinas del benchmark.
#
# Uso: ./info_maquina.sh [nombre_de_la_maquina]

NOMBRE="${1:-$(hostname)}"
SALIDA="info_maquina_${NOMBRE}.txt"

{
    echo "===== Máquina: $NOMBRE ====="
    echo "Fecha: $(date)"
    echo
    echo "----- Sistema -----"
    uname -a
    grep PRETTY_NAME /etc/os-release 2>/dev/null
    echo
    echo "----- CPU (lscpu) -----"
    lscpu
    echo
    echo "----- Núcleos disponibles (nproc) -----"
    nproc
    echo
    echo "----- Memoria (free -h) -----"
    free -h
    echo
    echo "----- Gobernador de frecuencia -----"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "no disponible"
    echo
    echo "----- Compilador -----"
    gcc --version | head -1
} > "$SALIDA" 2>&1

echo "Guardado en $SALIDA"
