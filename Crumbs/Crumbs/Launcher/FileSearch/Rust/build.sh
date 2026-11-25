#!/bin/sh
set -eu
crate=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(cd "$crate/../../../../.." && pwd)
out=${1:-"$root/.build/file-search"}
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-26.0}
mkdir -p "$out"
set --
for arch in ${ARCHS:-$(uname -m)}; do
    case "$arch" in
        arm64) target=aarch64-apple-darwin ;;
        x86_64) target=x86_64-apple-darwin ;;
        *) echo "Unsupported Mac architecture: $arch" >&2; exit 1 ;;
    esac
    cargo build --manifest-path "$crate/Cargo.toml" --locked --release \
        --target "$target" --target-dir "$out/cargo"
    set -- "$@" "$out/cargo/$target/release/libcrumbs_file_search.a"
done
lipo -create "$@" -output "$out/libcrumbs_file_search.a"
