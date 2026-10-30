# idp-platform

Internal Developer Platform (IDP) sobre Kubernetes que corre entera en un PC con WSL2, sin coste de nube.
Un desarrollador entra en un portal (Backstage), elige una plantilla y obtiene un servicio con repositorio,
CI/CD firmado, despliegue por GitOps en dev y prod y políticas de seguridad verificadas en el clúster.

## Qué incluye

| Pieza | Qué hace | Dónde se configura |
|---|---|---|
| Clústeres `mgmt`, `dev`, `prod` | k3d (k3s en Docker) sobre una red compartida | `clusters/`, `scripts/` |
| Argo CD | GitOps: app-of-apps y ApplicationSets | `platform/bootstrap/`, `platform/apps/` |
| Línea base de los spokes | Namespace `team-demo` con cuotas y NetworkPolicies | `platform/spokes/baseline/` |
| Kyverno | Solo admite imágenes de la plataforma, firmadas por su propio CI (Cosign keyless) | `platform/policies/` (dev y prod), `platform/policies-mgmt/` (Backstage) |
| App de ejemplo (opcional) | Golden path de una app Python; no es necesaria para la plataforma | repo `idp-sample-app` |
| Backstage | Portal: catálogo, plantillas y descubrimiento de servicios | repo `idp-backstage` |
| Golden path | Crea un servicio `svc-<nombre>` desde Backstage | `docs/golden-path.md` |

## Los tres repositorios

| Repo | Contenido | Quién lo despliega |
|---|---|---|
| `idp-platform` (este) | Infraestructura, Argo CD, políticas, scripts | `make` en tu PC |
| `idp-sample-app` (opcional) | App de ejemplo con su pipeline | Argo CD, si ejecutas `make sample-app` |
| `idp-backstage` | Portal Backstage, su pipeline y la plantilla de servicios | Argo CD, desde `idp-platform` |

Los tres deben ser **públicos** (Argo CD lee de ellos sin credenciales) y viven en tu cuenta de GitHub.
Cada servicio creado con la plantilla es un cuarto repo `svc-<nombre>`.

## Arquitectura

```
                  tu PC (WSL2 + Docker, red idp-net)
 ┌───────────────────────────┐   ┌─────────────────┐   ┌─────────────────┐
 │ mgmt   :8080              │   │ dev   :8081     │   │ prod   :8082    │
 │ Argo CD  Backstage        │──▶│ team-demo       │   │ team-demo       │
 │ PostgreSQL  Kyverno       │──▶│ apps + Kyverno  │   │ apps + Kyverno  │
 └───────────────────────────┘   └─────────────────┘   └─────────────────┘
        ▲ lee de Git                    ▲ despliega por digest
   idp-platform  idp-backstage  idp-sample-app  svc-*
```

- **Ingress:** Traefik (viene con k3s). No se usa ingress-nginx porque el proyecto Kubernetes anunció su
  retirada (ver Fuentes). Los dominios `*.localtest.me` resuelven a `127.0.0.1`: no hay que tocar `hosts`.
- **GitOps:** `platform/apps/` es lo único que sincroniza la app raíz. Los ApplicationSets recorren los
  clústeres con la etiqueta `idp.dev/role=spoke` (dev y prod); mgmt, que no es un spoke, tiene sus propias apps.
- **Despliegue por digest:** el CI de cada app escribe `repo:tag@sha256:...` en su chart; Argo CD lo aplica.
- **Seguridad:** acciones de GitHub fijadas por SHA, Trivy como puerta de calidad, imágenes firmadas
  con Cosign y verificadas por Kyverno al admitir el pod.

## Requisitos

1. **Windows 11/10 con WSL2 + Ubuntu.** Trabaja siempre dentro de WSL y clona los repos en `~/` (nunca en `/mnt/c`).
2. **Memoria de WSL limitada:** copia `docs/wslconfig.example` a `C:\Users\<usuario>\.wslconfig` y ejecuta
   `wsl --shutdown` en PowerShell. Con los tres clústeres, Kyverno, Backstage y PostgreSQL, conviene un PC de 32 GB.
3. **Docker** accesible desde WSL (Docker Desktop con integración WSL2, o Docker Engine dentro de Ubuntu).
4. **k3d**: `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash`
5. **kubectl**: <https://kubernetes.io/docs/tasks/tools/>
6. `git`, `make` (`sudo apt install -y git make`) y `curl`.
7. Una cuenta de GitHub. Opcional: `gh`, `argocd`, `k9s`.

## Puesta en marcha, de cero a plataforma completa

Hazlo en este orden. Cada etapa termina con una **comprobación**: no pases a la siguiente si falla.

### Etapa 1. Infraestructura base (unos minutos)

```bash
git clone https://github.com/$OWNER/idp-platform.git ~/idp-platform
cd ~/idp-platform
make up                # preflight + 3 clústeres + Argo CD + registro de spokes
make argocd-password   # contraseña inicial del usuario admin
```

Comprobación: `kubectl config get-contexts` muestra `k3d-mgmt`, `k3d-dev` y `k3d-prod`, y
<http://argocd.localtest.me:8080> abre (usuario `admin`). En *Settings → Clusters* aparecen dev y prod.

### Etapa 2. Entregar el control a GitOps

```bash
make set-owner OWNER=<usuario>      # tu cuenta de GitHub en las políticas de Kyverno (ghcr.io/<usuario>/...)
make set-repo REPO_URL=https://github.com/$OWNER/idp-platform.git
git add -A && git commit -m "Configura repo y cuenta" && git push
make root
make status
```

`make root` activa la app raíz. A partir de aquí Argo CD instala, desde Git, cert-manager, la línea base
de los spokes y Kyverno (con sus políticas) en dev, prod y mgmt.

Comprobación (tarda unos minutos en estar todo en verde):

```bash
make status                                           # todas Synced/Healthy
kubectl --context k3d-dev  -n kyverno get pods        # Kyverno en marcha
kubectl --context k3d-mgmt -n kyverno get pods
kubectl --context k3d-dev -n team-demo get quota,limitrange,netpol
```

Las políticas de Kyverno empiezan en modo **Audit**: registran, pero no rechazan nada.

### Etapa 3. App de ejemplo (opcional)

La plataforma, Backstage y los servicios `svc-*` funcionan sin ella. Por defecto Kyverno solo admite `svc-*`; `make sample-app` añade la app al ApplicationSet **y** la autoriza en las políticas (`make sample-app-off` lo deshace). Pasos completos en el README de `idp-sample-app`. Resumen:

1. Crea el repo público `idp-sample-app` y sube su contenido; espera a que el workflow `ci` termine en verde.
2. Haz público el paquete en GHCR (perfil → *Packages* → `idp-sample-app` → *Package settings* → *Change visibility*).
3. En este repo: `make sample-app APP_REPO_URL=https://github.com/$OWNER/idp-sample-app.git`, commit y push.

Comprobación: <http://sample-app.dev.localtest.me:8081> responde. Prod se activa después con el workflow
manual `promote-to-prod` del repo de la app: <http://sample-app.prod.localtest.me:8082>.

### Etapa 4. Kyverno en modo bloqueo

```bash
make test-policies                          # dev; también POLICY_ENV=prod
make policies-mode MODE=deny                # dev y prod
git add -A && git commit -m "Políticas en Deny" && git push
make test-policies                          # ahora debe rechazar lo no autorizado
```

La comprobación incluye que la imagen firmada de la app de ejemplo **pasa**. Haz siempre Audit → comprobar
→ Deny. Detalles y límites en `docs/kyverno.md`. Las políticas de Backstage (mgmt) se cambian aparte,
cuando Backstage ya funcione (Etapa 5): `make policies-mode MODE=deny TARGET=mgmt` y
`make test-policies POLICY_ENV=mgmt`.

### Etapa 5. Backstage

Hacen falta: una OAuth App de GitHub, un token de solo lectura, el repo público `idp-backstage` y el paquete
de su imagen en público. Guía paso a paso en `docs/backstage.md`.

**Antes de nada, configura tu cuenta en `idp-backstage`** (si no, el login falla con "unable to resolve user identity").
El script cambia el usuario en el descubrimiento, el catálogo y la plantilla, y escribe tu `node_id` en `catalog/org.yaml`:

```bash
cd idp-backstage
./scripts/set-owner.sh <usuario>
# si no puede consultar la API de GitHub (límite o sin red), te dice cómo repetirlo:
#   NODE_ID=$(gh api users/<usuario> --jq .node_id) ./scripts/set-owner.sh <usuario>
git add -A && git commit -m "chore: cuenta y node_id" && git push     # el CI reconstruye la imagen
```

Usa la misma cuenta que en `make set-owner` de la Etapa 2. El `metadata.name` del usuario en `org.yaml` da igual para
el login: solo cuenta que `user-id` coincida con tu `node_id`. `./scripts/rollback.sh` de `idp-backstage` devuelve
el `node_id` al placeholder (la cuenta se queda): repite este paso al empezar de cero.

Resumen del final:

```bash
make backstage-secrets     # pide Client ID, Client Secret y token; no van a Git
make backstage BACKSTAGE_REPO_URL=https://github.com/$OWNER/idp-backstage.git
git add -A && git commit -m "Activa Backstage" && git push
```

Comprobación: `kubectl --context k3d-mgmt -n backstage get pods` (Backstage y PostgreSQL en `1/1`) e
iniciar sesión con GitHub en <http://backstage.localtest.me:8080>. La app `backstage` da error de render
hasta que el CI de `idp-backstage` escriba su primer digest: es lo esperado.

**Guarda en un lugar seguro** los tres valores de `make backstage-secrets`: si recreas los clústeres,
tendrás que volver a introducirlos.

### Etapa 6. Tu primer servicio

En Backstage: **Create → "Servicio Python (golden path)"**. El repo se llama `svc-<nombre>` (minúsculas,
números y guiones). La primera vez, GitHub pide autorizar permisos para crear el repo.
Después: espera al CI del repo nuevo, haz público su paquete en GHCR y acepta el pull request que Backstage
abre en este repo. El servicio aparece solo en el catálogo en unos 5 minutos. Detalles en `docs/golden-path.md`.

## URLs

| Qué | URL |
|---|---|
| Argo CD | <http://argocd.localtest.me:8080> |
| Backstage | <http://backstage.localtest.me:8080> |
| App de ejemplo (dev / prod) | <http://sample-app.dev.localtest.me:8081> / <http://sample-app.prod.localtest.me:8082> |
| Servicio `svc-<nombre>` (dev / prod) | `http://<nombre>.dev.localtest.me:8081` / `http://<nombre>.prod.localtest.me:8082` |

`make urls` las imprime. Con prod hace falta haber ejecutado antes `promote-to-prod` en el repo del servicio.

## Comandos (`make help`)

| Comando | Qué hace |
|---|---|
| `make up` | Preflight, clústeres, Argo CD y registro de spokes |
| `make set-repo REPO_URL=...` / `make root` | Apunta los manifiestos a tu repo / activa GitOps |
| `make sample-app APP_REPO_URL=...` / `make sample-app-off` | (Opcional) activa / desactiva la app de ejemplo, incluida su autorización en Kyverno |
| `make backstage-secrets` / `make backstage BACKSTAGE_REPO_URL=...` | Credenciales / activa Backstage |
| `make policies-mode MODE=audit\|deny [TARGET=spokes\|mgmt\|all]` | Modo de las políticas (por defecto, dev y prod) |
| `make test-policies [POLICY_ENV=dev\|prod\|mgmt]` | Prueba las políticas con peticiones dry-run |
| `make status` / `make argocd-password` / `make urls` | Estado, contraseña de Argo CD, URLs |
| `make rollback` (alias `make rollout`) | Deshace los cambios de la puesta en marcha en el repo y **destruye** los clústeres, para empezar de cero |
| `make down` | **Destruye** clústeres y red |

## Operación diaria

- **Crear un servicio:** Backstage → Create (Etapa 6).
- **Promover a prod:** repo del servicio → *Actions → promote-to-prod → Run workflow*. Verifica firma y SBOM
  y escribe el digest en `values-prod.yaml`. Opcional: revisores obligatorios en el environment `production`.
- **Quitar un servicio:** borra `platform/services/svc-<nombre>.yaml` de este repo (Argo CD poda sus apps) y
  elimina su repo en GitHub (desaparece del catálogo solo).
- **Cambiar usuarios o plantillas de Backstage:** van dentro de su imagen; exige un push al repo `idp-backstage`.

## Apagar y borrar

- **Empezar de cero:** `make rollback` (alias `make rollout`). Muestra un plan, pide confirmación y:
  restaura la URL del repo a `__REPO_URL__` (lo que hizo `make set-repo`), borra los ficheros generados por
  `make sample-app` y `make backstage`, devuelve las políticas a Audit, quita `idp-sample-app` de las listas permitidas, restaura `<usuario>` en las políticas y tests (lo que hizo `make set-owner`), borra `platform/services/svc-*.yaml` y
  destruye los clústeres. No hace commit ni push: revisa con `git status`, súbelo y repite las Etapas 1 a 6.
  No toca los otros repos, los paquetes de GHCR ni GitHub. Opciones: `DRY_RUN=1` (solo mostrar el plan),
  `FORCE=1` (sin confirmación), `KEEP_CLUSTERS=1`, `KEEP_SERVICES=1`.
- `make down` elimina los clústeres y la red. **Se pierde todo**, incluidos el Secret `backstage-secrets` y
  los datos de PostgreSQL. Para volver: Etapas 1 a 6. Los repos en GitHub se conservan.
- Para pausar sin borrar: `k3d cluster stop --all` y `k3d cluster start --all` (comandos estándar de k3d,
  no ejecutados en este proyecto). Con Kyverno en modo bloqueo, si Backstage arranca antes que Kyverno
  puede quedarse sin crear pods: ver `docs/kyverno.md` (riesgo de `failurePolicy: Fail`).

## Problemas conocidos

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Docker no responde` | Docker parado o sin integración WSL | Arranca Docker Desktop y activa la integración con tu distro |
| Puerto 8080 ocupado | Otro servicio de Windows o WSL | Cambia el mapeo en `clusters/mgmt.yaml` y las URLs |
| Spokes en *Unknown* o error TLS | El certificado de la API no valida con el nombre interno | `SPOKE_INSECURE=1 make spokes` (solo laboratorio) |
| `ComparisonError` en Argo CD | El repo no está en Git o `repoURL` incorrecta | `make set-repo`, push y espera |
| Todo va lento | Repo en `/mnt/c` o poca RAM para WSL | Muévelo a `~/` y revisa `.wslconfig` |
| `kyverno-*` siempre OutOfSync | Metadatos vacíos en los CRD de Kyverno | Ya se ignoran en los manifiestos (`ignoreDifferences`) |
| `ImagePullBackOff` en una app o servicio | Paquete de GHCR privado, o CI sin terminar | Haz público el paquete; espera al CI |
| `ErrImagePull ... not found` justo tras un CI | GHCR tarda en servir el digest recién publicado | Espera unos minutos: kubelet reintenta |
| Backstage 404 en la URL | No existe la app `backstage` en Argo CD | `make backstage-secrets`, `make backstage`, push |
| `secret "backstage-secrets" not found` | Clúster o namespace recreado | `make backstage-secrets` y reinicia el pod |
| `ENOTFOUND backstage-postgres` | Backstage arrancó antes que la base de datos | Se resuelve solo; el pod espera a PostgreSQL |
| Crear el repo desde Backstage da 404 | El token de usuario no tiene permisos de escritura | Revoca la app en github.com/settings/applications, cierra sesión en Backstage y vuelve a entrar |
| El formulario no avanza (*Form validation failed*) | El repo no empieza por `svc-` o tiene mayúsculas | Usa `svc-` + minúsculas, números y guiones |
| Un `svc-*` no aparece en el catálogo | El descubrimiento corre cada 5 minutos | Espera; si no, mira el log: `kubectl --context k3d-mgmt -n backstage logs deploy/backstage -c backstage \| grep -i descubi` |
| Aviso de WebSocket `/api/signals` en la consola | Inofensivo: el primer intento llega antes de que el backend lo acepte | Ignorar |

## Documentación

| Documento | Contenido |
|---|---|
| `docs/kyverno.md` | Políticas, modos Audit/Deny, Kyverno en mgmt, límites |
| `docs/backstage.md` | OAuth App, secretos, despliegue, problemas de Backstage |
| `docs/golden-path.md` | Cómo funciona la plantilla de servicios y su modelo de seguridad |

## Hoja de ruta

- [x] Clústeres reproducibles, Argo CD, app-of-apps, línea base multi-clúster
- [x] Golden path de aplicación (GitHub Actions, GHCR, Trivy, Cosign, despliegue por digest)
- [x] Backstage con plantillas de software y descubrimiento de servicios
- [x] Kyverno: verificación de firmas en dev, prod y mgmt
- [ ] Crossplane + CloudNativePG (base de datos self-service)
- [ ] External Secrets / OpenBao
- [ ] Observabilidad (Prometheus, Grafana, Loki, Tempo)
- [ ] ADRs completos y demo en vídeo

## Decisiones (ADR resumido)

- **k3d frente a kind**: arranque rápido y menor consumo; kind queda como alternativa si se quiere Cilium.
- **Traefik frente a ingress-nginx**: ya incluido en k3s y sin dependencia de un proyecto retirado.
- **Registro declarativo de spokes** (Secret de clúster) frente a `argocd cluster add`: reproducible y versionable.
- **Una política por convención de nombre** (`svc-*`): cualquier servicio creado con la plantilla pasa la
  verificación de firma sin tocar Kyverno, y nada fuera de esa convención entra.
- **Descubrimiento propio de servicios** en Backstage: el módulo oficial fallaba con repos privados de la cuenta.
- **Versiones fijadas** en charts y acciones; súbelas de forma deliberada, no automática.

## Fuentes

- [Ingress NGINX: Statement from the Kubernetes Steering and Security Response Committees](https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)
- [Ingress NGINX Retirement: What You Need to Know](https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)
