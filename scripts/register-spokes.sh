#!/usr/bin/env bash
# Registra dev y prod en Argo CD (hub mgmt) de forma declarativa.
# Crea un ServiceAccount en cada spoke y un Secret de tipo "cluster" en mgmt.
# Se usa el nombre interno del balanceador (red docker idp-net), no 0.0.0.0.
#
# Si la verificación TLS falla en tu entorno: SPOKE_INSECURE=1 make spokes
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl
SPOKE_INSECURE="${SPOKE_INSECURE:-0}"
HUB="$(ctx mgmt)"

for env in "${SPOKES[@]}"; do
  c="$(ctx "$env")"
  log "Registrando $env en Argo CD"

  kubectl --context "$c" apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
EOF

  token_b64=""
  for _ in $(seq 1 30); do
    token_b64="$(kubectl --context "$c" -n kube-system get secret argocd-manager-token \
      -o jsonpath='{.data.token}' 2>/dev/null || true)"
    [[ -n "$token_b64" ]] && break
    sleep 1
  done
  [[ -n "$token_b64" ]] || die "No se generó el token del ServiceAccount en $env"

  token="$(printf '%s' "$token_b64" | base64 -d)"
  # CA con la que kubectl verifica la API de este clúster (la misma que debe usar Argo CD)
  ca_b64="$(kubectl --context "$c" config view --raw --minify \
    -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
  [[ -n "$ca_b64" ]] || die "No se pudo leer la CA de $env desde el kubeconfig"

  if [[ "$SPOKE_INSECURE" == "1" ]]; then
    warn "SPOKE_INSECURE=1: Argo CD NO verificará el certificado de $env (solo laboratorio)"
    tls='{"insecure":true}'
  else
    tls="{\"insecure\":false,\"caData\":\"${ca_b64}\"}"
  fi

  kubectl --context "$HUB" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cluster-${env}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    idp.dev/role: spoke
    env: ${env}
type: Opaque
stringData:
  name: ${env}
  server: https://k3d-${env}-serverlb:6443
  config: |
    {"bearerToken":"${token}","tlsClientConfig":${tls}}
EOF
done

log "Spokes registrados. Comprueba el estado en la UI (Settings → Clusters)"
