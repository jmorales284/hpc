#!/usr/bin/env bash
export LC_ALL=C
#
# compilar.sh -- compila lo que usa esta entrega:
#   matmul_secuencial_O2           el secuencial (línea base)
#   matmul_openmp_{externo,collapse,medio,interno}   las 4 variantes de OpenMP
# Todo con -O2, igual que la línea base de la primera entrega.
set -e
CF="-Wall -Wextra"
echo "Compilando el secuencial (-O2)..."
gcc -O2 $CF -o matmul_secuencial_O2 matmul_secuencial.c
echo "Compilando las 4 variantes de OpenMP (mismo fuente, distinta directiva)..."
gcc -O2 $CF -fopenmp -DVARIANTE=0 -o matmul_openmp_externo  matmul_openmp.c
gcc -O2 $CF -fopenmp -DVARIANTE=1 -o matmul_openmp_collapse matmul_openmp.c
gcc -O2 $CF -fopenmp -DVARIANTE=2 -o matmul_openmp_medio    matmul_openmp.c
gcc -O2 $CF -fopenmp -DVARIANTE=3 -o matmul_openmp_interno  matmul_openmp.c
echo "Listo."
