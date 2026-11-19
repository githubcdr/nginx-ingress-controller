# syntax=docker/dockerfile:1.7

# ==============================================================================
# Resurrected Kubernetes ingress-nginx Controller (v1.15.1 + NGINX 1.31.9)
#
# Security fixes included via NGINX 1.31.9 (released 2026-11-18):
#   - CVE-2026-123007 (HTTP/2 flow control integer/heap buffer overflow -> RCE)
#   - CVE-2026-123633 (HTTP/2 upstream proxying use-after-free -> RCE)
#   - CVE-2026-123634, CVE-2026-121810, CVE-2026-125283, CVE-2026-118899,
#     CVE-2026-113425, CVE-2026-120993, CVE-2026-120967, CVE-2026-123640
#   - 00_drop-alias-root.patch (hardening: disables root/alias directives)
# ==============================================================================

ARG ALPINE_VERSION=3.23.8
ARG GO_VERSION=1.26-alpine3.23
ARG INGRESS_NGINX_TAG=controller-v1.15.1
ARG INGRESS_NGINX_COMMIT=0a5901f3c64f11e92e487799b8da3f00cca37515
ARG VERSION=v1.15.1-nginx1.31.9

# ------------------------------------------------------------------------------
# Stage 1: Build NGINX 1.31.9 + OpenResty Lua + ModSecurity + OTEL + njs
# ------------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS nginx-builder

ARG VERIFY_CHECKSUMS=true

COPY nginx/build.sh /build.sh
COPY nginx/patches /patches

RUN apk update \
  && apk upgrade --no-cache \
  && apk add --no-cache bash \
  && chmod +x /build.sh \
  && VERIFY_CHECKSUMS="${VERIFY_CHECKSUMS}" /build.sh

# ------------------------------------------------------------------------------
# Stage 2: Build ingress-nginx Go Controller Binaries (pinned v1.15.1)
# ------------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS controller-builder

ARG TARGETOS=linux
ARG TARGETARCH
ARG INGRESS_NGINX_TAG
ARG INGRESS_NGINX_COMMIT
ARG VERSION

RUN apk add --no-cache git ca-certificates

WORKDIR /src
RUN git clone --depth 1 --branch "${INGRESS_NGINX_TAG}" https://github.com/kubernetes/ingress-nginx.git . \
  && ACTUAL_COMMIT="$(git rev-parse HEAD)" \
  && if [ "${ACTUAL_COMMIT}" != "${INGRESS_NGINX_COMMIT}" ]; then \
       echo "ERROR: Expected commit ${INGRESS_NGINX_COMMIT}, got ${ACTUAL_COMMIT}" >&2; \
       exit 1; \
     fi

ENV CGO_ENABLED=0 \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH}

RUN PKG="k8s.io/ingress-nginx" \
  && REPO_INFO="https://github.com/kubernetes/ingress-nginx" \
  && LDFLAGS="-buildid= -w -s -X ${PKG}/version.RELEASE=${VERSION} -X ${PKG}/version.COMMIT=${INGRESS_NGINX_COMMIT} -X ${PKG}/version.REPO=${REPO_INFO}" \
  && mkdir -p /out/bin \
  && go build -trimpath -ldflags="${LDFLAGS}" -buildvcs=false -o /out/bin/nginx-ingress-controller "${PKG}/cmd/nginx" \
  && go build -trimpath -ldflags="${LDFLAGS}" -buildvcs=false -o /out/bin/dbg "${PKG}/cmd/dbg" \
  && go build -trimpath -ldflags="${LDFLAGS}" -buildvcs=false -o /out/bin/wait-shutdown "${PKG}/cmd/waitshutdown"

# ------------------------------------------------------------------------------
# Stage 3: Minimal Hardened Runtime Image
# ------------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION}

ARG VERSION
ARG INGRESS_NGINX_COMMIT

LABEL org.opencontainers.image.title="NGINX Ingress Controller for Kubernetes (Resurrected)" \
      org.opencontainers.image.description="Security-updated kubernetes/ingress-nginx v1.15.1 built with NGINX 1.31.9 (fixes CVE-2026-123007 and CVE-2026-123633)" \
      org.opencontainers.image.source="https://github.com/githubcdr/nginx-ingress-controller" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${INGRESS_NGINX_COMMIT}"

ENV PATH=$PATH:/usr/local/luajit/bin:/usr/local/nginx/sbin:/usr/local/nginx/bin
ENV LUA_PATH="/usr/local/share/luajit-2.1/?.lua;/usr/local/share/luajit-2.1.0-beta3/?.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/lib/lua/?.lua;;"
ENV LUA_CPATH="/usr/local/lib/lua/?/?.so;/usr/local/lib/lua/?.so;;"

COPY --from=nginx-builder /usr/local /usr/local
COPY --from=nginx-builder /usr/lib/libopentelemetry* /usr/local/lib/
COPY --from=nginx-builder /opt /opt
COPY --from=nginx-builder /etc/nginx /etc/nginx

RUN apk update \
  && apk upgrade --no-cache \
  && apk add --no-cache \
    bash \
    openssl \
    pcre \
    zlib \
    ca-certificates \
    patch \
    yajl \
    lmdb \
    libxml2 \
    libmaxminddb \
    yaml-cpp \
    dumb-init \
    tzdata \
    grpc-cpp \
    libprotobuf \
    abseil-cpp-crc-cpu-detect \
    abseil-cpp-vlog-config-internal \
    diffutils \
  && ln -sf /usr/local/nginx/sbin/nginx /sbin/nginx \
  && ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx \
  && adduser -S -D -H -u 101 -h /usr/local/nginx -s /sbin/nologin -G www-data -g www-data www-data \
  && rm -rf /var/cache/apk/*

WORKDIR /etc/nginx

COPY --from=controller-builder --chown=www-data:www-data /src/rootfs/etc /etc
COPY --from=controller-builder --chown=www-data:www-data /out/bin/dbg /
COPY --from=controller-builder --chown=www-data:www-data /out/bin/nginx-ingress-controller /
COPY --from=controller-builder --chown=www-data:www-data /out/bin/wait-shutdown /

RUN bash -eu -c ' \
  writeDirs=( \
    /etc/ingress-controller \
    /etc/ingress-controller/ssl \
    /etc/ingress-controller/auth \
    /etc/ingress-controller/geoip \
    /etc/ingress-controller/telemetry \
    /var/log \
    /var/log/nginx \
    /var/lib/nginx/body \
    /var/lib/nginx/fastcgi \
    /var/lib/nginx/proxy \
    /var/lib/nginx/scgi \
    /var/lib/nginx/uwsgi \
    /var/log/audit \
    /tmp/nginx \
  ); \
  for dir in "${writeDirs[@]}"; do \
    mkdir -p "${dir}"; \
    chown -R www-data:www-data "${dir}"; \
  done' \
  && echo "/lib:/usr/lib:/usr/local/lib:/modules_mount/etc/nginx/modules/otel" > "/etc/ld-musl-$(uname -m).path" \
  && apk add --no-cache libcap \
  && setcap    cap_net_bind_service=+ep /nginx-ingress-controller \
  && setcap -v cap_net_bind_service=+ep /nginx-ingress-controller \
  && setcap    cap_net_bind_service=+ep /usr/local/nginx/sbin/nginx \
  && setcap -v cap_net_bind_service=+ep /usr/local/nginx/sbin/nginx \
  && setcap    cap_net_bind_service=+ep /usr/bin/dumb-init \
  && setcap -v cap_net_bind_service=+ep /usr/bin/dumb-init \
  && apk del libcap \
  && rm -rf /var/cache/apk/*

USER www-data

# Redirect NGINX logs to container stdout/stderr
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
  && ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80 443 8443 10254

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/nginx-ingress-controller"]
