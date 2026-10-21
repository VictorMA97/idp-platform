#!/usr/bin/env bash
# Elimina los tres clústeres y la red docker compartida.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need k3d

for c in "${CLUSTERS[@]}"; do
  if cluster_exists "$c"; then
    log "Eliminando clúster $c"
    k3d cluster delete "$c"
  fi
done

if command -v docker >/dev/null 2>&1 && docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  log "Eliminando red $NETWORK_NAME"
  docker network rm "$NETWORK_NAME" >/dev/null || warn "No se pudo borrar la red $NETWORK_NAME (¿contenedores aún conectados?)"
fi
log "Listo"
