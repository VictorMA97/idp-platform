#!/usr/bin/env bash
# Activa Backstage: genera platform/apps/backstage-app.yaml desde la plantilla.
# Idempotente: se puede repetir con otra URL.
# Uso: scripts/enable-backstage.sh https://github.com/<usuario>/idp-backstage.git
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BACKSTAGE_REPO_URL="${1:-}"
[[ -n "$BACKSTAGE_REPO_URL" ]] || die "Uso: scripts/enable-backstage.sh https://github.com/<usuario>/idp-backstage.git"

# Argo CD no tiene claves SSH configuradas: se convierte cualquier URL SSH a HTTPS
if [[ "$BACKSTAGE_REPO_URL" =~ ^(ssh://)?git@github\.com[:/](.+)$ ]]; then
  BACKSTAGE_REPO_URL="https://github.com/${BASH_REMATCH[2]}"
  warn "URL SSH convertida a HTTPS: $BACKSTAGE_REPO_URL"
fi
[[ "$BACKSTAGE_REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+$ ]] \
  || die "La URL debe tener la forma https://github.com/<usuario>/<repo>"

need git
git ls-remote "$BACKSTAGE_REPO_URL" HEAD >/dev/null 2>&1 \
  || die "No se puede leer $BACKSTAGE_REPO_URL sin credenciales. ¿Existe, tiene commits y es público?"

TEMPLATE="$ROOT_DIR/platform/templates/backstage-app.yaml.tpl"
TARGET="$ROOT_DIR/platform/apps/backstage-app.yaml"
[[ -f "$TEMPLATE" ]] || die "Falta la plantilla $TEMPLATE"

sed "s|__BACKSTAGE_REPO_URL__|${BACKSTAGE_REPO_URL}|" "$TEMPLATE" > "$TARGET"
log "Generado ${TARGET#"$ROOT_DIR"/}"

warn "Antes de hacer push, crea las credenciales en el clúster: make backstage-secrets"
warn "Haz commit y push: Argo CD creará la app 'backstage' en mgmt."
warn "Hasta que el pipeline de Backstage publique su primera imagen, la app dará error de render"
warn "('image.tag o image.digest son obligatorios'): es lo esperado."
