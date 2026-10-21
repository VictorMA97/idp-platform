#!/usr/bin/env bash
# Instala Argo CD en el clúster mgmt y lo expone en http://argocd.localtest.me:8080
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl
# 'stable' sigue la última versión estable. Para reproducibilidad, fija una versión
# concreta una vez que todo funcione: ARGOCD_VERSION=vX.Y.Z make argocd
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
K="kubectl --context $(ctx mgmt)"

log "Instalando Argo CD (${ARGOCD_VERSION}) en mgmt"
$K create namespace argocd --dry-run=client -o yaml | $K apply -f -
# server-side: el CRD de ApplicationSet es demasiado grande para apply "cliente"
$K apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

log "Esperando a que Argo CD esté disponible"
$K -n argocd wait --for=condition=Available deployment --all --timeout=300s

# TLS lo termina el ingress, así que argocd-server va en modo HTTP interno
log "Configurando argocd-server en modo insecure (TLS en el ingress) y creando ingress"
$K -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}'
$K -n argocd rollout restart deployment argocd-server
$K -n argocd rollout status deployment argocd-server --timeout=180s
$K apply -f "$ROOT_DIR/platform/bootstrap/argocd-ingress.yaml"

version="$($K -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}')"
log "Argo CD instalado: ${version}"
log "UI: http://argocd.localtest.me:8080  (usuario: admin, contraseña: make argocd-password)"
