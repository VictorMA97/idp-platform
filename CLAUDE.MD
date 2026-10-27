## Kyverno (Fase 5a)

Kyverno v1.19.2 (chart 3.9.2) corre en cada spoke, desplegado por los ApplicationSets
`kyverno` y `kyverno-policies`. Políticas en `platform/policies/` (ImageValidatingPolicy +
ValidatingPolicy, `policies.kyverno.io/v1`), solo en namespaces con la etiqueta `idp.dev/team`.
Empiezan en modo Audit; `make policies-mode MODE=deny` las pasa a bloqueo y `make test-policies`
las prueba. Detalles, limitaciones y pasos en `docs/kyverno.md`.
- Invariante: todo prefijo de `restrict-image-registries` debe estar cubierto por una política de firma.
- No se verifican attestations (SBOM) en el clúster: fallo abierto kyverno/kyverno#16678 con Cosign v3.
- Estado: escrito y validado contra el esquema del CRD, **sin ejecutar aún en el entorno real**.

## Backstage (Fase 3)

Backstage corre en el clúster mgmt (no en spokes), desplegado por la Application `backstage`
(plantilla en `platform/templates/backstage-app.yaml.tpl`, se activa con `make backstage`).
Código, imagen y chart en el repo `idp-backstage`; el CI escribe el digest en `chart/values-mgmt.yaml`.
Login con GitHub; credenciales en el Secret `backstage-secrets` (`make backstage-secrets`, nunca en Git).
Pasos y limitaciones en `docs/backstage.md`.
- Kyverno no está en mgmt: la firma de la imagen de Backstage no se verifica al admitir el pod.
- Estado: validado localmente; **sin ejecutar aún en el clúster real**.