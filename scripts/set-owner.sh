#!/usr/bin/env bash
# Cambia la cuenta de GitHub de la que se aceptan imágenes en las políticas de Kyverno (y en sus tests).
# Uso: scripts/set-owner.sh <usuario-de-github>      (o: make set-owner OWNER=<usuario>)
# Idempotente: detecta la cuenta actual y la sustituye. Respeta mayúsculas donde importan:
#   - ghcr.io exige minúsculas (ghcr.io/<usuario>/...)
#   - la identidad de firma de GitHub conserva las mayúsculas (github.com/<Usuario>/...)
# Solo edita ficheros; haz commit y push después.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NEW="${1:-}"
[[ "$NEW" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]] \
  || die "Uso: scripts/set-owner.sh <usuario-de-github>  (letras, números y guiones)"
NEW_LC="$(echo "$NEW" | tr '[:upper:]' '[:lower:]')"

V="$ROOT_DIR/platform/policies/verify-image-signatures.yaml"
CUR="$(sed -nE 's#.*github..com/([^/]+)/.*#\1#p' "$V" | head -1)"
[[ -n "$CUR" ]] || die "No encuentro la cuenta actual en ${V#"$ROOT_DIR"/} (¿se editó a mano el subjectRegExp?)"
CUR_LC="$(echo "$CUR" | tr '[:upper:]' '[:lower:]')"

if [[ "$CUR" == "$NEW" ]]; then log "La cuenta ya es $NEW: nada que cambiar."; exit 0; fi

FILES=(
  platform/policies/verify-image-signatures.yaml
  platform/policies/restrict-image-registries.yaml
  platform/policies-mgmt/verify-image-signatures.yaml
  platform/policies-mgmt/restrict-image-registries.yaml
  scripts/test-policies.sh
  scripts/test-policies-mgmt.sh
  scripts/sample-app-policies.sh
  platform/services/README.md
)
cd "$ROOT_DIR"
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { warn "Falta $f"; continue; }
  sed -i -E "s#\b${CUR}/#${NEW}/#g; s#\b${CUR_LC}/#${NEW_LC}/#g" "$f"
done
log "Cuenta cambiada: $CUR -> $NEW (imágenes en ghcr.io/$NEW_LC/...)"
left="$(grep -rlE "\b(${CUR}|${CUR_LC})/" "${FILES[@]}" 2>/dev/null || true)"
[[ -z "$left" ]] || warn "Aún queda '$CUR' en: $left"
warn "Haz commit y push. Recuerda repetir el cambio en idp-backstage: ./scripts/set-owner.sh $NEW"
