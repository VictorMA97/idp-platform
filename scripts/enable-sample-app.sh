#!/usr/bin/env bash
# Activa la app de ejemplo (OPCIONAL): genera platform/apps/sample-app-appset.yaml desde la plantilla
# y la autoriza en las políticas de Kyverno de dev/prod. Sin esto, la plataforma solo admite svc-*.
# Para quitarla: scripts/disable-sample-app.sh
# Idempotente: se puede repetir con otra URL.
# Uso: scripts/enable-sample-app.sh https://github.com/<usuario>/idp-sample-app.git
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP_REPO_URL="${1:-}"
[[ -n "$APP_REPO_URL" ]] || die "Uso: scripts/enable-sample-app.sh https://github.com/<usuario>/idp-sample-app.git"

# Argo CD no tiene claves SSH configuradas: se convierte cualquier URL SSH a HTTPS
if [[ "$APP_REPO_URL" =~ ^(ssh://)?git@github\.com[:/](.+)$ ]]; then
  APP_REPO_URL="https://github.com/${BASH_REMATCH[2]}"
  warn "URL SSH convertida a HTTPS: $APP_REPO_URL"
fi
[[ "$APP_REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+$ ]] \
  || die "La URL debe tener la forma https://github.com/<usuario>/<repo>"

need git
git ls-remote "$APP_REPO_URL" HEAD >/dev/null 2>&1 \
  || die "No se puede leer $APP_REPO_URL sin credenciales. ¿Existe, tiene commits y es público?"

TEMPLATE="$ROOT_DIR/platform/templates/sample-app-appset.yaml.tpl"
TARGET="$ROOT_DIR/platform/apps/sample-app-appset.yaml"
[[ -f "$TEMPLATE" ]] || die "Falta la plantilla $TEMPLATE"

sed "s|__APP_REPO_URL__|${APP_REPO_URL}|" "$TEMPLATE" > "$TARGET"
log "Generado ${TARGET#"$ROOT_DIR"/}"
"$(dirname "${BASH_SOURCE[0]}")/sample-app-policies.sh" on
log "Políticas de Kyverno: idp-sample-app autorizada (platform/policies)"

warn "Haz commit y push: Argo CD (platform-root) detectará el nuevo ApplicationSet y creará sample-app-dev y sample-app-prod."
warn "Hasta que el pipeline de la app publique su primera imagen, los pods quedarán en ImagePullBackOff (es lo esperado)."
