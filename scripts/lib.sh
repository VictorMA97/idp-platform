#!/usr/bin/env bash
# shellcheck disable=SC2034  # las variables las usan los scripts que cargan este fichero
# Funciones y variables comunes. Se carga con:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETWORK_NAME="${NETWORK_NAME:-idp-net}"
CLUSTERS=(mgmt dev prod)
SPOKES=(dev prod)

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Falta '$1'. Consulta la sección Prerrequisitos del README."
}

# Nombre del contexto de kubectl que crea k3d para un clúster
ctx() { echo "k3d-$1"; }

cluster_exists() { k3d cluster get "$1" >/dev/null 2>&1; }
