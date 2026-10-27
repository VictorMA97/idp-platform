# Plantilla (NO la sincroniza Argo CD: está fuera de platform/apps).
# scripts/enable-backstage.sh la copia a platform/apps/ con la URL del repo de Backstage.
#
# Backstage es una herramienta de la plataforma, no de un equipo: se despliega UNA vez,
# en el clúster de gestión (mgmt, donde vive Argo CD), no en dev ni en prod.
# El chart y su values-mgmt.yaml viven en el repo de Backstage; el pipeline de CI
# reescribe values-mgmt.yaml con el tag y el digest de la imagen firmada.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backstage
  namespace: argocd
spec:
  project: default
  source:
    repoURL: __BACKSTAGE_REPO_URL__  # idp:backstage-repo-url
    targetRevision: HEAD
    path: chart
    helm:
      valueFiles:
        - values.yaml
        - values-mgmt.yaml
  destination:
    # El clúster donde corre Argo CD (mgmt)
    server: https://kubernetes.default.svc
    namespace: backstage
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/enforce: restricted
        pod-security.kubernetes.io/enforce-version: latest
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 2m
