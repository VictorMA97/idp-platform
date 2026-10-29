#!/usr/bin/env bash
# Deshace lo que la puesta en marcha escribió en este repo y destruye los clústeres, para empezar de cero.
#
# Qué revierte (solo ficheros de ESTE repo; no hace commit ni push):
#   1. La URL de tu repo en los manifiestos (lo que hizo `make set-repo`) -> vuelve a __REPO_URL__
#   2. platform/apps/sample-app-appset.yaml y backstage-app.yaml (generados por `make sample-app` y `make backstage`)
#   3. Las políticas de Kyverno en dev, prod y mgmt -> modo Audit (lo que cambió `make policies-mode`)
#   4. platform/services/svc-*.yaml (los pull requests que abre Backstage al crear servicios)
#   5. Los clústeres y la red (`make down`). Se pierden el Secret backstage-secrets y los datos de PostgreSQL.
#
# NO toca: los otros repos (idp-backstage, idp-sample-app, svc-*), los paquetes de GHCR ni GitHub.
#
# Variables:  FORCE=1 (no pedir confirmación) · DRY_RUN=1 (solo mostrar el plan)
#             KEEP_CLUSTERS=1 (no destruir los clústeres) · KEEP_SERVICES=1 (no borrar platform/services/svc-*.yaml)
# Uso: make rollback [FORCE=1] [DRY_RUN=1] [KEEP_CLUSTERS=1] [KEEP_SERVICES=1]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FORCE="${FORCE:-0}"; DRY_RUN="${DRY_RUN:-0}"
KEEP_CLUSTERS="${KEEP_CLUSTERS:-0}"; KEEP_SERVICES="${KEEP_SERVICES:-0}"
cd "$ROOT_DIR" || exit 1

# 1) Manifiestos con una URL de repo ya escrita (la línea lleva el marcador y no es el placeholder)
mapfile -t url_files < <(grep -rlE 'repoURL: .*# idp:repo-url' platform \
  | while read -r f; do grep -E 'repoURL: .*# idp:repo-url' "$f" | grep -qv '__REPO_URL__' && echo "$f"; done || true)

# 2) Ficheros generados a partir de plantillas
generated=()
for f in platform/apps/sample-app-appset.yaml platform/apps/backstage-app.yaml; do
  [[ -f "$f" ]] && generated+=("$f")
done

# 3) Políticas en Deny (líneas marcadas)
mapfile -t deny_files < <(grep -rl '# idp:policy-mode' platform 2>/dev/null \
  | while read -r f; do grep -E '# idp:policy-mode' "$f" | grep -q '\[Deny\]' && echo "$f"; done || true)

# 4) Servicios registrados por Backstage
services=()
if [[ "$KEEP_SERVICES" != "1" ]]; then
  shopt -s nullglob
  for f in platform/services/svc-*.yaml; do services+=("$f"); done
  shopt -u nullglob
fi

log "Plan de rollback (repo: $ROOT_DIR)"
show() { local title="$1"; shift; if (( $# )); then printf '  %s\n' "$title"; printf '      %s\n' "$@"; else printf '  %s: nada que hacer\n' "$title"; fi; }
show "URL del repo -> __REPO_URL__:" "${url_files[@]}"
show "Ficheros generados a borrar:" "${generated[@]}"
show "Políticas Deny -> Audit:" "${deny_files[@]}"
if [[ "$KEEP_SERVICES" == "1" ]]; then echo "  Servicios svc-*: se conservan (KEEP_SERVICES=1)"; else show "Servicios a borrar:" "${services[@]}"; fi
if [[ "$KEEP_CLUSTERS" == "1" ]]; then
  echo "  Clústeres: se conservan (KEEP_CLUSTERS=1). Con Git revertido y los clústeres vivos, Argo CD dejará de sincronizar."
else
  echo "  Clústeres mgmt, dev y prod y la red $NETWORK_NAME: SE DESTRUYEN (secretos de Backstage y datos de PostgreSQL incluidos)"
fi

if [[ "$DRY_RUN" == "1" ]]; then log "DRY_RUN=1: no se ha cambiado nada"; exit 0; fi

if [[ "$FORCE" != "1" ]]; then
  [[ -t 0 ]] || die "Hace falta confirmar y no hay terminal. Repite con FORCE=1 (o DRY_RUN=1 para solo ver el plan)."
  warn "Esto no se puede deshacer salvo con git (ficheros) o repitiendo la puesta en marcha (clústeres)."
  read -rp "Escribe 'si' para continuar: " answer
  [[ "$answer" == "si" ]] || die "Cancelado"
fi

for f in "${url_files[@]}"; do
  sed -i 's|repoURL: .*# idp:repo-url|repoURL: __REPO_URL__  # idp:repo-url|' "$f"
  log "URL restaurada en $f"
done
for f in "${generated[@]}"; do rm -f "$f"; log "Borrado $f"; done
for f in "${deny_files[@]}"; do
  sed -i '/# idp:policy-mode/ s/validationActions: \[Deny\]/validationActions: [Audit]/' "$f"
  log "Audit en $f"
done
for f in "${services[@]}"; do rm -f "$f"; log "Borrado $f"; done

if [[ "$KEEP_CLUSTERS" != "1" ]]; then
  "$ROOT_DIR/scripts/down.sh"
fi

log "Hecho. Repo revertido (sin commit)."
warn "Revisa con 'git status' y 'git diff', y haz commit y push para que GitHub quede igual:"
warn "  git add -A && git commit -m 'Reinicia la plataforma' && git push"
warn "Después, sigue el README desde la Etapa 1 (make up). Los otros repos y los paquetes de GHCR no se han tocado."
