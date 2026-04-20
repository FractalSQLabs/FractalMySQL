#!/usr/bin/env bash
#
# scripts/package.sh — mysql-fractalsql packaging.
#
# Assumes ./build.sh ${ARCH} has produced:
#   dist/${ARCH}/fractalsql.so
#
# Emits one .deb and one .rpm per arch into dist/packages/:
#   dist/packages/mysql-fractalsql-amd64.deb
#   dist/packages/mysql-fractalsql-amd64.rpm
#   dist/packages/mysql-fractalsql-arm64.deb
#   dist/packages/mysql-fractalsql-arm64.rpm
#
# One binary covers MySQL 8.0 / 8.4 LTS / 9.x — the UDF ABI is stable
# since MySQL 8.0.0, so the package depends on mysql-server generically
# rather than pinning a specific major.
#
# Usage:
#   scripts/package.sh [amd64|arm64]     # default: amd64

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="1.0.0"
ITERATION="1"
DIST_DIR="dist/packages"
PKG_NAME="mysql-fractalsql"
mkdir -p "${DIST_DIR}"

# Absolute repo root, captured before any -C chdir'd fpm invocation.
REPO_ROOT="$(pwd)"
for f in LICENSE LICENSE-THIRD-PARTY; do
    if [ ! -f "${REPO_ROOT}/${f}" ]; then
        echo "missing ${REPO_ROOT}/${f} — refusing to package without it" >&2
        exit 1
    fi
done

PKG_ARCH="${1:-amd64}"
case "${PKG_ARCH}" in
    amd64|arm64) ;;
    *)
        echo "unknown arch '${PKG_ARCH}' — expected amd64 or arm64" >&2
        exit 2
        ;;
esac

case "${PKG_ARCH}" in
    amd64) RPM_ARCH="x86_64"  ;;
    arm64) RPM_ARCH="aarch64" ;;
esac

SO="dist/${PKG_ARCH}/fractalsql.so"
if [ ! -f "${SO}" ]; then
    echo "missing ${SO} — run ./build.sh ${PKG_ARCH} first" >&2
    exit 1
fi

DEB_OUT="${DIST_DIR}/${PKG_NAME}-${PKG_ARCH}.deb"
RPM_OUT="${DIST_DIR}/${PKG_NAME}-${PKG_ARCH}.rpm"

# Build per-format staging roots. The plugin_dir mysqld actually
# reads from differs across distros — we match each one:
#
#   Debian/Ubuntu mysql-server / mysql-community-server (apt):
#       plugin_dir = /usr/lib/mysql/plugin/
#   RHEL/CentOS/Oracle Linux mysql-community-server (yum):
#       plugin_dir = /usr/lib64/mysql/plugin/   (el9 RPM uses lib64)
#
# Shipping the .so at the wrong path means CREATE FUNCTION ...
# SONAME 'fractalsql.so' silently fails to resolve at load time, so
# we stage two separate trees and point fpm at the appropriate one.
# (Verified by docker logs from the mysql:8.0 image, which is
# 8.0.45-1.el9 and reports @@plugin_dir = /usr/lib64/mysql/plugin/.)
#
# LICENSE ledger: staged into /usr/share/doc/<pkg>/ via install -Dm0644
# BEFORE running fpm. Explicit fpm src=dst mappings break here — fpm's
# -C chroots absolute source paths too, so ${REPO_ROOT}/LICENSE gets
# resolved as ${STAGE}${REPO_ROOT}/LICENSE and fpm bails with
# "Cannot chdir to ...".
STAGE_DEB="$(mktemp -d)"
STAGE_RPM="$(mktemp -d)"
trap 'rm -rf "${STAGE_DEB}" "${STAGE_RPM}"' EXIT

stage_common() {
    local stage="$1"
    install -Dm0644 sql/install_udf.sql \
        "${stage}/usr/share/${PKG_NAME}/install_udf.sql"
    install -Dm0644 "${REPO_ROOT}/LICENSE" \
        "${stage}/usr/share/doc/${PKG_NAME}/LICENSE"
    install -Dm0644 "${REPO_ROOT}/LICENSE-THIRD-PARTY" \
        "${stage}/usr/share/doc/${PKG_NAME}/LICENSE-THIRD-PARTY"
}

# Debian layout.
install -Dm0755 "${SO}" \
    "${STAGE_DEB}/usr/lib/mysql/plugin/fractalsql.so"
stage_common "${STAGE_DEB}"

# RHEL layout (/usr/lib64/).
install -Dm0755 "${SO}" \
    "${STAGE_RPM}/usr/lib64/mysql/plugin/fractalsql.so"
stage_common "${STAGE_RPM}"

echo "------------------------------------------"
echo "Packaging ${PKG_NAME} (${PKG_ARCH})"
echo "------------------------------------------"

# LuaJIT is statically linked into fractalsql.so — no libluajit-5.1-2
# (Debian) or luajit (RPM) runtime dependency is declared. mysql-server
# is depended on generically: the same .so works on 8.0 / 8.4 / 9.x.
fpm -s dir -t deb \
    -n "${PKG_NAME}" \
    -v "${VERSION}" \
    -a "${PKG_ARCH}" \
    --iteration "${ITERATION}" \
    --description "FractalSQL: Stochastic Fractal Search UDF for MySQL (8.0 / 8.4 LTS / 9.x)" \
    --license "MIT" \
    --depends "libc6 (>= 2.38)" \
    --depends "mysql-server | mysql-community-server | mariadb-server" \
    -C "${STAGE_DEB}" \
    -p "${DEB_OUT}" \
    usr

fpm -s dir -t rpm \
    -n "${PKG_NAME}" \
    -v "${VERSION}" \
    -a "${RPM_ARCH}" \
    --iteration "${ITERATION}" \
    --description "FractalSQL: Stochastic Fractal Search UDF for MySQL (8.0 / 8.4 LTS / 9.x)" \
    --license "MIT" \
    --depends "mysql-community-server" \
    -C "${STAGE_RPM}" \
    -p "${RPM_OUT}" \
    usr

rm -rf "${STAGE_DEB}" "${STAGE_RPM}"
trap - EXIT

echo
echo "Done. Packages in ${DIST_DIR}:"
ls -l "${DIST_DIR}"
