#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <limits.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/wait.h>

/* =========================================================
   Estructura para almacenar las tres matrices
   ========================================================= */

typedef struct
{
    int *A;
    int *B;
    int *C;
} Matrices;

/* =========================================================
   Obtención de parámetros
   ========================================================= */

int obtener_parametros(int argc, char *argv[], int *n, int *maximo, int *num_procesos)
{
    if (argc != 4)
    {
        fprintf(stderr, "Uso: %s <tamano> <valor_maximo> <num_procesos>\n", argv[0]);
        return 0;
    }

    *n = atoi(argv[1]);
    *maximo = atoi(argv[2]);
    *num_procesos = atoi(argv[3]);

    return 1;
}

/* =========================================================
   Validación de parámetros
   ========================================================= */

int validar_parametros(int n, int maximo, int num_procesos)
{
    if (n <= 0)
    {
        fprintf(stderr, "Error: el tamaño de la matriz debe ser mayor que 0.\n");
        return 0;
    }

    if (maximo <= 0)
    {
        fprintf(stderr, "Error: el valor máximo debe ser mayor que 0.\n");
        return 0;
    }

    if (num_procesos <= 0)
    {
        fprintf(stderr, "Error: el número de procesos debe ser mayor que 0.\n");
        return 0;
    }

    return 1;
}

/* =========================================================
   Validación de overflow (misma cota que la versión secuencial)
   ========================================================= */

int validar_rango_multiplicacion(int n, int maximo)
{
    int limite = INT_MAX / n;

    if (maximo > limite / maximo)
    {
        fprintf(stderr, "Error: los valores pueden producir overflow de tipo int.\n");
        return 0;
    }

    return 1;
}

/* =========================================================
   Reserva de una matriz en memoria COMPARTIDA entre procesos.

   A diferencia de malloc(), un fork() posterior a malloc() le da
   a cada hijo una copia privada tipo copy-on-write de esa memoria:
   lo que el hijo escriba en C NO se vería en el padre. Por eso aquí
   se usa mmap() con MAP_SHARED | MAP_ANONYMOUS, que crea una región
   visible y modificable por el proceso padre y todos los hijos,
   igual que en el documento de referencia.
   ========================================================= */

int *reservar_matriz_compartida(int n)
{
    size_t bytes = (size_t)n * (size_t)n * sizeof(int);

    int *m = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                   MAP_SHARED | MAP_ANONYMOUS, -1, 0);

    if (m == MAP_FAILED)
    {
        return NULL;
    }

    return m;
}

/* =========================================================
   Reserva de las tres matrices compartidas
   ========================================================= */

int reservar_matrices(Matrices *matrices, int n)
{
    matrices->A = reservar_matriz_compartida(n);
    matrices->B = reservar_matriz_compartida(n);
    matrices->C = reservar_matriz_compartida(n);

    if (matrices->A == NULL ||
        matrices->B == NULL ||
        matrices->C == NULL)
    {
        fprintf(stderr, "Error: no se pudo reservar memoria compartida.\n");
        return 0;
    }

    return 1;
}

/* =========================================================
   Inicialización de números aleatorios
   ========================================================= */

void inicializar_aleatoriedad(void)
{
    srand(time(NULL));
}

/* =========================================================
   Llenado de una matriz
   ========================================================= */

void llenar_matriz(int *matriz, int n, int maximo)
{
    for (int i = 0; i < n; i++)
    {
        for (int j = 0; j < n; j++)
        {
            matriz[i * n + j] = (rand() % maximo) + 1;
        }
    }
}

/* =========================================================
   Trabajo de UN proceso: multiplica únicamente su bloque de
   filas [fila_inicio, fila_fin) y escribe en C.

   Nota sobre sincronización: igual que con los hilos, cada
   proceso escribe en una región de C completamente disjunta
   de la de los demás (un rango de filas distinto). Por eso NO
   hace falta un semáforo para esta región crítica: no existe
   tal región crítica, ningún proceso lee ni escribe una celda
   que otro también toque. El semáforo del documento de
   referencia tiene sentido si varios procesos compartieran la
   MISMA celda o estructura (por ejemplo, un acumulador global
   de progreso); aquí no es el caso. Se deja documentado por si
   tu profesor pide explícitamente demostrar el uso de un
   semáforo como mecanismo de sincronización.
   ========================================================= */

void multiplicar_bloque(const int *A, const int *B, int *C, int n,
                         int fila_inicio, int fila_fin)
{
    for (int i = fila_inicio; i < fila_fin; i++)
    {
        for (int j = 0; j < n; j++)
        {
            int suma = 0;

            for (int k = 0; k < n; k++)
            {
                suma += A[i * n + k] * B[k * n + j];
            }

            C[i * n + j] = suma;
        }
    }
}

/* =========================================================
   Reparte las N filas entre num_procesos, crea los procesos
   con fork() (patrón fork-join equivalente al de hilos, pero
   con procesos), espera con waitpid a que todos terminen y
   mide el tiempo total con wall clock time.
   ========================================================= */

double medir_multiplicacion_procesos(const int *A, const int *B, int *C,
                                      int n, int num_procesos)
{
    if (num_procesos > n)
    {
        num_procesos = n;
    }

    pid_t *hijos = malloc((size_t)num_procesos * sizeof(pid_t));

    int filas_por_proceso = n / num_procesos;
    int resto = n % num_procesos;
    int fila_actual = 0;

    struct timespec inicio;
    struct timespec fin;

    clock_gettime(CLOCK_MONOTONIC, &inicio);

    for (int p = 0; p < num_procesos; p++)
    {
        int filas_asignadas = filas_por_proceso + (p < resto ? 1 : 0);
        int fila_inicio = fila_actual;
        int fila_fin = fila_actual + filas_asignadas;

        fila_actual += filas_asignadas;

        pid_t pid = fork();

        if (pid < 0)
        {
            fprintf(stderr, "Error: fork() falló en el proceso %d.\n", p);
            /* Se continúa esperando a los hijos ya creados para no dejar zombies */
            break;
        }
        else if (pid == 0)
        {
            /* Proceso hijo: calcula su bloque y termina */
            multiplicar_bloque(A, B, C, n, fila_inicio, fila_fin);
            _exit(0);
        }
        else
        {
            /* Proceso padre: guarda el pid para esperarlo luego */
            hijos[p] = pid;
        }
    }

    for (int p = 0; p < num_procesos; p++)
    {
        int estado;
        waitpid(hijos[p], &estado, 0);
    }

    clock_gettime(CLOCK_MONOTONIC, &fin);

    free(hijos);

    double segundos = (fin.tv_sec - inicio.tv_sec)
                    + (fin.tv_nsec - inicio.tv_nsec) / 1000000000.0;

    return segundos;
}

/* =========================================================
   Liberación de matrices compartidas
   ========================================================= */

void liberar_matrices(Matrices *matrices, int n)
{
    size_t bytes = (size_t)n * (size_t)n * sizeof(int);

    if (matrices->A) munmap(matrices->A, bytes);
    if (matrices->B) munmap(matrices->B, bytes);
    if (matrices->C) munmap(matrices->C, bytes);

    matrices->A = NULL;
    matrices->B = NULL;
    matrices->C = NULL;
}

/* =========================================================
   Función principal
   ========================================================= */

int main(int argc, char *argv[])
{
    int n;
    int maximo;
    int num_procesos;

    Matrices matrices = {NULL, NULL, NULL};

    if (!obtener_parametros(argc, argv, &n, &maximo, &num_procesos))
    {
        return 1;
    }

    if (!validar_parametros(n, maximo, num_procesos))
    {
        return 1;
    }

    if (!validar_rango_multiplicacion(n, maximo))
    {
        return 1;
    }

    if (!reservar_matrices(&matrices, n))
    {
        return 1;
    }

    inicializar_aleatoriedad();

    llenar_matriz(matrices.A, n, maximo);
    llenar_matriz(matrices.B, n, maximo);

    double tiempo = medir_multiplicacion_procesos(
        matrices.A,
        matrices.B,
        matrices.C,
        n,
        num_procesos
    );

    /* Salida en CSV, igual formato que matmul_hilos.c */
    printf("%d,%d,%.6f\n", n, num_procesos, tiempo);

    liberar_matrices(&matrices, n);

    return 0;
}