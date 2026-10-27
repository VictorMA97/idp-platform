#!/usr/bin/env bash
# Cambia las políticas de Kyverno entre auditoría (solo registra) y bloqueo (rechaza).
# Uso: scripts/policies-mode.sh audit|deny
# Solo toca las líneas marcadas con '# idp:policy-mode'. Hay que hacer commit y push después.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODE="${1:-}"
case "$MODE" in
  audit) from='\[Deny\]';  to='[Audit]' ;;
  deny)  from='\[Audit\]'; to='[Deny]'  ;;
  *) die "Uso: scripts/policies-mode.sh audit|deny" ;;
esac

mapfile -t files < <(grep -rl '# idp:policy-mode' "$ROOT_DIR/platform/policies" || true)
[[ ${#files[@]} -gt 0 ]] || die "No se encontraron marcadores '# idp:policy-mode' en platform/policies"

for f in "${files[@]}"; do
  sed -i "/# idp:policy-mode/ s/validationActions: ${from}/validationActions: ${to}/" "$f"
  log "${f#"$ROOT_DIR"/}: $(grep 'idp:policy-mode' "$f" | sed 's/^ *//')"
done

if [[ "$MODE" == "deny" ]]; then
  warn "Antes de hacer push, confirma en modo audit que la imagen firmada PASA: make test-policies"
fi
warn "Haz commit y push: Argo CD aplicará el cambio en dev y prod."
