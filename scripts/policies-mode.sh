#!/usr/bin/env bash
# Cambia las políticas de Kyverno entre auditoría (solo registra) y bloqueo (rechaza).
# Uso: scripts/policies-mode.sh audit|deny
#      TARGET=spokes|mgmt|all  (por defecto spokes: dev y prod; mgmt = clúster de gestión)
#      make policies-mode MODE=deny TARGET=mgmt
# Solo toca las líneas marcadas con '# idp:policy-mode'. Hay que hacer commit y push después.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODE="${1:-}"
case "$MODE" in
  audit) from='\[Deny\]';  to='[Audit]' ;;
  deny)  from='\[Audit\]'; to='[Deny]'  ;;
  *) die "Uso: scripts/policies-mode.sh audit|deny   (TARGET=spokes|mgmt|all)" ;;
esac

TARGET="${TARGET:-spokes}"
case "$TARGET" in
  spokes) dirs=(platform/policies) ;;
  mgmt)   dirs=(platform/policies-mgmt) ;;
  all)    dirs=(platform/policies platform/policies-mgmt) ;;
  *) die "TARGET debe ser spokes, mgmt o all" ;;
esac

files=()
for d in "${dirs[@]}"; do
  [[ -d "$ROOT_DIR/$d" ]] || die "No existe $d"
  mapfile -t found < <(grep -rl '# idp:policy-mode' "$ROOT_DIR/$d" || true)
  [[ ${#found[@]} -gt 0 ]] || die "No se encontraron marcadores '# idp:policy-mode' en $d"
  files+=("${found[@]}")
done

for f in "${files[@]}"; do
  sed -i "/# idp:policy-mode/ s/validationActions: ${from}/validationActions: ${to}/" "$f"
  log "${f#"$ROOT_DIR"/}: $(grep 'idp:policy-mode' "$f" | sed 's/^ *//')"
done

if [[ "$MODE" == "deny" ]]; then
  warn "Antes de hacer push, confirma en modo audit que la imagen firmada PASA: make test-policies POLICY_ENV=<dev|prod|mgmt>"
fi
warn "Haz commit y push: Argo CD aplicará el cambio (destino: ${TARGET})."
