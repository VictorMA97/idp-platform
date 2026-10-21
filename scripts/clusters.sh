#!/usr/bin/env bash
# Crea la red docker compartida y los clústeres mgmt, dev y prod (idempotente).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need docker; need k3d; need kubectl

# Se crea a mano para que k3d la trate como externa y no la borre al eliminar un clúster
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  log "Creando red docker $NETWORK_NAME"
  docker network create "$NETWORK_NAME" >/dev/null
fi

for c in "${CLUSTERS[@]}"; do
  if cluster_exists "$c"; then
    log "Clúster $c ya existe, se omite"
  else
    log "Creando clúster $c"
    k3d cluster create --config "$ROOT_DIR/clusters/$c.yaml"
  fi
done

for c in "${CLUSTERS[@]}"; do
  log "Esperando nodos Ready en $c"
  kubectl --context "$(ctx "$c")" wait --for=condition=Ready nodes --all --timeout=180s
done
