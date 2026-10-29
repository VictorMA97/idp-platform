# Servicios registrados

Un fichero `svc-<nombre>.yaml` por servicio. Lo crea la plantilla de Backstage mediante un pull
request; no hace falta editarlos a mano. Ejemplo:

```yaml
service: svc-pagos
repoURL: https://github.com/<usuario>/svc-pagos.git
```

Al aceptar el PR, el ApplicationSet `services` (platform/apps/services-appset.yaml) crea
`svc-pagos-dev` y `svc-pagos-prod`. Para dar de baja un servicio, borra su fichero: Argo CD
elimina las aplicaciones y sus recursos (`prune`).
