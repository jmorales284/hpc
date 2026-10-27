#!/usr/bin/env bash
export LC_ALL=C   # decimales con punto aunque el sistema esté en español (evita errores en awk/CSV)
#
# perfilar.sh -- caracterización (perfilado) de CPU y memoria de UN ejecutable.
#
# Uso:
#   ./perfilar.sh <etiqueta> <binario> <n> [workers]
#
# Qué mide:
#   - Con /usr/bin/time -v  : % de CPU usado, memoria máxima (RSS), fallos de
#                             página, cambios de contexto (voluntarios/involuntarios).
#   - Con perf stat         : ciclos, instrucciones, IPC (instrucciones por ciclo),
#                             referencias a caché, fallos de caché y % de fallos.
#
# Agrega una fila a perfilado.csv y guarda la salida cruda en perfil_raw.txt
# (útil para citar en el informe). Si falta alguna herramienta, esa parte
# queda como NA en vez de fallar.
#
# Instalación en Ubuntu (una vez):
#   sudo apt install time linux-tools-common linux-tools-generic
# Permisos de perf (si da "permission denied"):
#   sudo sysctl -w kernel.perf_event_paranoid=1

set -u

if [ $# -lt 3 ]; then
    echo "Uso: $0 <etiqueta> <binario> <n> [workers]" >&2
    exit 1
fi

ETIQ="$1"; BIN="$2"; N="$3"; W="${4:-}"
MAXVAL="${MAXVAL:-10}"
SALIDA="${SALIDA:-perfilado.csv}"
RAW="${RAW:-perfil_raw.txt}"
TIME_BIN="${TIME_BIN:-/usr/bin/time}"

CMD=("$BIN" "$N" "$MAXVAL")
[ -n "$W" ] && CMD+=("$W")
W_CSV="${W:-1}"

tmp_t=$(mktemp); tmp_p=$(mktemp)
trap 'rm -f "$tmp_t" "$tmp_p"' EXIT

na() { [ -n "$1" ] && echo "$1" || echo "NA"; }

# ---------- 1) CPU y memoria: time -v ----------
tiempo="NA"; cpu="NA"; rss="NA"; minf="NA"; majf="NA"; cvol="NA"; cinv="NA"
if [ -x "$TIME_BIN" ]; then
    salida=$("$TIME_BIN" -v "${CMD[@]}" 2>"$tmp_t")
    tiempo=$(na "$(echo "$salida" | cut -d',' -f3)")
    rss=$(na "$(awk -F': ' '/Maximum resident set size/ {print $2}' "$tmp_t")")
    cpu=$(na "$(awk -F': ' '/Percent of CPU this job got/ {gsub("%","",$2); print $2}' "$tmp_t")")
    minf=$(na "$(awk -F': ' '/Minor \(reclaiming a frame\) page faults/ {print $2}' "$tmp_t")")
    majf=$(na "$(awk -F': ' '/Major \(requiring I\/O\) page faults/ {print $2}' "$tmp_t")")
    cvol=$(na "$(awk -F': ' '/Voluntary context switches/ && !/Involuntary/ {print $2}' "$tmp_t")")
    cinv=$(na "$(awk -F': ' '/Involuntary context switches/ {print $2}' "$tmp_t")")
else
    echo "Aviso: no se encontró $TIME_BIN (sudo apt install time). CPU/memoria quedan en NA." >&2
    salida=$("${CMD[@]}")
    tiempo=$(na "$(echo "$salida" | cut -d',' -f3)")
fi

# ---------- 2) Contadores de hardware: perf stat ----------
ciclos="NA"; instr="NA"; ipc="NA"; crefs="NA"; cmiss="NA"; cpct="NA"
if command -v perf >/dev/null 2>&1; then
    perf stat -x, -e cycles,instructions,cache-references,cache-misses \
        "${CMD[@]}" >/dev/null 2>"$tmp_p"

    ev() {  # extrae el valor de un evento; vacío si no es numérico
        awk -F, -v ev="$1" '$3 ~ ("(^|/)" ev "(:[a-z]+)?/?$") && $1 ~ /^[0-9]+$/ {print $1; exit}' "$tmp_p"
    }
    ciclos=$(na "$(ev cycles)")
    instr=$(na "$(ev instructions)")
    crefs=$(na "$(ev cache-references)")
    cmiss=$(na "$(ev cache-misses)")

    if [ "$ciclos" != "NA" ] && [ "$instr" != "NA" ]; then
        ipc=$(awk -v i="$instr" -v c="$ciclos" 'BEGIN{printf "%.3f", i/c}')
    fi
    if [ "$crefs" != "NA" ] && [ "$cmiss" != "NA" ] && [ "$crefs" -gt 0 ]; then
        cpct=$(awk -v m="$cmiss" -v r="$crefs" 'BEGIN{printf "%.2f", 100*m/r}')
    fi
else
    echo "Aviso: no se encontró perf (sudo apt install linux-tools-generic). Contadores en NA." >&2
fi

# ---------- Salida ----------
if [ ! -f "$SALIDA" ]; then
    echo "etiqueta,n,workers,tiempo_s,cpu_pct,rss_max_kb,fallos_pag_menores,fallos_pag_mayores,ctx_voluntarios,ctx_involuntarios,ciclos,instrucciones,ipc,cache_refs,cache_misses,cache_miss_pct" > "$SALIDA"
fi
echo "${ETIQ},${N},${W_CSV},${tiempo},${cpu},${rss},${minf},${majf},${cvol},${cinv},${ciclos},${instr},${ipc},${crefs},${cmiss},${cpct}" >> "$SALIDA"

{
    echo "################ ${ETIQ} n=${N} workers=${W_CSV} ################"
    echo "--- time -v ---";  cat "$tmp_t"
    echo "--- perf stat ---"; cat "$tmp_p"
    echo
} >> "$RAW"

echo "[perfil] ${ETIQ} n=${N} w=${W_CSV}: t=${tiempo}s cpu=${cpu}% rss=${rss}KB ipc=${ipc} miss=${cpct}%"
