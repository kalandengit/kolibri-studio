# Kolibri Studio on Kubernetes

Manifests for a self-contained deployment (PostgreSQL, Redis and MinIO run
in-cluster). For serious production use, prefer managed Postgres/Redis/object
storage and point the ConfigMap/Secret at them instead.

## 1. Build and push the image

Kubernetes pulls images from a registry, so build the production image
(defined in `docker/Dockerfile.prod`) and push it to a registry your cluster
can reach:

```bash
docker build -t <registry>/studio-app-prod:latest -f docker/Dockerfile.prod .
docker push <registry>/studio-app-prod:latest
```

Then set `images.newName` in `kustomization.yaml` to `<registry>/studio-app-prod`.

## 2. Create secrets

```bash
cp secrets.example.yaml secrets.yaml   # fill in real values, never commit it
kubectl apply -f namespace.yaml
kubectl apply -f secrets.yaml
```

## 3. Deploy everything

```bash
kubectl apply -k deploy/k8s/
```

This creates: Postgres (StatefulSet, 20Gi PVC), Redis, MinIO (StatefulSet,
50Gi PVC) with a bucket-init Job, the Django app (2 replicas, gunicorn :8081),
a Celery worker, a migration Job, and an Ingress.

## 4. First-time initialization

Migrations run via the `studio-migrate` Job. To seed demo data
(admin `a@a.com` / `a`):

```bash
kubectl -n kolibri-studio exec deploy/studio-app -- python contentcuration/manage.py setup
```

## 5. Upgrades

```bash
docker build/push a new tag, update kustomization.yaml, then:
kubectl -n kolibri-studio delete job studio-migrate --ignore-not-found
kubectl apply -k deploy/k8s/
```

## Notes

- The Ingress assumes ingress-nginx; edit `host` in `ingress.yaml` and
  uncomment the TLS/cert-manager lines for HTTPS.
- Content files are served from MinIO through the app's storage URLs; the
  bucket allows anonymous downloads (same as the upstream dev setup).
- `DJANGO_SETTINGS_MODULE` defaults to `contentcuration.not_production_settings`
  (no real emails, permissive hosts). Switch to `contentcuration.settings`
  and configure email/Sentry/GCS for real production.
