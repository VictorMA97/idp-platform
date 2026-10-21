#!/usr/bin/env bash
# Comprueba que el entorno (WSL2 + Docker + herramientas) está listo.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Comprobando herramientas"
for bin in docker k3d kubectl git; do need "$bin"; done
docker info >/dev/null 2>&1 \
  || die "Docker no responde. ¿Está arrancado y con la integración WSL activada?"

case "$ROOT_DIR" in
  /mnt/*)
    warn "El repo está en $ROOT_DIR (disco de Windows). Muévelo a ~/ dentro de WSL: el I/O es mucho más lento."
    ;;
esac

mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
log "Memoria visible desde WSL: ~${mem_gb} GB"
if (( mem_gb < 14 )); then
  warn "Menos de 14 GB visibles. Revisa memory= en %UserProfile%\\.wslconfig (ver docs/wslconfig.example)."
fi

# Puertos de host usados por cada clúster (solo se comprueban los que aún no existen)
declare -A PORTS=( [mgmt]="8080 8443" [dev]="8081 8444" [prod]="8082 8445" )
if command -v ss >/dev/null 2>&1; then
  busy=0
  for c in "${CLUSTERS[@]}"; do
    cluster_exists "$c" && continue
    for p in ${PORTS[$c]}; do
      if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"; then
        warn "Puerto $p ocupado (lo necesita el clúster $c)"
        busy=1
      fi
    done
  done
  (( busy == 0 )) || die "Libera los puertos indicados o cámbialos en clusters/*.yaml"
fi
warn "Nota: ss solo ve puertos dentro de WSL; si algo de Windows usa 8080 el bind puede fallar igualmente."

log "Preflight OK"
