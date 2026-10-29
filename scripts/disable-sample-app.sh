#!/usr/bin/env bash
# Desactiva la app de ejemplo: borra su ApplicationSet y la retira de las políticas de Kyverno.
# Solo edita ficheros; haz commit y push después (Argo CD borrará sample-app-dev/prod).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
rm -f "$ROOT_DIR/platform/apps/sample-app-appset.yaml"
"$(dirname "${BASH_SOURCE[0]}")/sample-app-policies.sh" off
log "App de ejemplo desactivada en el repo."
warn "Haz commit y push: git add -A && git commit -m 'chore: quitar app de ejemplo' && git push"
