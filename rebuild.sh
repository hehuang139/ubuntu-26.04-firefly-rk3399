#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
image=${FIREFLY_BUILDER:-firefly-ubuntu26-builder:local}
stage=$(realpath -m -- "${FIREFLY_STAGE:-$PWD/work/ubuntu26}")
output=$(realpath -m -- "${FIREFLY_OUTPUT:-$PWD/outputs}")
ca=${FIREFLY_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}
base=https://cdimage.ubuntu.com/ubuntu-base/releases/26.04/release
prepare() { mkdir -p -- "$stage/inputs" "$stage/records" "$output"; }
run() {
    docker run --rm -v "$PWD:/src:ro" -v "$stage:/out" -v "$output:/images" \
        -e FIREFLY_OUTPUT=/images -e FIREFLY_RAW_ONLY \
        "${@:1:$#-1}" "$image" bash "${!#}"
}
fetch() {
    prepare
    local file
    for file in SHA256SUMS SHA256SUMS.gpg ubuntu-base-26.04.1-base-arm64.tar.gz; do
        curl -fsSL --retry 3 "$base/$file" -o "$stage/inputs/$file.new"
        mv -fT -- "$stage/inputs/$file.new" "$stage/inputs/$file"
    done
}
rootfs() {
    prepare
    run --privileged --network=host \
        -e https_proxy -e http_proxy -e no_proxy -e HTTPS_PROXY -e HTTP_PROXY -e NO_PROXY \
        -v "$ca:/build-ca.pem:ro" -e FIREFLY_CA_BUNDLE=/build-ca.pem /src/scripts/build-rootfs.sh
}
finalize() { run --privileged --network=none /src/scripts/finalize-rootfs.sh; }
assemble() {
    local mode
    for mode in "${@}"; do
        docker run --rm --network=none -v "$PWD:/src:ro" -v "$stage:/out" -v "$output:/images" \
            -e FIREFLY_OUTPUT=/images -e FIREFLY_RAW_ONLY "$image" bash /src/scripts/assemble.sh "$mode"
    done
}
case ${1:-help} in
    fetch) fetch ;;
    rootfs) rootfs ;;
    finalize) finalize ;;
    image) assemble sd emmc ;;
    sd|emmc) assemble "$1" ;;
    all) fetch; rootfs; finalize; assemble sd emmc ;;
    help) printf 'Usage: %s {all|fetch|rootfs|finalize|image|sd|emmc}\n' "$0" ;;
    *) exit 2 ;;
esac
