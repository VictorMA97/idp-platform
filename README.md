# idp-platform

Base de una Internal Developer Platform (IDP) sobre Kubernetes que corre entera en un portátil o PC (WSL2 en Windows), sin coste de nube.

## Arquitectura (hub-and-spoke)

| Clúster | Papel | Puertos de host |
|---|---|---|
| `mgmt` | Hub: Argo CD y, más adelante, Backstage, Crossplane, Kyverno y observabilidad | 8080 / 8443 |
| `dev` | Spoke de desarrollo | 8081 / 8444 |
| `prod` | Spoke de producción | 8082 / 8445 |

- Los tres clústeres son [k3d](https://k3d.io) (k3s en Docker) sobre una red Docker compartida (`idp-net`), de modo que Argo CD en `mgmt` alcanza la API de los spokes por su nombre interno.
- Ingress: **Traefik**, que viene con k3s. No se usa ingress-nginx porque el proyecto Kubernetes anunció su retirada en marzo de 2026 (ver Fuentes).
- Dominios `*.localtest.me` resuelven a `127.0.0.1`, así que no hace falta tocar el fichero `hosts`.
- GitOps: patrón *app-of-apps*. `platform/apps/` es lo que sincroniza la app raíz; un `ApplicationSet` con generador de clústeres despliega la línea base (`platform/spokes/baseline`) en cada spoke, con overlay por entorno.

## Prerrequisitos

1. **Windows 11/10 con WSL2 + Ubuntu.** Trabaja siempre dentro de WSL y clona el repo en `~/` (nunca en `/mnt/c`).
2. **Memoria de WSL limitada:** copia `docs/wslconfig.example` a `C:\Users\<usuario>\.wslconfig` y ejecuta `wsl --shutdown` en PowerShell.
3. **Docker** accesible desde WSL (Docker Desktop con integración WSL2, o Docker Engine dentro de Ubuntu).
4. **k3d**: `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash`
5. **kubectl**: <https://kubernetes.io/docs/tasks/tools/>
6. **git** y **make** (`sudo apt install -y git make`).
7. Una cuenta de GitHub y un repositorio **público** vacío (Argo CD leerá de él).
8. Opcional: CLI `argocd`, `k9s`, `kubectx`.

## Puesta en marcha

```bash
git clone https://github.com/<usuario>/idp-platform.git ~/idp-platform   # o copia esta carpeta y haz git init
cd ~/idp-platform

make up                # preflight + 3 clústeres + Argo CD + registro de spokes
make argocd-password   # contraseña inicial de admin
# UI: http://argocd.localtest.me:8080  (usuario: admin)

# Entrega del control a GitOps
make set-repo REPO_URL=https://github.com/<usuario>/idp-platform.git
git add -A && git commit -m "Configura repo" && git push
make root
make status
```

`make help` lista todos los objetivos. `make down` destruye todo.

### Qué deberías ver

- 3 clústeres: `kubectl config get-contexts` muestra `k3d-mgmt`, `k3d-dev`, `k3d-prod`.
- En Argo CD, `dev` y `prod` aparecen en *Settings → Clusters* con estado *Successful*.
- Tras `make root`: aplicaciones `platform-root`, `cert-manager`, `baseline-dev` y `baseline-prod`.
- En cada spoke: `kubectl --context k3d-dev -n team-demo get quota,limitrange,netpol`.

## Decisiones (ADR resumido)

- **k3d frente a kind**: arranque rápido y menor consumo; kind queda como alternativa si se quiere Cilium.
- **Traefik frente a ingress-nginx**: ya incluido en k3s y sin dependencia de un proyecto retirado.
- **Registro declarativo de spokes** (Secret de clúster) frente a `argocd cluster add`: reproducible y versionable, sin pasos manuales.
- **Versiones fijadas** en los charts (`cert-manager`); Argo CD se instala desde `stable` por defecto y se recomienda fijar versión tras la primera prueba (`ARGOCD_VERSION=vX.Y.Z make argocd`).

## Fuentes

- [Ingress NGINX: Statement from the Kubernetes Steering and Security Response Committees](https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)
- [Ingress NGINX Retirement: What You Need to Know](https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)
