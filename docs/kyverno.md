# Kyverno: verificación de firmas y guardarraíles

Kyverno corre en **cada spoke** (dev y prod), porque la admisión se decide en el clúster donde
se crean los pods. Se despliega por GitOps con dos ApplicationSets que recorren los spokes
registrados.

## Piezas

| Fichero | Qué hace |
|---|---|
| `platform/apps/kyverno-appset.yaml` | Instala el chart `kyverno` **3.9.2** (Kyverno v1.19.2) en cada spoke |
| `platform/apps/kyverno-policies-appset.yaml` | Aplica `platform/policies/` en cada spoke |
| `platform/policies/verify-image-signatures.yaml` | `ImageValidatingPolicy`: la imagen (`idp-sample-app` o `svc-*`) debe estar firmada por el `ci.yaml` de su propio repo (Cosign keyless) |
| `platform/policies/restrict-image-registries.yaml` | `ValidatingPolicy`: solo se admiten imágenes de orígenes autorizados |
| `platform/policies/disallow-latest-tag.yaml` | `ValidatingPolicy`: sin `:latest` ni imágenes sin tag (el digest basta) |

Las políticas solo afectan a namespaces con la etiqueta `idp.dev/team` (como `team-demo`).
`kube-system`, `kyverno`, `argocd` y el resto del sistema no se tocan.

## Cómo se verifica la firma

El pipeline firma con la identidad OIDC del workflow (sin claves). Kyverno comprueba que el
certificado de la firma tiene como emisor `https://token.actions.githubusercontent.com` y como
sujeto exactamente `.../(idp-sample-app|svc-<nombre>)/.github/workflows/ci.yaml@refs/heads/(main|master)`.
Una imagen publicada a mano, desde otra rama, desde otro workflow o desde otro repo no pasa.

**Invariante:** todo prefijo autorizado en `restrict-image-registries` debe estar cubierto por una
política de verificación. Si autorizas otra app, añade las dos cosas.

## Puesta en marcha

1. Copia estos ficheros a tu repo, vuelve a ejecutar `make set-repo REPO_URL=...` (la política de
   despliegue lleva el marcador de URL), commit y push. Argo CD instala Kyverno y luego las políticas.
2. Comprueba que está todo sano: `make status` y
   `kubectl --context k3d-dev -n kyverno get pods`.
3. **Modo Audit (el de partida):** las políticas registran pero no rechazan. Ejecuta
   `make test-policies` y revisa que la imagen firmada figura como `pass` en los informes:
   `kubectl --context k3d-dev -n team-demo get policyreport -o wide`.
4. **Solo cuando la imagen firmada pase en Audit:** `make policies-mode MODE=deny`, commit y push.
   Repite `make test-policies`: ahora debe rechazar nginx, el repo ajeno y `:latest`, y admitir la
   imagen firmada. Para volver atrás: `make policies-mode MODE=audit`.

## Limitaciones conocidas

- **Attestations (SBOM) no se verifican en el clúster.** Kyverno tiene un fallo abierto con las
  attestations de Cosign v3 ([kyverno/kyverno#16678](https://github.com/kyverno/kyverno/issues/16678)).
  La firma sí verifica. El SBOM se comprueba en `promote.yaml` con la CLI de cosign.
  Cuando se corrija, se añade `attestations` y `verifyAttestationSignatures` a la política.
- **Formato de firma:** Cosign v3 firma con el formato nuevo (bundle como referrer OCI). Es la razón
  de empezar en Audit: si la verificación no reconociera esas firmas, lo verías en los informes
  sin haber bloqueado nada.
- **Red:** Kyverno necesita salida a `ghcr.io` y a la infraestructura pública de Sigstore (raíz
  TUF y Rekor). Con k3d local la tienen por defecto.
- **`failurePolicy: Fail`:** si Kyverno cae, no se pueden crear pods en los namespaces de equipo.
  Es la postura segura; en un laboratorio puede ser molesta. Se limita al alcance de la etiqueta.
- **Una réplica por controlador** (laboratorio). En producción real, tres para alta disponibilidad.
- **Argo CD y los informes:** Kyverno genera muchos recursos de informe. Con pocos pods no importa;
  en un clúster grande conviene excluirlos con `resource.exclusions` en Argo CD.
- **Identidad fija:** el sujeto de la firma menciona `VictorMA97/idp-sample-app`. Si renombras el
  repo o la cuenta, edita `subjectRegExp` y el glob de la política.
- Las expresiones CEL se probaron con una implementación de Python, no con la de Kyverno.

## Referencias

- [ImageValidatingPolicy](https://kyverno.io/docs/policy-types/image-validating-policy/)
- [ValidatingPolicy](https://kyverno.io/docs/policy-types/validating-policy/)
