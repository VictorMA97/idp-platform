#!/usr/bin/env bash
# Prueba las políticas de Kyverno en un spoke con peticiones "dry-run" de servidor:
# pasan por los webhooks de admisión pero no crean nada.
# Uso: scripts/test-policies.sh [dev|prod]      (por defecto, dev)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl
ENVNAME="${1:-dev}"
[[ "$ENVNAME" == "dev" || "$ENVNAME" == "prod" ]] || die "El entorno debe ser dev o prod"
C="$(ctx "$ENVNAME")"
NS="team-demo"
K="kubectl --context $C"

log "Comprobando que Kyverno y las políticas existen en $ENVNAME"
$K -n kyverno get deploy kyverno-admission-controller >/dev/null 2>&1 \
  || die "Kyverno no está instalado en $ENVNAME (¿ha sincronizado la app kyverno-$ENVNAME en Argo CD?)"
$K get imagevalidatingpolicy verify-image-signatures >/dev/null 2>&1 \
  || die "Falta la política verify-image-signatures (¿ha sincronizado kyverno-policies-$ENVNAME?)"

mode="$($K get validatingpolicy restrict-image-registries -o jsonpath='{.spec.validationActions[0]}')"
log "Modo actual de las políticas: ${mode}"
case "$mode" in Deny|Audit) ;; *) die "Modo inesperado: '$mode'" ;; esac

fails=0
# probar <nombre> <imagen> <esperado en Deny: admitido|rechazado>
probar() {
  local name="$1" image="$2" expected_deny="$3" out rc=0 result expected
  out="$($K -n "$NS" run "policy-test-$name" --image="$image" --restart=Never \
        --dry-run=server -o name 2>&1)" || rc=$?
  if (( rc == 0 )); then result="admitido"; else result="rechazado"; fi
  if [[ "$mode" == "Deny" ]]; then expected="$expected_deny"; else expected="admitido"; fi
  if [[ "$result" == "$expected" ]]; then
    printf '  \033[1;32mOK\033[0m   %-22s %s (esperado: %s)\n' "$name" "$result" "$expected"
  else
    printf '  \033[1;31mFALLO\033[0m %-22s %s (esperado: %s)\n' "$name" "$result" "$expected"
    printf '        %s\n' "$(echo "$out" | head -3)"
    fails=$((fails + 1))
  fi
}

log "Casos de prueba (dry-run en $ENVNAME/$NS)"
probar registro-ajeno  "docker.io/library/nginx:1.27"              rechazado
probar otro-repo-ghcr  "ghcr.io/victorma97/otro-repo:1.0"          rechazado
probar tag-latest      "ghcr.io/victorma97/idp-sample-app:latest"  rechazado
# Cumple el prefijo svc- pero no existe ni está firmada: debe rechazarla la verificación de firma
probar svc-sin-firma   "ghcr.io/victorma97/svc-prueba-sin-firma:1.0" rechazado

current="$($K -n "$NS" get deploy "sample-app-$ENVNAME" \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
if [[ -n "$current" ]]; then
  probar imagen-firmada "$current" admitido
else
  warn "No existe el despliegue sample-app-$ENVNAME: se omite el caso de la imagen firmada."
  warn "Sin ese caso no se demuestra que la verificación de firma ACEPTA la imagen legítima."
fi

log "Informes de políticas (los de modo audit tardan unos segundos en aparecer)"
$K -n "$NS" get policyreport 2>/dev/null || warn "Aún no hay informes en $NS"

if (( fails > 0 )); then
  die "$fails caso(s) no coinciden con lo esperado en modo ${mode}"
fi
log "Todos los casos coinciden con lo esperado en modo ${mode}"
if [[ "$mode" == "Audit" ]]; then
  warn "En modo Audit nada se rechaza. Revisa los informes: la imagen firmada debe constar como 'pass'."
fi
