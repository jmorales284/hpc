#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <limits.h>
#include <omp.h>

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
   Validación de overflow (misma cota que las demás versiones)
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
    return malloc((size_t)n * (size_t)n * sizeof(int));
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
   Multiplicación con OpenMP -- 4 variantes según DÓNDE se pone la
   directiva. Se elige al compilar con -DVARIANTE=<0..3> (ver
   compilar_todo.sh); el algoritmo i-j-k es siempre el mismo.

   VARIANTE 0 (externo)          parallel for sobre el ciclo i
        Reparte filas de C entre los hilos: es lo mismo que hicimos a
        mano con pthreads/fork. Una sola región paralela.

   VARIANTE 1 (externo+collapse) parallel for collapse(2) sobre i y j
        Fusiona i y j en un solo espacio de n*n iteraciones (celdas de
        C) y lo reparte. Mejor balance de carga cuando n no es múltiplo
        del número de hilos o hay pocas filas por hilo.

   VARIANTE 2 (medio)            parallel for sobre el ciclo j
        El ciclo i queda secuencial y en CADA fila se crea/cierra una
        región paralela (n regiones en total): más overhead.

   VARIANTE 3 (interno)          parallel for reduction(+:suma) sobre k
        Se paraleliza la sumatoria de cada celda. Hay una región
        paralela por celda (n*n regiones): el mayor overhead. Sin la
        cláusula reduction habría condición de carrera sobre "suma" y el
        resultado sería incorrecto; con reduction cada hilo acumula una
        copia privada y OpenMP las combina al final, así el resultado
        sigue siendo correcto.

   En todas, schedule(static) reparte las iteraciones de una vez en
   bloques contiguos de igual tamaño. Las variables declaradas dentro
   de los ciclos (j, k, suma) son privadas de cada hilo.
   ========================================================= */

#ifndef VARIANTE
#define VARIANTE 0
#endif

void multiplicar_matrices_openmp(const int *A, const int *B, int *C, int n)
{
#if VARIANTE == 0

    #pragma omp parallel for schedule(static)
    for (int i = 0; i < n; i++)
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

#elif VARIANTE == 1

    #pragma omp parallel for collapse(2) schedule(static)
    for (int i = 0; i < n; i++)
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

#elif VARIANTE == 2

    for (int i = 0; i < n; i++)
    {
        #pragma omp parallel for schedule(static)
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

#elif VARIANTE == 3

    for (int i = 0; i < n; i++)
    {
        for (int j = 0; j < n; j++)
        {
            int suma = 0;

            #pragma omp parallel for reduction(+:suma) schedule(static)
            for (int k = 0; k < n; k++)
            {
                suma += A[i * n + k] * B[k * n + j];
            }

            C[i * n + j] = suma;
        }
    }

#else
#error "VARIANTE debe ser 0, 1, 2 o 3"
#endif
}

/* =========================================================
   Medición del tiempo (wall clock, igual que las otras versiones).
   omp_set_num_threads fija cuántos hilos usará la región paralela.
   ========================================================= */

double medir_multiplicacion_openmp(const int *A, const int *B, int *C,
                                   int n, int num_hilos)
{
    struct timespec inicio;
    struct timespec fin;

    omp_set_num_threads(num_hilos);

    clock_gettime(CLOCK_MONOTONIC, &inicio);

    multiplicar_matrices_openmp(A, B, C, n);

    clock_gettime(CLOCK_MONOTONIC, &fin);

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

    double tiempo = medir_multiplicacion_openmp(
        matrices.A,
        matrices.B,
        matrices.C,
        n,
        num_hilos
    );

    /* Salida CSV: tamano,hilos,tiempo_segundos (mismo formato de siempre) */
    printf("%d,%d,%.6f\n", n, num_hilos, tiempo);

    liberar_matrices(&matrices);

    return 0;
}
