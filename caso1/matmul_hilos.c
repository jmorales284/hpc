#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <limits.h>
#include <pthread.h>

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
   Estructura con lo que necesita cada hilo para trabajar
   sobre su bloque de filas
   ========================================================= */

typedef struct
{
    const int *A;
    const int *B;
    int *C;
    int n;
    int fila_inicio; /* inclusive */
    int fila_fin;    /* exclusivo */
} TareaHilo;

/* =========================================================
   Obtención de parámetros
   ========================================================= */

int obtener_parametros(int argc, char *argv[], int *n, int *maximo, int *num_hilos)
{
    if (argc != 4)
    {
        fprintf(stderr, "Uso: %s <tamano> <valor_maximo> <num_hilos>\n", argv[0]);
        return 0;
    }

    *n = atoi(argv[1]);
    *maximo = atoi(argv[2]);
    *num_hilos = atoi(argv[3]);

    return 1;
}

/* =========================================================
   Validación de parámetros
   ========================================================= */

int validar_parametros(int n, int maximo, int num_hilos)
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

    if (num_hilos <= 0)
    {
        fprintf(stderr, "Error: el número de hilos debe ser mayor que 0.\n");
        return 0;
    }

    return 1;
}

/* =========================================================
   Validación de overflow (misma lógica que la versión secuencial:
   el paralelismo no cambia el resultado, así que la cota es igual)
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
   Reserva de una matriz
   ========================================================= */

int *reservar_matriz(int n)
{
    return malloc(n * n * sizeof(int));
}

/* =========================================================
   Reserva de las tres matrices
   ========================================================= */

int reservar_matrices(Matrices *matrices, int n)
{
    matrices->A = reservar_matriz(n);
    matrices->B = reservar_matriz(n);
    matrices->C = reservar_matriz(n);

    if (matrices->A == NULL ||
        matrices->B == NULL ||
        matrices->C == NULL)
    {
        fprintf(stderr, "Error: no se pudo reservar memoria.\n");

        free(matrices->A);
        free(matrices->B);
        free(matrices->C);

        matrices->A = NULL;
        matrices->B = NULL;
        matrices->C = NULL;

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
   Trabajo de un hilo: calcula únicamente su bloque de filas
   de la matriz C. Cada hilo escribe en una región disjunta de
   C, así que no hace falta ningún mutex/semáforo: no hay
   condición de carrera posible entre hilos.
   ========================================================= */

void *multiplicar_bloque(void *arg)
{
    TareaHilo *t = (TareaHilo *)arg;

    for (int i = t->fila_inicio; i < t->fila_fin; i++)
    {
        for (int j = 0; j < t->n; j++)
        {
            int suma = 0;

            for (int k = 0; k < t->n; k++)
            {
                suma += t->A[i * t->n + k] * t->B[k * t->n + j];
            }

            t->C[i * t->n + j] = suma;
        }
    }

    return NULL;
}

/* =========================================================
   Reparte las N filas entre num_hilos lo más parejo posible
   (las primeras "resto" reciben una fila extra), crea los
   hilos (patrón fork-join), espera con pthread_join y mide
   el tiempo total con wall clock time.
   ========================================================= */

double medir_multiplicacion_hilos(const int *A, const int *B, int *C, int n, int num_hilos)
{
    /* No tiene sentido crear más hilos que filas a repartir */
    if (num_hilos > n)
    {
        num_hilos = n;
    }

    pthread_t *hilos = malloc((size_t)num_hilos * sizeof(pthread_t));
    TareaHilo *tareas = malloc((size_t)num_hilos * sizeof(TareaHilo));

    int filas_por_hilo = n / num_hilos;
    int resto = n % num_hilos;
    int fila_actual = 0;

    struct timespec inicio;
    struct timespec fin;

    clock_gettime(CLOCK_MONOTONIC, &inicio);

    for (int t = 0; t < num_hilos; t++)
    {
        int filas_asignadas = filas_por_hilo + (t < resto ? 1 : 0);

        tareas[t].A = A;
        tareas[t].B = B;
        tareas[t].C = C;
        tareas[t].n = n;
        tareas[t].fila_inicio = fila_actual;
        tareas[t].fila_fin = fila_actual + filas_asignadas;

        fila_actual += filas_asignadas;

        pthread_create(&hilos[t], NULL, multiplicar_bloque, &tareas[t]);
    }

    for (int t = 0; t < num_hilos; t++)
    {
        pthread_join(hilos[t], NULL);
    }

    clock_gettime(CLOCK_MONOTONIC, &fin);

    free(hilos);
    free(tareas);

    double segundos = (fin.tv_sec - inicio.tv_sec)
                    + (fin.tv_nsec - inicio.tv_nsec) / 1000000000.0;

    return segundos;
}

/* =========================================================
   Liberación de matrices
   ========================================================= */

void liberar_matrices(Matrices *matrices)
{
    free(matrices->A);
    free(matrices->B);
    free(matrices->C);

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
    int num_hilos;

    Matrices matrices = {NULL, NULL, NULL};

    if (!obtener_parametros(argc, argv, &n, &maximo, &num_hilos))
    {
        return 1;
    }

    if (!validar_parametros(n, maximo, num_hilos))
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

    double tiempo = medir_multiplicacion_hilos(
        matrices.A,
        matrices.B,
        matrices.C,
        n,
        num_hilos
    );

    /* Salida en formato CSV: tamano,hilos,tiempo_segundos
       Pensada para que el script de automatizacion redirija
       esta linea directo a un archivo y sea facil de tabular. */
    printf("%d,%d,%.6f\n", n, num_hilos, tiempo);

    liberar_matrices(&matrices);

    return 0;
}