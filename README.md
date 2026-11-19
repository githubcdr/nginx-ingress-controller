# nginx-ingress-controller-resurrected

A security-updated, ready-to-run Docker image for the archived [`kubernetes/ingress-nginx`](https://github.com/kubernetes/ingress-nginx) controller (`controller-v1.15.1`), rebuilt with **NGINX 1.31.9** (released November 18, 2026) and updated OpenResty Lua / Alpine 3.23.8 runtime components.

> **Note:** `kubernetes/ingress-nginx` was officially archived on March 24, 2026 (`v1.15.1` was the final upstream release, still bundling NGINX `1.27.1`). This repository provides a drop-in patched container image to remediate the November 2026 critical NGINX RCE vulnerabilities while you plan a migration to Gateway API or an actively maintained ingress controller.

## Security Fixes Included

Upgrading NGINX from `1.27.1` to **`1.31.9`** (alongside OpenResty `1.31.8.1`-aligned modules, Alpine `3.23.8`, OWASP CRS `v4.29.0`, and `njs 1.0.2`) remediates the November 18, 2026 "NGINX2Root" vulnerabilities and all prior 2025/2026 NGINX CVEs:

| CVE | Component | Impact | Fixed in |
| :--- | :--- | :--- | :--- |
| **CVE-2026-123007** | HTTP/2 flow control (`ngx_http_v2_module`) | Integer/heap buffer overflow → unauthenticated RCE / DoS | NGINX 1.30.7 / **1.31.9** |
| **CVE-2026-123633** | HTTP/2 upstream proxying (`ngx_http_v2_module`) | Use-after-free under connection pressure → RCE / DoS | NGINX 1.30.7 / **1.31.9** |
| **CVE-2026-123634** | DNS resolver | Use-after-free | NGINX 1.30.7 / **1.31.9** |
| **CVE-2026-121810** | HTTP/3 (`ngx_http_v3_module`) | Use-after-free | NGINX 1.30.7 / **1.31.9** |
| **CVE-2026-125283** | `alias` + `try_files` | Buffer overflow (also neutralized by `00_drop-alias-root.patch`) | NGINX 1.30.7 / **1.31.9** |
| **CVE-2026-118899** | TLS 1.3 request body reading | Infinite loop (DoS) | NGINX 1.30.7 / **1.31.9** |
| **CVE-2026-113425** | Mail proxy module | Use-after-free (module also disabled at compile time) | NGINX 1.30.7 / **1.31.9** |
| **CVE-2026-120993** | PROXY protocol v2 | NULL pointer dereference | NGINX 1.30.7 / **1.31.9** |
| **CVE-2026-120967 / 123640** | Stream & SSL preread | Validation bypasses | NGINX 1.30.7 / **1.31.9** |

### Additional Hardening
- **Strict SHA-256 verification** re-enabled in [`nginx/build.sh`](nginx/build.sh) for all 28 downloaded source tarballs (upstream had checksum verification commented out).
- **Pinned upstream controller commit**: `controller-v1.15.1` (`0a5901f3c64f11e92e487799b8da3f00cca37515`) verified during build.
- **`00_drop-alias-root.patch`** updated for NGINX `1.31.9` to strip the `root` and `alias` directives from NGINX core.
- **Minimal non-root runtime**: Alpine `3.23.8`, runs as `www-data` (UID `101`), `cap_net_bind_service=+ep` only, `libcap` removed after `setcap`, no compilers or static `.a` libraries in the final image.
- **Multi-arch ready**: Builds cleanly for `linux/amd64` and `linux/arm64` (including dynamic musl linker path `/etc/ld-musl-$(uname -m).path`).

## Build the Docker Image

### Single architecture (local)
```bash
docker build -t nginx-ingress-controller:v1.15.1-nginx1.31.9 .
```

### Multi-architecture (amd64 + arm64) and push to GHCR
```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/githubcdr/nginx-ingress-controller:v1.15.1-nginx1.31.9 \
  --push .
```

## Verify the Built Image

```bash
# Confirm NGINX 1.31.9 and compiled modules
docker run --rm --entrypoint nginx nginx-ingress-controller:v1.15.1-nginx1.31.9 -V

# Confirm controller version
docker run --rm nginx-ingress-controller:v1.15.1-nginx1.31.9 /nginx-ingress-controller --version

# Confirm non-root UID 101
docker run --rm --entrypoint id nginx-ingress-controller:v1.15.1-nginx1.31.9 -u

# Confirm 'root' directive is stripped (should report: unknown directive "root")
docker run --rm --entrypoint nginx nginx-ingress-controller:v1.15.1-nginx1.31.9 \
  -g 'events{} http{ server{ location / { root /etc; } } }' -t
```

## Deploy to Kubernetes (Drop-in Helm Upgrade)

Use [`deploy/helm-values.yaml`](deploy/helm-values.yaml) to swap the image in an existing `ingress-nginx` Helm release:

```bash
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --reuse-values \
  -f deploy/helm-values.yaml \
  --set controller.image.registry=ghcr.io \
  --set controller.image.image=githubcdr/nginx-ingress-controller \
  --set controller.image.tag=v1.15.1-nginx1.31.9
```

## CI / Automated Builds & Vulnerability Scanning

A GitHub Actions workflow is included at [`.github/workflows/build-and-scan.yml`](.github/workflows/build-and-scan.yml) that:
1. Builds the image and runs automated smoke tests (`nginx/1.31.9`, `root` directive rejection, controller `--version`, non-root UID `101`).
2. Scans the image with Trivy (`CRITICAL,HIGH`).
3. Pushes multi-arch (`linux/amd64`, `linux/arm64`) images to GHCR on pushes to `main` or `v*` tags.
