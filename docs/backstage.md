# Backstage (Fase 3): portal del desarrollador

Backstage se despliega **una sola vez, en el clúster de gestión (mgmt)**, junto a Argo CD. Es una
herramienta de la plataforma, no de un equipo, así que no va en dev ni en prod.
Su código vive en un repo aparte, `idp-backstage`, con su propio pipeline.

URL: http://backstage.localtest.me:8080

## Piezas

| Dónde | Qué |
|---|---|
| Repo `idp-backstage` | App de Backstage 1.56 (frontend nuevo), `Dockerfile`, chart de Helm (Backstage + PostgreSQL), CI |
| `platform/templates/backstage-app.yaml.tpl` | Plantilla de la Application de Argo CD (`make backstage` la copia a `platform/apps/`) |
| `scripts/backstage-secrets.sh` | Crea el Secret con las credenciales en mgmt (no van a Git) |

## Flujo

1. Haces push al repo `idp-backstage`. El CI construye la imagen, la escanea con Trivy, la firma con
   Cosign (keyless) y escribe tag y digest en `chart/values-mgmt.yaml`.
2. Argo CD (app `backstage` en mgmt) detecta el commit y despliega esa imagen **por digest**.
3. El usuario entra con GitHub. Solo pasa quien tenga un `User` en `catalog/org.yaml` cuyo
   `github.com/user-id` coincida con su ID inmutable de GitHub; el nombre de usuario no se usa.

## Puesta en marcha (en este orden)

### 1. OAuth App de GitHub

GitHub → Settings → Developer settings → OAuth Apps → New OAuth App:

- Homepage URL: `http://backstage.localtest.me:8080`
- Authorization callback URL: `http://backstage.localtest.me:8080/api/auth/github/handler/frame`

Genera un *client secret* y guarda el Client ID y el secret.

### 2. Token de GitHub

Settings → Developer settings → Fine-grained tokens. Sin permisos adicionales, acceso solo a
repositorios públicos. Backstage lo exige en la configuración; por ahora no escribe nada en GitHub.

### 3. Tu identidad en el catálogo

```bash
gh api users/<tu-usuario> --jq .node_id
```

Pon ese valor en `catalog/org.yaml` del repo `idp-backstage` (sustituye `__GITHUB_NODE_ID__`).
Si no coincide, el login falla con *unable to resolve user identity*.

### 4. Repo `idp-backstage`

Crea un repo **público** en GitHub, `idp-backstage`, y sube el contenido de `idp-backstage.zip`:

```bash
unzip idp-backstage.zip -d idp-backstage && cd idp-backstage
git init -b master && git add -A && git commit -m "Backstage"
git remote add origin https://github.com/<usuario>/idp-backstage.git && git push -u origin master
```

- En Settings → Actions, permite también `actions/setup-node` si tienes una lista de acciones
  permitidas (las demás ya las usa `idp-sample-app`).
- Cuando el CI publique la primera imagen, haz el paquete público: GitHub → tu perfil → Packages →
  `idp-backstage` → Package settings → Change visibility → Public. Sin eso el clúster no puede
  descargarla.
- El primer CI puede fallar en el escaneo de Trivy (Backstage tiene muchas dependencias).
  Mira el informe; no relajes el umbral sin entender cada hallazgo.

### 5. Credenciales en el clúster

```bash
make backstage-secrets     # pide Client ID, Client Secret y token; genera las claves internas
```

### 6. Activar la app en Argo CD

```bash
make backstage BACKSTAGE_REPO_URL=https://github.com/<usuario>/idp-backstage.git
git add -A && git commit -m "Activa Backstage" && git push
make status
```

La app `backstage` dará error de render hasta que el CI haya escrito el primer digest
(`image.tag o image.digest son obligatorios`). Es lo esperado y se resuelve solo.

### 7. Comprobar

```bash
kubectl --context k3d-mgmt -n backstage get pods
```

Deben estar `backstage-xxxx` y `backstage-postgres-0` en `Running`. Abre
http://backstage.localtest.me:8080 e inicia sesión con GitHub. Debes ver el sistema `idp` y los
componentes `idp-platform`, `idp-backstage` e `idp-sample-app`.

## Qué se ha comprobado y qué no

Comprobado: la app compila (`tsc` y empaquetado del backend); arranca con la configuración de
producción contra un PostgreSQL real, también con el sistema de ficheros en solo lectura; el login
redirige a GitHub con la URL de retorno correcta; el catálogo carga las 9 entidades sin errores; los
scripts pasan `shellcheck` y el de secretos se probó con un `kubectl` simulado.

**No comprobado:** la construcción de la imagen (no hay Docker en mi entorno), el login completo con
tu cuenta de GitHub, el chart con `helm` real (lo renderizé con un arnés propio; el CI hace
`helm lint` y `helm template`) y el despliegue en el clúster.

## Limitaciones

- **Kyverno no está en mgmt.** La imagen de Backstage se firma en CI y se despliega por digest, pero
  el clúster no verifica la firma al admitir el pod, como sí hace en dev y prod. Extender Kyverno a
  mgmt es un paso posterior.
- **Los datos de PostgreSQL** están en un volumen local: se pierden con `make down`.
- **Cambiar usuarios** (`catalog/org.yaml`) obliga a reconstruir la imagen: el fichero va dentro.
- **Imágenes base sin fijar por digest:** `node:24-trixie-slim` y `postgres:17-alpine`. Trivy las
  escanea en cada ejecución, pero conviene fijarlas.
- **Sin plantillas de software (scaffolder) todavía.** Un servicio nuevo no pasaría la política de
  firma actual, que acepta solo `idp-sample-app`. Hay que generalizarla antes (fase 3b).
- Una réplica de Backstage y de PostgreSQL (laboratorio).
