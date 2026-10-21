#!/usr/bin/env bash
# Apunta los manifiestos GitOps a TU repositorio. Idempotente: puedes repetirlo.
# Uso: scripts/set-repo.sh https://github.com/<usuario>/idp-platform.git
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO_URL="${1:-}"
[[ -n "$REPO_URL" ]] || die "Uso: scripts/set-repo.sh https://github.com/<usuario>/idp-platform.git"
[[ "$REPO_URL" == *"|"* || "$REPO_URL" == *"&"* ]] && die "La URL contiene caracteres no soportados"

# Las líneas a sustituir llevan el marcador '# idp:repo-url'
mapfile -t files < <(grep -rl '# idp:repo-url' "$ROOT_DIR/platform" || true)
[[ ${#files[@]} -gt 0 ]] || die "No se encontraron marcadores '# idp:repo-url'"

for f in "${files[@]}"; do
  sed -i "s|repoURL: .*# idp:repo-url|repoURL: ${REPO_URL}  # idp:repo-url|" "$f"
  log "Actualizado ${f#"$ROOT_DIR"/}"
done

warn "Haz commit y push antes de 'make root': Argo CD lee desde Git, no desde tu disco."
warn "Usa un repo público (es un portafolio); con uno privado tendrías que dar credenciales a Argo CD."
