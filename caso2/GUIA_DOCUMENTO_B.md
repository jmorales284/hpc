# Guía – Documento B: perfilado, benchmark y OpenMP

Se trabaja con **dos programas**: el secuencial (línea base) y el de OpenMP (4 variantes).
Todo se ejecuta en una terminal Linux de tu máquina principal (la de la entrega 1).

## Qué hay en la carpeta

| Archivo | Para qué sirve |
|---|---|
| `matmul_secuencial.c` | Tu programa secuencial. Es la línea base. |
| `matmul_openmp.c` | El mismo programa con una directiva `#pragma omp`. Se compila 4 veces con `-DVARIANTE=0..3`, según dónde va la directiva (externo, collapse, medio, interno). |
| `compilar.sh` | Compila el secuencial y las 4 variantes de OpenMP (`-O2`). |
| `correr_openmp.sh` | **El benchmark largo**: mide línea base y variantes, y genera tablas y gráficas. |
| `benchmark.sh` | Lo usa el anterior para medir (repeticiones, CSV, reanudable). |
| `benchmark_rapido.sh` | Prueba corta (minutos) para comparar máquinas. |
| `perfilar_todo.sh`, `perfilar.sh` | Perfilado con `perf` y `/usr/bin/time -v`. |
| `perfilar_gprof_valgrind.sh` | gprof (CPU) y Valgrind: Memcheck y Massif (memoria). |
| `info_maquina.sh` | Datos de la máquina (CPU, caché, RAM, gcc). |
| `analizar_entrega2.py` | Tablas de promedios, speedup y gráficas. |

## ¿Y `matmul_hilos.c` y `matmul_procesos.c`?

Son de la entrega 1 (pthreads y fork) y **no se ejecutan en esta entrega**, por eso no vienen en esta carpeta. Lo que sí se usa de ellos son los **datos que ya mediste** (hilos y procesos, dentro de tu `resultados.csv`), solo para comparar al final: "OpenMP vs pthreads vs procesos" en la gráfica y en las conclusiones.

## Paso a paso

**1. Prepara la carpeta.** Descomprime el zip y copia ahí tu `resultados.csv` de la entrega 1 (el de 660 filas). Es la línea base y los datos de hilos/procesos para comparar. **Sin él**, la etapa 1 vuelve a medir la base completa (~16 h).
```bash
cd ~/ruta/de/la/carpeta
chmod +x *.sh
ls
```

**2. Herramientas** (tú ya las tienes: gcc, OpenMP, gprof, valgrind, pandas y perf comprobados).

**3. Compila y haz la prueba rápida (2 min).**
```bash
bash compilar.sh
PRUEBA=1 ./correr_openmp.sh
rm -rf prueba_run
```
Los números de `prueba_run/` no son datos reales; solo verifican que todo corre.

**4. Datos y comparación de máquinas.**
```bash
./info_maquina.sh
./benchmark_rapido.sh
```
Más Geekbench 6 (puntaje 1 núcleo y multinúcleo; captura de pantalla). Repite estos pasos en la segunda máquina.

**5. Perfilado** (con el equipo quieto; antes de la corrida larga, no a la vez).
```bash
./perfilar_todo.sh
./perfilar_gprof_valgrind.sh 2000 1000
```
Salen `perfilado.csv`, `perfil_raw.txt` y la carpeta `perfilado/` (gprof planas y por línea, memcheck, massif).

**6. Corrida larga** (equipo conectado, sin suspensión, sin usarlo).
```bash
nohup ./correr_openmp.sh > log.txt 2>&1 &
tail -f log.txt
```
Mide, con todos tus hilos lógicos, las 4 variantes con N = 800, 1000, 2000, 4000, 6000, 8000 y 10 repeticiones (la variante interna, 3 repeticiones en N>4000). Si se interrumpe, relanza el mismo comando: continúa donde iba.
Estimado: ~15 h para externo, collapse y medio y ~4 h o más para la interna (**cálculo, no medido**). Si falta tiempo: `SZ_FULL="800 1000 2000 4000 6000" nohup ./correr_openmp.sh > log.txt 2>&1 &` (y lo declaramos en el informe).

**7. Segunda máquina.** Copia la carpeta y ejecuta (mide su propia línea base; el `resultados.csv` de la primera máquina no se usa allí):
```bash
bash compilar.sh
LIGERO=1 nohup ./correr_openmp.sh > log.txt 2>&1 &
```
Usa N = 1000, 2000 y 4000 con 5 repeticiones. Si tiene otro número de hilos, el script lo detecta solo (`nproc`).

**8. Envíame** de cada máquina: `resultados_openmp.csv`, `tabla_promedios.csv`, `tabla_speedup.csv`, `grafica_openmp.png`, `grafica_tecnicas.png`, `info_maquina_*.txt`, la captura de Geekbench y, de la principal, `perfilado.csv` y la carpeta `perfilado/`.

## Si algo falla
| Síntoma | Qué hacer |
|---|---|
| `Permission denied` | `chmod +x *.sh` |
| `perf: permiso denegado` | `sudo sysctl -w kernel.perf_event_paranoid=1` |
| Se detuvo la corrida | Relanza el mismo comando |
| No sale la gráfica | Falta `resultados.csv` en la carpeta; cópialo y corre `ETAPAS="3" ./correr_openmp.sh` |
| La variante interna tarda demasiado | Detén (`pkill -f correr_openmp`) y avísame; los datos parciales sirven |
