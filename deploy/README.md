# Deploying Kolibri Studio

Three options, from simplest to most scalable:

| Option | For | How |
|---|---|---|
| **Cloud VPS (Docker Compose)** | one server, demo/staging/small prod | `sudo bash deploy/install-vps.sh --with-demo-data` |
| **Docker image only** | your own orchestration | pulled from GHCR by CI, or `docker build -t studio-app-prod -f docker/Dockerfile.prod .` |
| **Kubernetes** | scalable production | see [k8s/README.md](k8s/README.md) |
| **Windows (native, no Docker/admin)** | local development on Windows | `powershell -ExecutionPolicy Bypass -File deploy\install-windows.ps1` |

## Windows quick start

From a checkout of this repo, in a regular (non-admin) PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File deploy\install-windows.ps1
```

Installs portable Python 3.10, Node 20 + pnpm, PostgreSQL 16, Redis and MinIO
under `%USERPROFILE%\kolibri-studio-env`, installs all dependencies, migrates
and seeds the database, and generates `start-studio.bat`. Options:
`-InstallRoot <dir>`, `-Port <n>`, `-NoDemoData`. Re-running skips completed
steps. Afterwards, launch everything with:

```
%USERPROFILE%\kolibri-studio-env\start-studio.bat
```

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
