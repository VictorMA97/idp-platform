## Kyverno (Fase 5a)

Kyverno v1.19.2 (chart 3.9.2) corre en cada spoke, desplegado por los ApplicationSets
`kyverno` y `kyverno-policies`. Políticas en `platform/policies/` (ImageValidatingPolicy +
ValidatingPolicy, `policies.kyverno.io/v1`), solo en namespaces con la etiqueta `idp.dev/team`.
Empiezan en modo Audit; `make policies-mode MODE=deny` las pasa a bloqueo y `make test-policies`
las prueba. Detalles, limitaciones y pasos en `docs/kyverno.md`.
- Invariante: todo prefijo de `restrict-image-registries` debe estar cubierto por una política de firma.
- No se verifican attestations (SBOM) en el clúster: fallo abierto kyverno/kyverno#16678 con Cosign v3.
- Estado: escrito y validado contra el esquema del CRD, **sin ejecutar aún en el entorno real**.