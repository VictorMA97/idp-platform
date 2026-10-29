# Golden path: crear un servicio desde Backstage

En Backstage: **Create → "Servicio Python (golden path)"**. Rellenas nombre del repo (`svc-<nombre>`),
descripción y equipo, y la plantilla hace todo lo demás.

## Qué ocurre

1. Backstage genera el código (FastAPI, tests, Dockerfile, chart de Helm, workflows) y **crea el repo
   en GitHub con tu token** (el que autorizas al iniciar sesión, no uno guardado en el clúster).
2. Abre un **pull request en `idp-platform`** que añade `platform/services/svc-<nombre>.yaml`.
3. El componente aparece solo en el catálogo de Backstage (descubrimiento automático de repos `svc-*`, cada 5 minutos).
4. El CI del repo nuevo construye, escanea (Trivy), genera SBOM, **firma con Cosign** y despliega en dev.
5. Cuando aceptas el PR, el ApplicationSet `services` crea `svc-<nombre>-dev` y `svc-<nombre>-prod`.

## Pasos manuales (a propósito)

- **Hacer público el paquete en GHCR** tras el primer CI (perfil → Packages → paquete → Change visibility).
  El clúster no tiene credenciales de pull. Es un paso de GitHub que no se puede automatizar con el token
  de usuario sin permisos extra.
- **Aceptar el PR de idp-platform.** Es el control humano: nada llega al clúster sin revisión.
- Opcional: revisores obligatorios en el environment `production` del repo del servicio.

## Modelo de seguridad

- Kyverno solo admite imágenes de `svc-*` (y de `idp-sample-app` si activaste la app de ejemplo) **firmadas por el `ci.yaml` de su propio repo**
  en `main`/`master`. Un repo sin el prefijo, un fork o una imagen manual no arrancan (en modo Deny).
- Invariante: todo prefijo permitido en `restrict-image-registries` debe estar cubierto en
  `verify-image-signatures`.
- Los permisos pedidos al usuario son `public_repo` y `workflow` (este último es necesario para subir
  `.github/workflows`). Dan acceso amplio a tus repos públicos: es el coste de usar el token del usuario.
- `protectDefaultBranch: false`: el CI escribe el digest en `main`; en cuentas personales la protección
  no admite excepciones para el bot.

## Recursos por servicio

Cada pod pide 50m CPU / 64Mi y limita 250m / 128Mi; prod usa 2 réplicas. Las cuotas de `team-demo`
se comparten entre servicios: dev 30 pods, 1 CPU y 1Gi de requests; prod 40 pods, 3 CPU y 3Gi.
Con la app de ejemplo ya desplegada caben muchos servicios, pero no infinitos.

## Descubrimiento del catálogo

`idp.serviceDiscovery` (en `app-config.yaml` de idp-backstage; código en
`packages/backend/src/modules/serviceDiscovery.ts`) busca cada 5 minutos los repos públicos `svc-*` de la cuenta
con `catalog-info.yaml` en la raíz y los registra. Si borras un repo, su entrada desaparece. El catálogo se
reconstruye solo aunque se pierda la base de datos. Si GitHub falla, no se modifica nada. Usa el `GITHUB_TOKEN` de
solo lectura (repos públicos) del Secret `backstage-secrets`. No se usa el módulo oficial porque su consulta
incluye los repos privados de la cuenta y falla con un token que no los cubre.

## Eliminar un servicio

Borra `platform/services/svc-<nombre>.yaml` de `idp-platform` (el ApplicationSet poda sus apps) y
elimina el repo y la entrada del catálogo a mano.

## Comprobado de punta a punta

Con el servicio `svc-test`: la plantilla crea el repo con el token del usuario, el CI construye, escanea y
firma, Kyverno (modo Deny) admite la imagen, y Argo CD despliega `svc-test-dev` y `svc-test-prod`.

## Detalles a tener en cuenta

- **Consentimiento de GitHub:** el formulario pide `repo`, `workflow`, `public_repo` y otros. Si crear el
  repo da 404, el token solo tiene `read:user`: revoca la app, cierra sesión, entra de nuevo y acepta.
- **Nombre del repo:** debe ser `svc-` + minúsculas, números y guiones (sin guion final). Si no, el
  formulario no avanza ("Form validation failed" en la consola).
- **prod:** `values-prod.yaml` empieza sin imagen; la rellena el workflow manual `promote-to-prod` del repo del
  servicio. En la prueba, `svc-test-prod` tardó en sincronizar y acabó funcionando; no se identificó la causa.
- **Aviso de la consola** `WebSocket /api/signals failed`: inofensivo.
