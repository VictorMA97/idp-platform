#!/usr/bin/env bash
# Entrega el control a GitOps: aplica la app raíz (app-of-apps) en mgmt.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl
if grep -rq '__REPO_URL__' "$ROOT_DIR/platform"; then
  die "Aún hay placeholders de repo. Ejecuta primero: make set-repo REPO_URL=https://github.com/<usuario>/idp-platform.git (y haz push)"
fi

# Argo CD lee de GitHub: los cambios locales sin subir no cuentan
if git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
    die "Hay cambios sin commitear. Haz commit y push antes de 'make root'."
  fi
  if [[ -n "$(git -C "$ROOT_DIR" log '@{u}..' --oneline 2>/dev/null)" ]]; then
    die "Hay commits sin subir. Haz 'git push' antes de 'make root'."
  fi
else
  die "Esto no es un repositorio git. Ejecuta git init, añade el remote y haz push."
fi

log "Aplicando la app raíz en mgmt"
kubectl --context "$(ctx mgmt)" apply -f "$ROOT_DIR/platform/bootstrap/root-app.yaml"
log "Observa el progreso con: make status"
