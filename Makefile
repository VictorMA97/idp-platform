SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

REPO_URL ?=
HUB := k3d-mgmt

.PHONY: help preflight up clusters argocd spokes set-repo root status argocd-password urls down

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
	@echo "  2) git add -A && git commit -m 'Configura repo' && git push"
	@echo "  3) make root"

set-repo: ## Apunta los manifiestos a tu repo: make set-repo REPO_URL=...
	@./scripts/set-repo.sh "$(REPO_URL)"

root: ## Aplica la app raíz (app-of-apps) y activa GitOps
	@./scripts/apply-root.sh

status: ## Estado de las aplicaciones de Argo CD
	@kubectl --context $(HUB) -n argocd get applications,applicationsets

argocd-password: ## Muestra la contraseña inicial de admin de Argo CD
	@kubectl --context $(HUB) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

urls: ## Muestra las URLs de acceso
	@echo "Argo CD : http://argocd.localtest.me:8080"
	@echo "dev     : http://*.localtest.me:8081   (ingress del spoke dev)"
	@echo "prod    : http://*.localtest.me:8082   (ingress del spoke prod)"

down: ## Elimina clústeres y red (destruye todo)
	@./scripts/down.sh
