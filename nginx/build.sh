#!/bin/bash

# Copyright 2023 The Kubernetes Authors. All rights reserved.
# Updated 2026 for NGINX 1.31.9 security remediation (CVE-2026-123007, CVE-2026-123633, et al.)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

# NGINX 1.31.9 (released 2026-11-18) fixes:
# - CVE-2026-123007 (HTTP/2 flow control integer/heap buffer overflow - RCE)
# - CVE-2026-123633 (HTTP/2 upstream proxying use-after-free - RCE)
# - CVE-2026-123634, CVE-2026-121810, CVE-2026-125283, CVE-2026-118899,
#   CVE-2026-113425, CVE-2026-120993, CVE-2026-120967, CVE-2026-123640
export NGINX_VERSION=1.31.9

# OpenResty 1.31.8.1 compatible module versions
export NDK_VERSION=v0.3.6
export SETMISC_VERSION=v0.34
export MORE_HEADERS_VERSION=v0.40
export NGINX_DIGEST_AUTH=v1.0.0
export MODSECURITY_VERSION=v1.0.4
# ModSecurity v3.0.17 fixes CVE-2026-30923, CVE-2026-52747, CVE-2026-52761, CVE-2026-73856, CVE-2026-104269
export MODSECURITY_LIB_VERSION=v3.0.17
export OWASP_MODSECURITY_CRS_VERSION=v4.29.0
export LUA_NGX_VERSION=v0.10.32rc7
export LUA_STREAM_NGX_VERSION=v0.0.20rc3
export LUA_UPSTREAM_VERSION=v0.08
export LUA_CJSON_VERSION=2.1.0.20
export GEOIP2_VERSION=445df24ef3781e488cee3dfe8a1e111997fc1dfe
export LUAJIT_VERSION=v2.1-20261023
export LUA_RESTY_BALANCER=v0.05
export LUA_RESTY_CACHE=v0.15
export LUA_RESTY_CORE=v0.1.35rc2
export LUA_RESTY_COOKIE_VERSION=f418d77082eaef48331302e84330488fdc810ef4
export LUA_RESTY_DNS=v0.24
export LUA_RESTY_HTTP=v0.17.2
export LUA_RESTY_LOCK=v0.09
export LUA_RESTY_UPLOAD_VERSION=v0.11
export LUA_RESTY_STRING_VERSION=v0.19
export LUA_RESTY_MEMCACHED_VERSION=v0.18
export LUA_RESTY_REDIS_VERSION=v0.34
export LUA_RESTY_IPMATCHER_VERSION=3e93c53eb8c9884efe939ef070486a0e507cc5be
export MIMALOC_VERSION=v2.2.4
export OPENTELEMETRY_CPP_VERSION=v1.19.0
export OPENTELEMETRY_PROTO_VERSION=v1.5.0
export NJS_VERSION=1.0.2

export BUILD_PATH=/tmp/build
VERIFY_CHECKSUMS="${VERIFY_CHECKSUMS:-true}"

ARCH=$(uname -m)

get_src()
{
  hash="$1"
  url="$2"
  dest="${3-}"
  ARGS=""
  f=$(basename "$url")

  echo "Downloading $url"

  curl -fsSL "$url" -o "$f"
  if [ "$VERIFY_CHECKSUMS" = "true" ]; then
    echo "$hash  $f" | sha256sum -c - || exit 10
  fi
  if [ -n "$dest" ]; then
    mkdir -p "${BUILD_PATH}/${dest}"
    ARGS="-C ${BUILD_PATH}/${dest} --strip-components=1"
  fi
  tar xzf "$f" $ARGS
  rm -rf "$f"
}

# Install required packages to build
# Dependencies from "ninja" and below are OTEL dependencies
apk add --no-cache \
  bash \
  gcc \
  clang \
  libc-dev \
  make \
  automake \
  openssl-dev \
  pcre-dev \
  pcre2-dev \
  zlib-dev \
  linux-headers \
  libxslt-dev \
  gd-dev \
  perl-dev \
  libedit-dev \
  mercurial \
  alpine-sdk \
  findutils \
  curl \
  ca-certificates \
  patch \
  libaio-dev \
  openssl \
  cmake \
  util-linux \
  lmdb-tools \
  wget \
  curl-dev \
  libprotobuf \
  git g++ pkgconf flex bison doxygen yajl-dev lmdb-dev libtool autoconf libxml2 libxml2-dev \
  python3 \
  libmaxminddb-dev \
  bc \
  unzip \
  dos2unix \
  yaml-cpp \
  coreutils \
  ninja \
  gtest-dev \
  build-base \
  pkgconfig \
  c-ares-dev \
  re2-dev \
  grpc-dev \
  protobuf-dev

mkdir -p /etc/nginx
mkdir --verbose -p "$BUILD_PATH"
cd "$BUILD_PATH"

# Download, verify SHA-256 checksums, and extract source tarballs
get_src a11c5eeee2e257f4478f0e649f84b0040787d277d2d3e5233952aa6b6dcb80ad \
        "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"

get_src e3438a71130b63760ac4accec9f77ac8f91ad8f778e1940b061e9ea83dd62fe7 \
        "https://github.com/openresty/ngx_devel_kit/archive/$NDK_VERSION.tar.gz" "ngx_devel_kit"

get_src e0330194b72f2fe4c0ce3ece06b02dc4aa0ab491eb75bf42c6f5e283912e468c \
        "https://github.com/open-telemetry/opentelemetry-cpp/archive/$OPENTELEMETRY_CPP_VERSION.tar.gz" "opentelemetry-cpp"

get_src 08f40636adbc5f33d2084bd8e7b64e491dd0239d1a95021dbffbdf1ca8cea454 \
        "https://github.com/open-telemetry/opentelemetry-proto/archive/$OPENTELEMETRY_PROTO_VERSION.tar.gz" "opentelemetry-proto"

get_src f083e6a68520a9dfa09f0afbeb88ab7539f479cc5af91d8607ae2ab1874f9898 \
        "https://github.com/openresty/set-misc-nginx-module/archive/$SETMISC_VERSION.tar.gz" "set-misc-nginx-module"

get_src c14cb5e6c998590c209efbf77bd7637ce2cab02332e4192756a8af5b26ba4284 \
        "https://github.com/openresty/headers-more-nginx-module/archive/$MORE_HEADERS_VERSION.tar.gz" "headers-more-nginx-module"

get_src f09851e6309560a8ff3e901548405066c83f1f6ff88aa7171e0763bd9514762b \
        "https://github.com/atomx/nginx-http-auth-digest/archive/$NGINX_DIGEST_AUTH.tar.gz" "nginx-http-auth-digest"

get_src bb596d146ad0650014168dda9dc8d07c50a070010044c95ed0d167a9a78e63a1 \
        "https://github.com/owasp-modsecurity/ModSecurity-nginx/archive/$MODSECURITY_VERSION.tar.gz" "ModSecurity-nginx"

get_src 70e005d3883224a808638154396c65b5e756876e9957c90b244a2f51ca07a843 \
        "https://github.com/openresty/lua-nginx-module/archive/$LUA_NGX_VERSION.tar.gz" "lua-nginx-module"

get_src cbd42d84575be2ca34d58091a519db58b734d9f8ddb9ebb681e0f77e5d9b78f6 \
        "https://github.com/openresty/stream-lua-nginx-module/archive/$LUA_STREAM_NGX_VERSION.tar.gz" "stream-lua-nginx-module"

get_src 722620a74a8f75ac154691933d2ae4969b2173061476a3d3bf0de2b9891a0e45 \
        "https://github.com/openresty/lua-upstream-nginx-module/archive/$LUA_UPSTREAM_VERSION.tar.gz" "lua-upstream-nginx-module"

get_src 46ec00b6ba6261890a7d185c48f848e5e6b7a2909fc39ac80f407d1dcbfc74b2 \
        "https://github.com/openresty/luajit2/archive/$LUAJIT_VERSION.tar.gz" "luajit2"

get_src 5e2113ed09cdd710908df8c6d1630616eeacb9216ef8705a06c25733394ddf28 \
        "https://github.com/leev/ngx_http_geoip2_module/archive/$GEOIP2_VERSION.tar.gz" "ngx_http_geoip2_module"

get_src deb4ab1ffb9f3d962c4b4a2c4bdff692b86a209e3835ae71ebdf3b97189e40a9 \
        "https://github.com/openresty/lua-resty-upload/archive/$LUA_RESTY_UPLOAD_VERSION.tar.gz" "lua-resty-upload"

get_src 8b3e17e8796f083228b89ddd013bcc688c7d15afcc721c70059fd4a8bf2355dc \
        "https://github.com/openresty/lua-resty-string/archive/$LUA_RESTY_STRING_VERSION.tar.gz" "lua-resty-string"

get_src 8b2ff4edefc240dea0d3adb9dd065a42e8c09e06ba8bb0a188464cf76c9e4d06 \
        "https://github.com/openresty/lua-resty-balancer/archive/$LUA_RESTY_BALANCER.tar.gz" "lua-resty-balancer"

get_src fcd84dd01c8d589b0c1f68b11dd54c50d70d9b15d3f6e1a5760e970c4f99b7aa \
        "https://github.com/openresty/lua-resty-core/archive/$LUA_RESTY_CORE.tar.gz" "lua-resty-core"

get_src a99fb872aa731274ac70453cd4e6b2e0e8fb978893063d512ca67c7c332510e1 \
        "https://github.com/openresty/lua-cjson/archive/$LUA_CJSON_VERSION.tar.gz" "lua-cjson"

get_src c0217456f4c36bb9ebbf7dbcd733e3d70734330364c88df73e703c4777521ff9 \
        "https://github.com/cloudflare/lua-resty-cookie/archive/$LUA_RESTY_COOKIE_VERSION.tar.gz" "lua-resty-cookie"

get_src 8cf1a22e0d5b8f35cb0b2e14c58fcb3aa505a8fb6e956817f0cdb1f06593f072 \
        "https://github.com/openresty/lua-resty-lrucache/archive/$LUA_RESTY_CACHE.tar.gz" "lua-resty-lrucache"

get_src b4ddcd47db347e9adf5c1e1491a6279a6ae2a3aff3155ef77ea0a65c998a69c1 \
        "https://github.com/openresty/lua-resty-lock/archive/$LUA_RESTY_LOCK.tar.gz" "lua-resty-lock"

get_src 06e08aec4290ee83b505a0b9fa66fa4e9fbe729ce505bc88f3dc2093789223f7 \
        "https://github.com/openresty/lua-resty-dns/archive/$LUA_RESTY_DNS.tar.gz" "lua-resty-dns"

get_src 3da18ca8582243eff28302591e36651dc7fab046e77336aa4a6fa718bccce4a2 \
        "https://github.com/ledgetech/lua-resty-http/archive/$LUA_RESTY_HTTP.tar.gz" "lua-resty-http"

get_src 3567144cfa26e63453960ec347137f47403b264af071385d2f16b8434eb3736e \
        "https://github.com/openresty/lua-resty-memcached/archive/$LUA_RESTY_MEMCACHED_VERSION.tar.gz" "lua-resty-memcached"

get_src 427fde15a4ad2237c947368bee2c443bf8f402e339f64bf3716de324c6afb613 \
        "https://github.com/openresty/lua-resty-redis/archive/$LUA_RESTY_REDIS_VERSION.tar.gz" "lua-resty-redis"

get_src bf4f89c0c00d1e986260d22180cbccbd2016eb054b5c2adcc1b6ee0ff773032f \
        "https://github.com/api7/lua-resty-ipmatcher/archive/$LUA_RESTY_IPMATCHER_VERSION.tar.gz" "lua-resty-ipmatcher"

get_src 754a98de5e2912fddbeaf24830f982b4540992f1bab4a0a8796ee118e0752bda \
        "https://github.com/microsoft/mimalloc/archive/${MIMALOC_VERSION}.tar.gz" "mimalloc"

get_src 84a114499fa6878d3ec52b99c1cf2874a91eb0d915408f418a2b1279519f09ae \
        "https://github.com/nginx/njs/archive/${NJS_VERSION}.tar.gz" "njs"

# Improve compilation times (safely handle single-core runners)
CORES=$(nproc)
if [ "$CORES" -gt 1 ]; then
  CORES=$((CORES - 1))
fi

export MAKEFLAGS=-j${CORES}
export CTEST_BUILD_FLAGS=${MAKEFLAGS}

# Install LuaJIT from OpenResty fork
export LUAJIT_LIB=/usr/local/lib
export LUA_LIB_DIR="$LUAJIT_LIB/lua"
export LUAJIT_INC=/usr/local/include/luajit-2.1

cd "$BUILD_PATH/luajit2"
make CCDEBUG=-g
make install

ln -sf /usr/local/bin/luajit /usr/local/bin/lua
ln -sf "$LUAJIT_INC" /usr/local/include/lua

cd "$BUILD_PATH/opentelemetry-cpp"
export CXXFLAGS="-DBENCHMARK_HAS_NO_INLINE_ASSEMBLY"
cmake -B build -G Ninja -Wno-dev \
  -DOTELCPP_PROTO_PATH="${BUILD_PATH}/opentelemetry-proto/" \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_TESTING="OFF" \
  -DBUILD_W3CTRACECONTEXT_TEST="OFF" \
  -DCMAKE_BUILD_TYPE=None \
  -DWITH_ABSEIL=ON \
  -DWITH_STL=ON \
  -DWITH_EXAMPLES=OFF \
  -DWITH_ZPAGES=OFF \
  -DWITH_OTLP_GRPC=ON \
  -DWITH_OTLP_HTTP=ON \
  -DWITH_ZIPKIN=ON \
  -DWITH_PROMETHEUS=OFF \
  -DWITH_ASYNC_EXPORT_PREVIEW=OFF \
  -DWITH_METRICS_EXEMPLAR_PREVIEW=OFF
cmake --build build
cmake --install build

# Git tuning
git config --global --add core.compression -1

# Get Brotli source and deps
cd "$BUILD_PATH"
git clone --depth=100 https://github.com/google/ngx_brotli.git
cd ngx_brotli
git reset --hard a71f9312c2deb28875acc7bacfdd5695a111aa53
git submodule init
git submodule update

cd "$BUILD_PATH"
git clone --depth=1 https://github.com/ssdeep-project/ssdeep
cd ssdeep/
./bootstrap
./configure
make
make install

# Build ModSecurity library
cd "$BUILD_PATH"
git clone -n https://github.com/owasp-modsecurity/ModSecurity
cd ModSecurity/
git checkout "$MODSECURITY_LIB_VERSION"
git submodule update --init --recursive

sh build.sh

# https://github.com/owasp-modsecurity/ModSecurity/issues/1909#issuecomment-465926762
sed -i '115i LUA_CFLAGS="${LUA_CFLAGS} -DWITH_LUA_JIT_2_1"' build/lua.m4
sed -i '117i AC_SUBST(LUA_CFLAGS)' build/lua.m4

./configure \
  --disable-doxygen-doc \
  --disable-doxygen-html \
  --disable-examples

make
make install

mkdir -p /etc/nginx/modsecurity
cp modsecurity.conf-recommended /etc/nginx/modsecurity/modsecurity.conf
cp unicode.mapping /etc/nginx/modsecurity/unicode.mapping

# Replace serial logging with concurrent
sed -i 's|SecAuditLogType Serial|SecAuditLogType Concurrent|g' /etc/nginx/modsecurity/modsecurity.conf

# Concurrent logging implies the log is stored in several files
echo "SecAuditLogStorageDir /var/log/audit/" >> /etc/nginx/modsecurity/modsecurity.conf

# Download OWASP ModSecurity CRS v4
cd /etc/nginx/
git clone --depth 1 -b "$OWASP_MODSECURITY_CRS_VERSION" https://github.com/coreruleset/coreruleset
mv coreruleset owasp-modsecurity-crs
cd owasp-modsecurity-crs

mv crs-setup.conf.example crs-setup.conf
mv rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
mv rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf
cd ..

# OWASP CRS v4 rules
cat <<'EOF' > /etc/nginx/owasp-modsecurity-crs/nginx-modsecurity.conf
Include /etc/nginx/owasp-modsecurity-crs/crs-setup.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-901-INITIALIZATION.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-905-COMMON-EXCEPTIONS.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-911-METHOD-ENFORCEMENT.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-913-SCANNER-DETECTION.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-920-PROTOCOL-ENFORCEMENT.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-921-PROTOCOL-ATTACK.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-922-MULTIPART-ATTACK.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-930-APPLICATION-ATTACK-LFI.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-931-APPLICATION-ATTACK-RFI.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-932-APPLICATION-ATTACK-RCE.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-933-APPLICATION-ATTACK-PHP.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-934-APPLICATION-ATTACK-GENERIC.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-941-APPLICATION-ATTACK-XSS.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-942-APPLICATION-ATTACK-SQLI.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-943-APPLICATION-ATTACK-SESSION-FIXATION.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-944-APPLICATION-ATTACK-JAVA.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-949-BLOCKING-EVALUATION.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-950-DATA-LEAKAGES.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-951-DATA-LEAKAGES-SQL.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-952-DATA-LEAKAGES-JAVA.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-953-DATA-LEAKAGES-PHP.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-954-DATA-LEAKAGES-IIS.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-955-WEB-SHELLS.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-959-BLOCKING-EVALUATION.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-980-CORRELATION.conf
Include /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf
EOF

# Build NGINX 1.31.9
cd "$BUILD_PATH/nginx-$NGINX_VERSION"

# Apply NGINX patches in sorted order
for PATCH in /patches/*; do
  echo "Patch: $(basename "$PATCH")"
  if [[ "$PATCH" == *.txt ]]; then
    patch -p0 < "$PATCH"
  else
    patch -p1 < "$PATCH"
  fi
done

WITH_FLAGS="--with-debug \
  --with-compat \
  --with-pcre-jit \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_realip_module \
  --with-http_auth_request_module \
  --with-http_addition_module \
  --with-http_gzip_static_module \
  --with-http_sub_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_realip_module \
  --with-stream_ssl_preread_module \
  --with-threads \
  --with-http_secure_link_module \
  --with-http_gunzip_module"

CC_OPT="-g -O2 -fPIE -fstack-protector-strong \
  -Wformat \
  -Werror=format-security \
  -Wno-deprecated-declarations \
  -fno-strict-aliasing \
  -D_FORTIFY_SOURCE=2 \
  --param=ssp-buffer-size=4 \
  -DTCP_FASTOPEN=23 \
  -fPIC \
  -Wno-cast-function-type"

LD_OPT="-fPIE -fPIC -pie -Wl,-z,relro -Wl,-z,now"

if [[ ${ARCH} != "aarch64" ]]; then
  WITH_FLAGS+=" --with-file-aio"
fi

if [[ ${ARCH} == "x86_64" ]]; then
  CC_OPT+=' -m64 -mtune=generic'
fi

WITH_MODULES=" \
  --add-module=$BUILD_PATH/ngx_devel_kit \
  --add-module=$BUILD_PATH/set-misc-nginx-module \
  --add-module=$BUILD_PATH/headers-more-nginx-module \
  --add-module=$BUILD_PATH/lua-nginx-module \
  --add-module=$BUILD_PATH/stream-lua-nginx-module \
  --add-module=$BUILD_PATH/lua-upstream-nginx-module \
  --add-dynamic-module=$BUILD_PATH/nginx-http-auth-digest \
  --add-dynamic-module=$BUILD_PATH/ModSecurity-nginx \
  --add-dynamic-module=$BUILD_PATH/ngx_http_geoip2_module \
  --add-dynamic-module=$BUILD_PATH/ngx_brotli \
  --add-dynamic-module=$BUILD_PATH/njs/nginx"

# Use njs native engine (avoid requiring external quickjs library)
export NJS_QUICKJS=NO

./configure \
  --prefix=/usr/local/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --modules-path=/etc/nginx/modules \
  --http-log-path=/var/log/nginx/access.log \
  --error-log-path=/var/log/nginx/error.log \
  --lock-path=/var/lock/nginx.lock \
  --pid-path=/run/nginx.pid \
  --http-client-body-temp-path=/var/lib/nginx/body \
  --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
  --http-proxy-temp-path=/var/lib/nginx/proxy \
  --http-scgi-temp-path=/var/lib/nginx/scgi \
  --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
  ${WITH_FLAGS} \
  --without-mail_pop3_module \
  --without-mail_smtp_module \
  --without-mail_imap_module \
  --without-http_uwsgi_module \
  --without-http_scgi_module \
  --with-cc-opt="${CC_OPT}" \
  --with-ld-opt="${LD_OPT}" \
  --user=www-data \
  --group=www-data \
  ${WITH_MODULES}

make
make modules
make install

# Build OpenTelemetry NGINX module against NGINX 1.31.9
export OPENTELEMETRY_CONTRIB_COMMIT=8933841f0a7f8737f61404cf0a64acf6b079c8a5
cd "$BUILD_PATH"
git clone https://github.com/open-telemetry/opentelemetry-cpp-contrib.git "opentelemetry-cpp-contrib-${OPENTELEMETRY_CONTRIB_COMMIT}"
cd "${BUILD_PATH}/opentelemetry-cpp-contrib-${OPENTELEMETRY_CONTRIB_COMMIT}"
git reset --hard "${OPENTELEMETRY_CONTRIB_COMMIT}"

# Ensure HTTPS download URL in nginx.cmake
sed -i 's|http://nginx.org/download/|https://nginx.org/download/|g' instrumentation/nginx/nginx.cmake

export OTEL_TEMP_INSTALL=/tmp/otel
mkdir -p "${OTEL_TEMP_INSTALL}"

cd "${BUILD_PATH}/opentelemetry-cpp-contrib-${OPENTELEMETRY_CONTRIB_COMMIT}/instrumentation/nginx"
mkdir -p build
cd build
cmake -DCMAKE_BUILD_TYPE=Release \
  -G Ninja \
  -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_INSTALL_PREFIX="${OTEL_TEMP_INSTALL}" \
  -DBUILD_SHARED_LIBS=ON \
  -DNGINX_VERSION="${NGINX_VERSION}" \
  ..
cmake --build . -j "${CORES}" --target install

mkdir -p /etc/nginx/modules
cp "${OTEL_TEMP_INSTALL}/otel_ngx_module.so" /etc/nginx/modules/otel_ngx_module.so

# Install Lua resty libraries
cd "$BUILD_PATH/lua-resty-core"
make install

cd "$BUILD_PATH/lua-resty-balancer"
make all
make install

export LUA_INCLUDE_DIR=/usr/local/include/luajit-2.1
ln -sf "$LUA_INCLUDE_DIR" /usr/include/lua5.1

cd "$BUILD_PATH/lua-cjson"
make all
make install

cd "$BUILD_PATH/lua-resty-cookie"
make all
make install

cd "$BUILD_PATH/lua-resty-lrucache"
make install

cd "$BUILD_PATH/lua-resty-dns"
make install

cd "$BUILD_PATH/lua-resty-lock"
make install

# Required for OCSP verification
cd "$BUILD_PATH/lua-resty-http"
make install

cd "$BUILD_PATH/lua-resty-upload"
make install

cd "$BUILD_PATH/lua-resty-string"
make install

cd "$BUILD_PATH/lua-resty-memcached"
make install

cd "$BUILD_PATH/lua-resty-redis"
make install

cd "$BUILD_PATH/lua-resty-ipmatcher"
INST_LUADIR=/usr/local/lib/lua make install

# Build mimalloc (disable arch-specific optimizations per kubernetes/ingress-nginx#13608)
cd "$BUILD_PATH/mimalloc"
mkdir -p out/release
cd out/release
cmake -DMI_NO_OPT_ARCH=ON ../..
make
make install

# Update image permissions
writeDirs=( \
  /etc/nginx \
  /usr/local/nginx \
  /opt/modsecurity/var/log \
  /opt/modsecurity/var/upload \
  /opt/modsecurity/var/audit \
  /var/log/audit \
  /var/log/nginx \
);

adduser -S -D -H -u 101 -h /usr/local/nginx -s /sbin/nologin -G www-data -g www-data www-data

for dir in "${writeDirs[@]}"; do
  mkdir -p "${dir}"
  chown -R www-data:www-data "${dir}"
done

rm -rf /etc/nginx/owasp-modsecurity-crs/.git
rm -rf /etc/nginx/owasp-modsecurity-crs/tests

# Remove static .a libraries and temporary build artifacts
find /usr/local -name "*.a" -delete
rm -rf "$BUILD_PATH" "$OTEL_TEMP_INSTALL"
