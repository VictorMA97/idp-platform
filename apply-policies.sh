#!/usr/bin/env bash
# Generaliza las políticas de Kyverno de "solo idp-sample-app" a "idp-sample-app y svc-*".
# Edita los ficheros EN SU SITIO y no toca la línea validationActions: conserva el modo (Audit/Deny)
# en el que estén. Es idempotente: si ya está aplicado, no cambia nada.
# Uso, desde la raíz de idp-platform:   ./apply-policies.sh
set -euo pipefail
command -v python3 >/dev/null || { echo "[x] Falta python3" >&2; exit 1; }
python3 - <<'PY'
import sys
V = 'platform/policies/verify-image-signatures.yaml'
R = 'platform/policies/restrict-image-registries.yaml'
PATCHES = {
 V: [
  ("""# Exige que las imágenes de idp-sample-app estén firmadas (Cosign keyless) por el workflow ci.yaml
# del repo VictorMA97/idp-sample-app. Una imagen publicada a mano, o por otro repo, no pasa.
#""",
   """# Exige que las imágenes de la plataforma estén firmadas (Cosign keyless) por el workflow ci.yaml
# de su propio repo. Una imagen publicada a mano, desde otra cuenta o desde otro workflow, no pasa.
#
# Qué imágenes están cubiertas (y, por tanto, pueden ejecutarse en los namespaces de equipo):
#   - idp-sample-app              la app de ejemplo
#   - svc-<nombre>                los servicios creados con la plantilla de Backstage
# La convención de nombre "svc-" es el límite: solo los repos de la cuenta con ese prefijo pueden
# producir imágenes aceptadas. Si autorizas otro origen, añade su patrón AQUÍ y su prefijo en
# restrict-image-registries.yaml (invariante: todo prefijo autorizado debe estar cubierto aquí).
#"""),
  ("""  matchImageReferences:
    - glob: 'ghcr.io/victorma97/idp-sample-app*'
""",
   """  matchImageReferences:
    - glob: 'ghcr.io/victorma97/idp-sample-app*'
    - glob: 'ghcr.io/victorma97/svc-*'
"""),
  ("""              # Identidad exacta del workflow que firma (acepta main o master)
              subjectRegExp: '^https://github\\.com/VictorMA97/idp-sample-app/\\.github/workflows/ci\\.yaml@refs/heads/(main|master)$'""",
   """              # Identidad exacta del workflow que firma: propietario, repo (idp-sample-app o svc-*),
              # fichero ci.yaml y rama main o master. Un fork o una rama de trabajo no pasan.
              subjectRegExp: '^https://github\\.com/VictorMA97/(idp-sample-app|svc-[a-z0-9-]+)/\\.github/workflows/ci\\.yaml@refs/heads/(main|master)$'"""),
  ("message: 'La imagen no está firmada por el pipeline de idp-sample-app'",
   "message: 'La imagen no está firmada por el pipeline de su repositorio (idp-sample-app o svc-*)'"),
 ],
 R: [
  ("""# INVARIANTE: todo prefijo autorizado aquí debe estar cubierto por una política de verificación
# de firma. Por eso el prefijo es el repo concreto y no toda la cuenta de GHCR: si no, cualquier
# otro paquete sin firmar de la cuenta pasaría. Para autorizar otra app, añade su prefijo aquí
# Y su patrón en una política de verificación.""",
   """# INVARIANTE: todo prefijo autorizado aquí debe estar cubierto por una política de verificación
# de firma (verify-image-signatures.yaml). Por eso los prefijos son repos concretos (idp-sample-app)
# o una convención de nombre (svc-) y no toda la cuenta de GHCR: si no, cualquier otro paquete sin
# firmar de la cuenta pasaría. Para autorizar otro origen, añade su prefijo aquí Y su patrón allí."""),
  ("""expression: "['ghcr.io/victorma97/idp-sample-app']\"""",
   """expression: "['ghcr.io/victorma97/idp-sample-app', 'ghcr.io/victorma97/svc-']\""""),
  ("message: 'Solo se permiten imágenes de orígenes autorizados (ghcr.io/victorma97/idp-sample-app)'",
   "message: 'Solo se permiten imágenes de orígenes autorizados (ghcr.io/victorma97/idp-sample-app y ghcr.io/victorma97/svc-*)'"),
 ],
}
results, errors = {}, []
for path, pairs in PATCHES.items():
    try: text = open(path, encoding='utf-8').read()
    except FileNotFoundError:
        errors.append(f"No existe {path}. ¿Estás en la raíz de idp-platform?"); continue
    applied = skipped = 0
    for old, new in pairs:
        if new in text: skipped += 1; continue
        if text.count(old) != 1:
            errors.append(f"{path}: no encuentro el texto esperado (o aparece varias veces):\n    {old.splitlines()[0][:100]}")
            break
        text = text.replace(old, new); applied += 1
    else:
        results[path] = (text, applied, skipped)
if errors:
    print("[x] No se ha modificado NADA:", *errors, sep="\n  ", file=sys.stderr); sys.exit(1)
for path, (text, applied, skipped) in results.items():
    if applied: open(path, 'w', encoding='utf-8').write(text)
    print(f"{path}: {applied} cambio(s) aplicado(s), {skipped} ya estaba(n)")
PY
echo
echo "Modo actual de las políticas (debe seguir siendo el que tenías):"
grep -n 'validationActions' platform/policies/*.yaml
