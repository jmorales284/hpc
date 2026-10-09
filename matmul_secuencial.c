#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <limits.h>

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

int obtener_parametros(int argc, char *argv[], int *n, int *maximo)
{
    if (argc != 3)
    {
        printf("Uso: %s <tamano> <valor_maximo>\n", argv[0]);
        return 0;
    }

    *n = atoi(argv[1]);
    *maximo = atoi(argv[2]);

    return 1;
}

/* =========================================================
   Validación de parámetros
   ========================================================= */

int validar_parametros(int n, int maximo)
{
    if (n <= 0)
    {
        printf("Error: el tamaño de la matriz debe ser mayor que 0.\n");
        return 0;
    }

    if (maximo <= 0)
    {
        printf("Error: el valor máximo debe ser mayor que 0.\n");
        return 0;
    }

    return 1;
}

/* =========================================================
   Validación de overflow
   ========================================================= */

int validar_rango_multiplicacion(int n, int maximo)
{
    int limite = INT_MAX / n;

    if (maximo > limite / maximo)
    {
        printf("Error: los valores pueden producir overflow de tipo int.\n");
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
        printf("Error: no se pudo reservar memoria.\n");

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
   Multiplicación de matrices
   ========================================================= */

void multiplicar_matrices(int *A, int *B, int *C, int n)
{
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
}

/* =========================================================
   Medición del tiempo de multiplicación
   ========================================================= */

double medir_multiplicacion(int *A, int *B, int *C, int n)
{
    struct timespec inicio;
    struct timespec fin;

    clock_gettime(CLOCK_MONOTONIC, &inicio);

    multiplicar_matrices(A, B, C, n);

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
   Mostrar información del resultado
   ========================================================= */

void mostrar_resultado(int n, int maximo, double tiempo)
{
    printf("Multiplicación completada.\n");
    printf("Tamaño: %d x %d\n", n, n);
    printf("Valor máximo de entrada: %d\n", maximo);
    printf("Tiempo de multiplicación: %.6f segundos\n", tiempo);
}

/* =========================================================
   Función principal
   ========================================================= */

int main(int argc, char *argv[])
{
    int n;
    int maximo;

    Matrices matrices = {NULL, NULL, NULL};

    if (!obtener_parametros(argc, argv, &n, &maximo))
    {
        return 1;
    }

    if (!validar_parametros(n, maximo))
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

    double tiempo = medir_multiplicacion(
        matrices.A,
        matrices.B,
        matrices.C,
        n
    );

    /* Salida en CSV: tamano,workers,tiempo_segundos (workers=1 para
       la version secuencial), mismo formato que matmul_hilos.c y
       matmul_procesos.c, para que un solo script pueda tabular los tres. */
    printf("%d,1,%.6f\n", n, tiempo);

    liberar_matrices(&matrices);

    return 0;
}