#!/usr/bin/env python3
"""
analizar_entrega2.py

Toma los CSV generados por benchmark.sh y construye:
  - tabla_promedios.csv : tiempo promedio por técnica y tamaño de N
  - tabla_speedup.csv   : speedup = T_baseline / T_técnica
  - grafica_flags.png   : speedup de cada nivel de optimización del compilador
  - grafica_tecnicas.png: comparación de las técnicas (mejor flag, traspuesta,
                          mejor hilos, mejor procesos y, si existe, OpenMP)

Archivos de entrada (todos con columnas tipo,n,workers,tiempo_segundos,repeticion):
  resultados.csv            -> el experimento anterior (secuencial, hilos, procesos)
  resultados_flags.csv      -> tipos O0, O1, O2, O3, Ofast
  resultados_traspuesta.csv -> tipo traspuesta
  resultados_openmp.csv     -> la MEJOR variante de OpenMP compilada con -O2 (2, 4, 8 hilos)
  resultados_openmp_O0.csv  -> las 4 variantes compiladas con -O0 (selección de directiva)

Uso:
  python3 analizar_entrega2.py                    # baseline = secuencial -O2
  python3 analizar_entrega2.py --baseline o0      # baseline = secuencial -O0

Sobre el baseline (decisión metodológica, ver explicación en el chat):
  o2 -> usa la secuencial de resultados.csv (compilada con -O2), la MISMA contra
        la que ya se calcularon los speedups de hilos y procesos. Es el único
        baseline para el que las 4 curvas son estrictamente comparables.
  o0 -> usa el tipo O0 de resultados_flags.csv. Muestra el efecto "puro" del
        compilador, pero hilos y procesos (compilados con -O2) quedan mezclando
        el efecto del compilador con el del paralelismo; el script lo advierte.
"""

import argparse
import os
import sys

import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def cargar(ruta, obligatorio=False, silencioso=False):
    if not os.path.exists(ruta):
        if obligatorio:
            sys.exit(f"Error: falta el archivo obligatorio {ruta}")
        if not silencioso:
            print(f"(aviso) no se encontró {ruta}, se omite")
        return None
    df = pd.read_csv(ruta)
    esperado = {"tipo", "n", "workers", "tiempo_segundos", "repeticion"}
    if not esperado.issubset(df.columns):
        sys.exit(f"Error: {ruta} no tiene las columnas {sorted(esperado)}")
    return df


def promedios(df):
    """Tiempo promedio (y cantidad de repeticiones) por tipo, n y workers."""
    g = df.groupby(["tipo", "n", "workers"])["tiempo_segundos"]
    out = g.agg(["mean", "count"]).reset_index()
    out.columns = ["tipo", "n", "workers", "tiempo_prom", "repeticiones"]
    return out


def rotulo_omp(clave):
    """'openmp_collapse 8' -> 'OpenMP collapse (8 hilos)'"""
    nombre, w = clave.split()
    variante = nombre.split("_", 1)[1] if "_" in nombre else "externo"
    return f"OpenMP {variante} ({w} hilos)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--paralelo", default="resultados.csv")
    ap.add_argument("--flags", default="resultados_flags.csv")
    ap.add_argument("--traspuesta", default="resultados_traspuesta.csv")
    ap.add_argument("--openmp", default="resultados_openmp.csv")
    ap.add_argument("--openmp-o0", default="resultados_openmp_O0.csv",
                    help="variantes de OpenMP compiladas con -O0 (selección de directiva)")
    ap.add_argument("--baseline", choices=["o2", "o0"], default="o2")
    ap.add_argument("--omp-hilos", type=int, default=8,
                    help="nº de hilos con el que se comparan las variantes de OpenMP (por defecto 8 = hilos lógicos)")
    args = ap.parse_args()

    par = cargar(args.paralelo, obligatorio=True)
    flg = cargar(args.flags, silencioso=True)
    trs = cargar(args.traspuesta, silencioso=True)
    omp = cargar(args.openmp)

    todos = pd.concat([d for d in (par, flg, trs, omp) if d is not None], ignore_index=True)
    prom = promedios(todos)

    # ---------- Baseline ----------
    if args.baseline == "o2":
        base_df = prom[(prom.tipo == "secuencial")]
        etiqueta_base = "secuencial -O2"
    else:
        if flg is None or not (flg.tipo == "O0").any():
            sys.exit("Error: baseline o0 requiere datos de tipo O0 en resultados_flags.csv")
        base_df = prom[(prom.tipo == "O0")]
        etiqueta_base = "secuencial -O0"
        print("AVISO: con baseline O0, los speedups de hilos/procesos (compilados con -O2)\n"
              "       incluyen el efecto del compilador además del paralelismo.\n")

    base = base_df.set_index("n")["tiempo_prom"].sort_index()
    ns = list(base.index)
    print(f"Baseline: {etiqueta_base}; tamaños: {ns}")

    # ---------- Speedup de cada curva ----------
    curvas = {}  # etiqueta -> Serie indexada por n
    for (tipo, w), sub in prom.groupby(["tipo", "workers"]):
        if tipo == "secuencial":
            continue
        serie = sub.set_index("n")["tiempo_prom"]
        sp = (base / serie).reindex(ns)
        if tipo in ("hilos", "procesos") or tipo.startswith("openmp"):
            etiqueta = f"{tipo} {w}"
        elif tipo == "traspuesta":
            etiqueta = "traspuesta"
        elif tipo in ("O0", "O1", "O2", "O3", "Ofast"):  # flags de compilación
            etiqueta = f"-{tipo}"
        else:
            print(f"(aviso) tipo desconocido '{tipo}', se omite")
            continue
        curvas[etiqueta] = sp

    # ---------- Tablas ----------
    tabla_prom = prom.pivot_table(index=["tipo", "workers"], columns="n", values="tiempo_prom")
    tabla_prom.round(4).to_csv("tabla_promedios.csv")
    tabla_sp = pd.DataFrame(curvas).T[ns]
    tabla_sp.round(3).to_csv("tabla_speedup.csv")
    print("\nSpeedup (T_baseline / T_técnica):")
    print(tabla_sp.round(3).to_string())

    # ---------- Mejor de cada familia (mayor speedup promedio sobre los tamaños) ----------
    def mejor(prefijo, excluir=()):
        cand = {k: v for k, v in curvas.items()
                if k.startswith(prefijo) and k not in excluir and v.notna().any()}
        if not cand:
            return None
        return max(cand, key=lambda k: cand[k].mean())

    mejor_flag = mejor("-", excluir=("-O0",))
    mejor_hilos = mejor("hilos")
    mejor_procesos = mejor("procesos")
    mejor_omp = mejor("openmp")
    print("\nMejores por familia (mayor speedup promedio):")
    for nombre, val in (("flag", mejor_flag), ("hilos", mejor_hilos),
                        ("procesos", mejor_procesos), ("openmp", mejor_omp)):
        if val:
            print(f"  {nombre:9s}: {val}  (promedio {curvas[val].mean():.3f})")

    # ---------- Gráfica 1: flags ----------
    flags_presentes = [k for k in curvas if k.startswith("-")]
    if flags_presentes:
        plt.figure(figsize=(9, 5.5))
        for k in flags_presentes:
            plt.plot(ns, curvas[k], marker="o", label=k)
        plt.axhline(1.0, color="gray", linestyle=":", linewidth=1)
        plt.xlabel("N (tamaño de la matriz cuadrada)")
        plt.ylabel(f"Speedup vs {etiqueta_base}")
        plt.title("Optimización por compilación (versión secuencial)")
        plt.grid(True, linestyle="--", alpha=0.4)
        plt.legend()
        plt.tight_layout()
        plt.savefig("grafica_flags.png", dpi=150)
        plt.close()

    # ---------- Variantes de OpenMP (-O2) vs secuencial -O2 de la primera entrega ----------
    sufijo = f" {args.omp_hilos}"
    variantes = [k for k in curvas if k.startswith("openmp") and k.endswith(sufijo)]
    if variantes:
        plt.figure(figsize=(9, 5.5))
        for k in sorted(variantes):
            plt.plot(ns, curvas[k], marker="o", label=rotulo_omp(k))
        plt.axhline(1.0, color="gray", linestyle=":", linewidth=1)
        plt.xlabel("N (tamaño de la matriz cuadrada)")
        plt.ylabel(f"Speedup vs {etiqueta_base}")
        plt.title(f"OpenMP: ubicación de la directiva ({args.omp_hilos} hilos)")
        plt.grid(True, linestyle="--", alpha=0.4)
        plt.legend()
        plt.tight_layout()
        plt.savefig("grafica_openmp.png", dpi=150)
        plt.close()
    else:
        print(f"(aviso) no hay curvas de OpenMP con {args.omp_hilos} hilos; se omite grafica_openmp.png")

    # ---------- Una gráfica de variantes por cada nº de hilos medido (distinto al principal) ----------
    cuentas = sorted({k.split()[-1] for k in curvas if k.startswith("openmp")}, key=int)
    for w in cuentas:
        if int(w) == args.omp_hilos:
            continue
        vs = [k for k in curvas if k.startswith("openmp") and k.endswith(f" {w}")]
        if not vs:
            continue
        plt.figure(figsize=(9, 5.5))
        for k in sorted(vs):
            plt.plot(ns, curvas[k], marker="o", label=rotulo_omp(k))
        plt.axhline(1.0, color="gray", linestyle=":", linewidth=1)
        plt.xlabel("N (tamaño de la matriz cuadrada)")
        plt.ylabel(f"Speedup vs {etiqueta_base}")
        plt.title(f"OpenMP: ubicación de la directiva ({w} hilos)")
        plt.grid(True, linestyle="--", alpha=0.4)
        plt.legend()
        plt.tight_layout()
        plt.savefig(f"grafica_openmp_{w}hilos.png", dpi=150)
        plt.close()

    # ---------- Selección de directiva de OpenMP: código SIN optimizar (-O0) ----------
    # Baseline = secuencial -O0 (resultados_flags.csv). Aísla el efecto de la directiva:
    # lo único que cambia entre el baseline y cada variante es el pragma.
    omp0 = cargar(args.openmp_o0, silencioso=True)
    if omp0 is not None and flg is not None and (flg.tipo == "O0").any():
        p0 = promedios(omp0)
        b0 = promedios(flg[flg.tipo == "O0"]).set_index("n")["tiempo_prom"].sort_index()
        cur0 = {}
        for (tipo, w), sub in p0.groupby(["tipo", "workers"]):
            serie = sub.set_index("n")["tiempo_prom"]
            comunes = [n for n in serie.index if n in b0.index]
            cur0[f"{tipo} {w}"] = (b0.loc[comunes] / serie.loc[comunes])
        t0 = pd.DataFrame(cur0).T.sort_index(axis=1)
        t0.round(3).to_csv("tabla_openmp_seleccion.csv")
        print("\nOpenMP, selección de directiva (speedup vs secuencial -O0, sin optimizar):")
        print(t0.round(3).to_string())
        plt.figure(figsize=(9, 5.5))
        for k in sorted(cur0):
            plt.plot(cur0[k].index, cur0[k].values, marker="o", label=rotulo_omp(k))
        plt.axhline(1.0, color="gray", linestyle=":", linewidth=1)
        plt.xlabel("N (tamaño de la matriz cuadrada)")
        plt.ylabel("Speedup vs secuencial -O0")
        plt.title("OpenMP: ubicación de la directiva (sin optimización de compilación)")
        plt.grid(True, linestyle="--", alpha=0.4)
        plt.legend()
        plt.tight_layout()
        plt.savefig("grafica_openmp_O0.png", dpi=150)
        plt.close()
    else:
        pass

    # ---------- Gráfica 2: comparación de técnicas ----------
    seleccion = [(mejor_flag, f"Compilación ({mejor_flag})" if mejor_flag else None),
                 ("traspuesta" if "traspuesta" in curvas else None, "Matriz traspuesta"),
                 (mejor_hilos, f"Hilos pthread ({mejor_hilos.split()[1]})" if mejor_hilos else None),
                 (mejor_procesos, f"Procesos fork ({mejor_procesos.split()[1]})" if mejor_procesos else None),
                 (mejor_omp, rotulo_omp(mejor_omp) if mejor_omp else None)]
    plt.figure(figsize=(9, 5.5))
    hay = False
    for clave, rotulo in seleccion:
        if clave:
            plt.plot(ns, curvas[clave], marker="o", label=rotulo)
            hay = True
    if hay:
        plt.axhline(1.0, color="gray", linestyle=":", linewidth=1)
        plt.xlabel("N (tamaño de la matriz cuadrada)")
        plt.ylabel(f"Speedup vs {etiqueta_base}")
        plt.title("Comparación de técnicas de optimización")
        plt.grid(True, linestyle="--", alpha=0.4)
        plt.legend()
        plt.tight_layout()
        plt.savefig("grafica_tecnicas.png", dpi=150)
    plt.close()

    print("\nGenerados: tabla_promedios.csv, tabla_speedup.csv, grafica_openmp*.png, grafica_tecnicas.png")


if __name__ == "__main__":
    main()
