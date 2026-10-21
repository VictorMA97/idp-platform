#!/usr/bin/env bash
# Entrega el control a GitOps: aplica la app raíz (app-of-apps) en mgmt.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl
if grep -rq '__REPO_URL__' "$ROOT_DIR/platform"; then
  die "Aún hay placeholders de repo. Ejecuta primero: make set-repo REPO_URL=https://github.com/<usuario>/idp-platform.git (y haz push)"
fi

log "Aplicando la app raíz en mgmt"
kubectl --context "$(ctx mgmt)" apply -f "$ROOT_DIR/platform/bootstrap/root-app.yaml"
log "Observa el progreso con: make status"
