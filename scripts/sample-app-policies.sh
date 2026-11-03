#!/usr/bin/env bash
# Autoriza (on) o retira (off) la app de ejemplo en las políticas de Kyverno de dev/prod.
# La base solo admite svc-*; la app de ejemplo es opcional y se añade con `make sample-app`.
# Uso: scripts/sample-app-policies.sh on|off      (idempotente; solo edita ficheros, no hace git)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$ROOT_DIR/platform/policies/restrict-image-registries.yaml"
V="$ROOT_DIR/platform/policies/verify-image-signatures.yaml"
case "${1:-}" in
  on)
    sed -i "s#^\(.*expression: \)\"\['ghcr.io/<usuario>/svc-'\]\"\(.*idp:allowed-prefixes\)#\1\"['ghcr.io/<usuario>/idp-sample-app', 'ghcr.io/<usuario>/svc-']\"\2#" "$R"
    grep -q 'glob: .*idp-sample-app' "$V" \
      || sed -i "/# idp:glob-anchor/i\\    - glob: 'ghcr.io/<usuario>/idp-sample-app*'  # idp:sample-app" "$V"
    sed -i '/# idp:subject/ s#(svc-\[a-z0-9-\]+)#(idp-sample-app|svc-[a-z0-9-]+)#' "$V"
    ;;
  off)
    sed -i "s#\"\['ghcr.io/<usuario>/idp-sample-app', 'ghcr.io/<usuario>/svc-'\]\"#\"['ghcr.io/<usuario>/svc-']\"#" "$R"
    sed -i '/# idp:sample-app/d' "$V"
    sed -i '/# idp:subject/ s#(idp-sample-app|svc-\[a-z0-9-\]+)#(svc-[a-z0-9-]+)#' "$V"
    ;;
  *) die "Uso: $0 on|off" ;;
esac
