# Golden path: crear un servicio desde Backstage

En Backstage: **Create → "Servicio Python (golden path)"**. Rellenas nombre del repo (`svc-<nombre>`),
descripción y equipo, y la plantilla hace todo lo demás.

## Qué ocurre

1. Backstage genera el código (FastAPI, tests, Dockerfile, chart de Helm, workflows) y **crea el repo
   en GitHub con tu token** (el que autorizas al iniciar sesión, no uno guardado en el clúster).
2. Abre un **pull request en `idp-platform`** que añade `platform/services/svc-<nombre>.yaml`.
3. Registra el componente en el catálogo de Backstage.
4. El CI del repo nuevo construye, escanea (Trivy), genera SBOM, **firma con Cosign** y despliega en dev.
5. Cuando aceptas el PR, el ApplicationSet `services` crea `svc-<nombre>-dev` y `svc-<nombre>-prod`.

## Pasos manuales (a propósito)

- **Hacer público el paquete en GHCR** tras el primer CI (perfil → Packages → paquete → Change visibility).
  El clúster no tiene credenciales de pull. Es un paso de GitHub que no se puede automatizar con el token
  de usuario sin permisos extra.
- **Aceptar el PR de idp-platform.** Es el control humano: nada llega al clúster sin revisión.
- Opcional: revisores obligatorios en el environment `production` del repo del servicio.

## Modelo de seguridad

- Kyverno solo admite imágenes de `idp-sample-app` y `svc-*` **firmadas por el `ci.yaml` de su propio repo**
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

## Eliminar un servicio

Borra `platform/services/svc-<nombre>.yaml` de `idp-platform` (el ApplicationSet poda sus apps) y
elimina el repo y la entrada del catálogo a mano.

## Sin probar en el entorno real

- La ejecución real del scaffolder con tu token de usuario (se probó el renderizado de la plantilla con
  los filtros y acciones reales, no las llamadas a GitHub).
- El comportamiento de Argo CD con `platform/services/` sin ningún fichero `.yaml` (solo hay README).
  Si el ApplicationSet `services` da error, crea un servicio de prueba o avísame.
- Kyverno con una imagen real de `svc-*`.
- Los Helm templates se validaron con una aproximación en Go, además de `helm lint`.
