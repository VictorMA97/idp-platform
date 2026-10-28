#!/usr/bin/env bash
# Prueba las políticas de Kyverno de mgmt (namespace backstage) con peticiones "dry-run" de servidor:
# pasan por los webhooks de admisión pero no crean nada.
# Uso: scripts/test-policies-mgmt.sh      (o: make test-policies POLICY_ENV=mgmt)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl
C="$(ctx mgmt)"
NS="backstage"
K="kubectl --context $C"

log "Comprobando que Kyverno y las políticas existen en mgmt"
$K -n kyverno get deploy kyverno-admission-controller >/dev/null 2>&1 \
  || die "Kyverno no está instalado en mgmt (¿ha sincronizado la app kyverno-mgmt en Argo CD?)"
$K get imagevalidatingpolicy verify-image-signatures >/dev/null 2>&1 \
  || die "Falta la política verify-image-signatures (¿ha sincronizado kyverno-policies-mgmt?)"

mode="$($K get validatingpolicy restrict-image-registries -o jsonpath='{.spec.validationActions[0]}')"
log "Modo actual de las políticas: ${mode}"
case "$mode" in Deny|Audit) ;; *) die "Modo inesperado: '$mode'" ;; esac

fails=0
# Pod que cumple el perfil "restricted" de Pod Security (el namespace lo exige): así, si algo lo
# rechaza, es Kyverno y no Pod Security.
pod_manifest() {
  cat <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: policy-test-$1
  namespace: $NS
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: test
      image: "$2"
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
YAML
}

# probar <nombre> <imagen> <esperado en Deny: admitido|rechazado>
probar() {
  local name="$1" image="$2" expected_deny="$3" out rc=0 result expected
  out="$(pod_manifest "$name" "$image" | $K create --dry-run=server -f - -o name 2>&1)" || rc=$?
  if (( rc == 0 )); then result="admitido"; else result="rechazado"; fi
  if [[ "$mode" == "Deny" ]]; then expected="$expected_deny"; else expected="admitido"; fi
  if [[ "$result" == "rechazado" && "$out" != *olicy* && "$out" != *yverno* ]]; then
    printf '  \033[1;31mFALLO\033[0m %-22s rechazado, pero NO por una política de Kyverno:\n        %s\n' \
      "$name" "$(echo "$out" | head -3)"
    fails=$((fails + 1)); return
  fi
  if [[ "$result" == "$expected" ]]; then
    printf '  \033[1;32mOK\033[0m   %-22s %s (esperado: %s)\n' "$name" "$result" "$expected"
  else
    printf '  \033[1;31mFALLO\033[0m %-22s %s (esperado: %s)\n' "$name" "$result" "$expected"
    printf '        %s\n' "$(echo "$out" | head -3)"
    fails=$((fails + 1))
  fi
}

log "Casos de prueba (dry-run en mgmt/$NS)"
probar registro-ajeno   "docker.io/library/nginx:1.27"                rechazado
probar otro-repo-ghcr   "ghcr.io/victorma97/otro-repo:1.0"            rechazado
probar tag-latest       "ghcr.io/victorma97/idp-backstage:latest"     rechazado
# Cumple el prefijo pero no está firmada: debe rechazarla la verificación de firma
probar backstage-sin-firma "ghcr.io/victorma97/idp-backstage:sin-firma" rechazado

current="$($K -n "$NS" get deploy backstage \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
if [[ -n "$current" ]]; then
  log "Imagen en ejecución: $current"
  probar imagen-firmada "$current" admitido
else
  warn "No existe el despliegue backstage: se omite el caso de la imagen firmada."
  warn "Sin ese caso no se demuestra que la verificación de firma ACEPTA la imagen legítima."
fi

pg="$($K -n "$NS" get statefulset backstage-postgres \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
[[ -n "$pg" ]] && probar postgres "$pg" admitido

log "Informes de políticas (los de modo audit tardan unos segundos en aparecer)"
$K -n "$NS" get policyreport 2>/dev/null || warn "Aún no hay informes en $NS"

if (( fails > 0 )); then
  die "$fails caso(s) no coinciden con lo esperado en modo ${mode}"
fi
log "Todos los casos coinciden con lo esperado en modo ${mode}"
if [[ "$mode" == "Audit" ]]; then
  warn "En modo Audit nada se rechaza. Revisa los informes: la imagen firmada debe constar como 'pass'."
fi
