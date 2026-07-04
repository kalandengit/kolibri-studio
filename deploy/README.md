# Deploying Kolibri Studio

Three options, from simplest to most scalable:

| Option | For | How |
|---|---|---|
| **Cloud VPS (Docker Compose)** | one server, demo/staging/small prod | `sudo bash deploy/install-vps.sh --with-demo-data` |
| **Docker image only** | your own orchestration | `docker build -t studio-app-prod -f docker/Dockerfile.prod .` |
| **Kubernetes** | scalable production | see [k8s/README.md](k8s/README.md) |

## Cloud VPS quick start

On a fresh Ubuntu/Debian/RHEL-family VPS (2+ vCPU, 4+ GB RAM recommended):

```bash
# copy the project to the server, then:
sudo bash deploy/install-vps.sh --with-demo-data --port 8080
```

The script installs Docker, generates random secrets into `deploy/.env`,
builds the image, starts PostgreSQL + Redis + MinIO + Django (gunicorn) +
Celery, runs migrations, and (with `--with-demo-data`) seeds the admin
account `a@a.com` / `a`.

Put a reverse proxy with TLS (Caddy, nginx + certbot) in front of the port
for public deployments, and review `deploy/.env` before real use.

## The Docker image

`docker/Dockerfile.prod` (upstream) builds a single image containing the
compiled frontend and the Django backend; its entrypoint runs
`make altprodserver` (gunicorn on port 8081). The same image is used for the
Celery worker with the command `make prodceleryworkers`, and by all the
Kubernetes manifests.
