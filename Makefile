SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

REPO_URL ?=
HUB := k3d-mgmt

APP_REPO_URL ?=
MODE ?=
POLICY_ENV ?= dev
BACKSTAGE_REPO_URL ?=

.PHONY: help preflight up clusters argocd spokes set-repo set-owner root sample-app sample-app-off policies-mode test-policies backstage backstage-secrets status argocd-password urls down

help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

preflight: ## Comprueba Docker, herramientas, memoria y puertos
	@./scripts/preflight.sh

clusters: ## Crea la red y los clústeres mgmt, dev y prod
	@./scripts/clusters.sh

argocd: ## Instala Argo CD en mgmt y lo expone por ingress
	@./scripts/install-argocd.sh

spokes: ## Registra dev y prod en Argo CD
	@./scripts/register-spokes.sh

up: preflight clusters argocd spokes ## Levanta toda la infraestructura base
	@echo
	@echo "Siguiente paso (GitOps):"
	@echo "  1) make set-repo REPO_URL=https://github.com/$OWNER/idp-platform.git"
	@echo "  2) git add -A && git commit -m 'Configura repo' && git push"
	@echo "  3) make root"

set-repo: ## Apunta los manifiestos a tu repo: make set-repo REPO_URL=...
	@./scripts/set-repo.sh "$(REPO_URL)"

root: ## Aplica la app raíz (app-of-apps) y activa GitOps
	@./scripts/apply-root.sh

set-owner: ## Cuenta de GitHub autorizada en Kyverno: make set-owner OWNER=<usuario>
	@./scripts/set-owner.sh "$(OWNER)"

sample-app: ## (Opcional) Activa la app de ejemplo: make sample-app APP_REPO_URL=...
	@./scripts/enable-sample-app.sh "$(APP_REPO_URL)"

sample-app-off: ## Desactiva la app de ejemplo (borra su appset y la quita de las políticas)
	@./scripts/disable-sample-app.sh

policies-mode: ## Modo de las políticas Kyverno: make policies-mode MODE=audit|deny
	@./scripts/policies-mode.sh "$(MODE)"

test-policies: ## Prueba las políticas Kyverno: make test-policies [POLICY_ENV=dev|prod]
	@./scripts/test-policies.sh "$(POLICY_ENV)"

backstage-secrets: ## Crea las credenciales de Backstage en mgmt (OAuth de GitHub, token); no van a Git
	@./scripts/backstage-secrets.sh
	@kubectl --context $(HUB) -n backstage rollout restart deploy/backstage

rollback: ## Deshace la puesta en marcha para empezar de cero (borra clústeres): make rollback [DRY_RUN=1] [FORCE=1] [KEEP_CLUSTERS=1] [KEEP_SERVICES=1]
	@./scripts/rollback.sh

backstage: ## Activa Backstage: make backstage BACKSTAGE_REPO_URL=https://github.com/<usuario>/idp-backstage.git
	@./scripts/enable-backstage.sh "$(BACKSTAGE_REPO_URL)"

status: ## Estado de las aplicaciones de Argo CD
	@kubectl --context $(HUB) -n argocd get applications,applicationsets

argocd-password: ## Muestra la contraseña inicial de admin de Argo CD
	@kubectl --context $(HUB) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

urls: ## Muestra las URLs de acceso
	@echo "Argo CD : http://argocd.localtest.me:8080"
	@echo "Backstage: http://backstage.localtest.me:8080"
	@echo "dev     : http://*.localtest.me:8081   (ingress del spoke dev)"
	@echo "prod    : http://*.localtest.me:8082   (ingress del spoke prod)"
	@test -f platform/apps/sample-app-appset.yaml && { echo "app dev : http://sample-app.dev.localtest.me:8081"; echo "app prod: http://sample-app.prod.localtest.me:8082"; } || true

down: ## Elimina clústeres y red (destruye todo)
	@./scripts/down.sh
