#!/usr/bin/env bash
# Crea (o actualiza) el Secret 'backstage-secrets' en el namespace 'backstage' del clúster mgmt.
# Nada de esto va a Git. Los valores se leen de variables de entorno o se piden por pantalla
# (sin eco) y se pasan a kubectl por entrada estándar, no por argumentos.
#
# Variables (o se piden):
#   AUTH_GITHUB_CLIENT_ID      Client ID de la OAuth App de GitHub
#   AUTH_GITHUB_CLIENT_SECRET  Client Secret de la OAuth App
#   GITHUB_TOKEN               Token de GitHub (fine-grained, solo lectura de repos públicos)
#
# BACKEND_SECRET y POSTGRES_PASSWORD se generan al azar la primera vez y se CONSERVAN después:
# cambiar la contraseña de PostgreSQL con la base de datos ya creada rompería la conexión.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need kubectl
need openssl
C="$(ctx mgmt)"
NS=backstage
K="kubectl --context $C"

$K get nodes >/dev/null 2>&1 || die "No se puede contactar con el clúster $C. ¿Está levantado? (make up)"

ask() { # ask VAR "descripción" [secreto]
  local var="$1" desc="$2" secret="${3:-}" val
  val="${!var:-}"
  if [[ -z "$val" ]]; then
    [[ -t 0 ]] || die "Falta $var (no hay terminal para pedirla)"
    if [[ -n "$secret" ]]; then read -rsp "$desc: " val; echo; else read -rp "$desc: " val; fi
  fi
  [[ -n "$val" ]] || die "$var no puede estar vacío"
  [[ "$val" != *$'\n'* ]] || die "$var no puede contener saltos de línea"
  printf -v "$var" '%s' "$val"
}

ask AUTH_GITHUB_CLIENT_ID     "Client ID de la OAuth App"
ask AUTH_GITHUB_CLIENT_SECRET "Client Secret de la OAuth App" secret
ask GITHUB_TOKEN              "Token de GitHub (solo lectura)" secret

# Conserva los valores generados si el Secret ya existe
existing() { $K -n "$NS" get secret backstage-secrets -o "jsonpath={.data.$1}" 2>/dev/null | base64 -d 2>/dev/null || true; }
POSTGRES_PASSWORD="$(existing POSTGRES_PASSWORD)"
BACKEND_SECRET="$(existing BACKEND_SECRET)"
[[ -n "$POSTGRES_PASSWORD" ]] || POSTGRES_PASSWORD="$(openssl rand -hex 24)"
[[ -n "$BACKEND_SECRET" ]]    || BACKEND_SECRET="$(openssl rand -hex 32)"

$K get namespace "$NS" >/dev/null 2>&1 || $K create namespace "$NS" >/dev/null

# --from-env-file=/dev/stdin: los valores no aparecen en la lista de procesos
{
  printf 'POSTGRES_PASSWORD=%s\n' "$POSTGRES_PASSWORD"
  printf 'BACKEND_SECRET=%s\n' "$BACKEND_SECRET"
  printf 'AUTH_GITHUB_CLIENT_ID=%s\n' "$AUTH_GITHUB_CLIENT_ID"
  printf 'AUTH_GITHUB_CLIENT_SECRET=%s\n' "$AUTH_GITHUB_CLIENT_SECRET"
  printf 'GITHUB_TOKEN=%s\n' "$GITHUB_TOKEN"
} | $K -n "$NS" create secret generic backstage-secrets --from-env-file=/dev/stdin \
      --dry-run=client -o yaml | $K apply -f - >/dev/null

log "Secret backstage-secrets creado/actualizado en $C/$NS"
warn "Si cambiaste las credenciales de GitHub con Backstage ya en marcha, reinicia el pod:"
warn "  kubectl --context $C -n $NS rollout restart deploy/backstage"
