# Observabilidad (solo mgmt)

Se despliega con Argo CD como el resto: dos Applications en `platform/apps/`.

| Application | Qué instala |
|---|---|
| `monitoring-mgmt` | kube-prometheus-stack 92.16.2: Prometheus, Alertmanager, Grafana, kube-state-metrics y los dashboards de Kubernetes |
| `monitoring-config-mgmt` | Lo propio de la plataforma (`platform/monitoring/`): ServiceMonitors, alertas y dashboards |

Acceso: <http://grafana.localtest.me:8080> (`admin` / `admin`, solo laboratorio).
Prometheus y Alertmanager no tienen ingress: `kubectl --context k3d-mgmt -n monitoring port-forward svc/monitoring-mgmt-kube-prom-prometheus 9090` (el nombre exacto: `kubectl -n monitoring get svc`).

## Qué se monitoriza

- **Argo CD**: estado de sincronización y salud de cada app, sincronizaciones, peticiones git (dashboard *IDP · Argo CD*).
- **Kyverno**: peticiones de admisión permitidas/denegadas, resultados por política, latencia (*IDP · Kyverno*).
- **Backstage y PostgreSQL**: ninguno exporta métricas propias aquí, así que se ven CPU, memoria, reinicios y estado listo del namespace `backstage` (*IDP · Backstage y PostgreSQL*).
- **Clúster mgmt**: los dashboards de Kubernetes que trae el chart (carpeta *General*).

Alertas propias (`platform/monitoring/alerts.yaml`): app de Argo CD sin sincronizar (15 min) o no sana, admission controller de Kyverno caído (con `failurePolicy: Fail` bloquearía despliegues en `backstage`), Backstage sin pods listos o reiniciándose. Alertmanager las recibe, pero **no hay receptor configurado** (correo, Slack…): se ven en su UI.

## Límites conocidos

- dev y prod **no** se monitorizan. El siguiente paso natural es Prometheus en modo agente en cada spoke con `remote_write` a mgmt.
- Sin disco persistente: al reiniciar el pod de Prometheus se pierden las métricas (retención 3 días).
- Desactivados a propósito en k3d: node-exporter, etcd, scheduler, controller-manager y kube-proxy.
- Sin logs ni trazas (Loki/Tempo quedan en la hoja de ruta).
- Consumo estimado: ~1 GB de RAM extra en mgmt.

## Si algo no aparece

| Síntoma | Causa probable |
|---|---|
| `monitoring-config-mgmt` en OutOfSync/Degraded al principio | Los CRD del operador aún no existen; Argo CD reintenta solo |
| Sin datos de Kyverno | `kubectl -n kyverno get svc --show-labels`: el ServiceMonitor selecciona `app.kubernetes.io/instance=kyverno-mgmt` y el puerto 8000 |
| Sin datos de Argo CD | Targets en Prometheus (*Status → Targets*): busca `serviceMonitor/monitoring/argocd` |
| Los pods de monitoring van lentos | Comprueba la memoria de WSL2 (`docs/wslconfig.example`) |
