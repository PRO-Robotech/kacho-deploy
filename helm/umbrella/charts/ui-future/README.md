# kacho-ui-future Helm chart

This chart is intentionally named `ui` so `kacho-deploy/helm/umbrella` can use it
as a drop-in replacement for the legacy `kacho-ui/deploy` dependency.

It installs:

- `ui` Deployment and Service: the module federation host and compatibility
  entrypoint used by ingress, port-forwarding, and existing `kacho-deploy`
  values.
- `ui-dashboard` Deployment and Service: the dashboard remote consumed at
  `/dashboard/assets/remoteEntry.js`.

Build images from this repository root:

```bash
docker build -f host/Dockerfile -t kacho-ui-future-host:dev .
docker build -f dashboard/Dockerfile -t kacho-ui-future-dashboard:dev .
```

Standalone install:

```bash
helm upgrade --install ui ./deploy -n kacho --create-namespace
```

`kacho-deploy` compatibility:

```yaml
ui:
  image: docker.io/prorobotech/kacho-ui-future-host:<tag>
  ingress:
    host: localhost
```

If your image names do not follow the `host` -> `dashboard` convention, set
`ui.dashboard.image` explicitly.
