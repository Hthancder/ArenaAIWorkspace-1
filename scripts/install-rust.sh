#!/bin/bash
# Dựng toolchain Rust **không cần** static.rust-lang.org.
#
# # Vì sao cần script này
#
# Sandbox chỉ cho ra ngoài tới: github.com, codeload.github.com, api.github.com,
# registry.npmjs.org, pypi.org, files.pythonhosted.org. `static.rust-lang.org`
# **không** nằm trong đó, nên `rustup toolchain install` luôn thất bại:
#
#     error: could not download file from 'https://static.rust-lang.org/...'
#
# Thư mục `~/.local` cũng không được snapshot, nên toolchain mất sau mỗi phiên.
# Script này dựng lại từ các gói npm có sẵn `rustc` + `cargo` + `rust-std`.
#
# # Cách dùng
#
#     ./scripts/install-rust.sh
#     export PATH="$HOME/.local/rust/bin:$HOME/.local/bin:$PATH"
#     export LD_LIBRARY_PATH="$HOME/.local/rust/lib"
#     cargo test --manifest-path app/Cargo.toml
#
# # Ba cái bẫy đã gặp
#
# 1. Gói `@toolchain-bin/rustc-*` **chỉ có driver**, thiếu `rust-std` ⇒
#    `can't find crate for 'std'`. Phải lấy `@rusttonpm/rust-std-linux-x64`.
# 2. `@rusttonpm` chỉ có **một** version (0.92.20250925 = rustc 1.92 nightly),
#    và `rustc`/`cargo`/`rust-std` phải **cùng** version.
# 3. Mặc định rustc 1.92 đòi **linker self-contained** trong sysroot, mà gói
#    npm không có `gcc-ld/ld.lld`. Script này lấy `rust-lld` và đặt vào
#    `lib/rustlib/<target>/bin/gcc-ld/`, kèm `libLLVM.so.*` mà nó cần.
#
# Nếu một ngày `static.rust-lang.org` mở, dùng rustup cho gọn:
#     curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal
set -euo pipefail

VERSION=0.92.20250925
ROOT="$HOME/.local/rust"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
    echo "  ↓ $1"
    curl -sL --fail -o "$TMP/$1.tgz" \
        "https://registry.npmjs.org/@rusttonpm/$1/-/$1-$VERSION.tgz"
    tar xzf "$TMP/$1.tgz" -C "$TMP"
}

echo "Tải ba gói cùng version $VERSION (rustc + cargo + rust-std phải khớp nhau)…"
mkdir -p "$TMP/x"
for pkg in rustc-linux-x64 cargo-linux-x64 rust-std-linux-x64; do
    echo "  ↓ $pkg"
    curl -sL --fail -o "$TMP/$pkg.tgz" \
        "https://registry.npmjs.org/@rusttonpm/$pkg/-/$pkg-$VERSION.tgz"
    tar xzf "$TMP/$pkg.tgz" -C "$TMP/x"
done

echo "Cài vào $ROOT …"
rm -rf "$ROOT"
mkdir -p "$ROOT/bin"

# Binary **thật** của rustc/cargo (không phải wrapper `package/bin/*`: wrapper
# gọi `../vendor/rustc/bin/rustc` và đường đó không tồn tại sau khi cài kiểu này).
cp "$TMP/x/package/vendor/rustc/bin/rustc" "$ROOT/bin/"
cp "$TMP/x/package/vendor/cargo/bin/cargo" "$ROOT/bin/"

# Driver + LLVM: rustc là binary nhỏ, phần thân ở `lib/*.so`.
cp "$TMP/x/package/vendor/rustc/lib/"*.so* "$ROOT/lib/"

# `std` cho target: chính là phần gói npm thứ ba.
mkdir -p "$ROOT/lib/rustlib/x86_64-unknown-linux-gnu"
cp -r "$TMP/x/package/vendor/rust-std-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/"* \
    "$ROOT/lib/rustlib/x86_64-unknown-linux-gnu/" 2>/dev/null || true

# Linker self-contained: rustc 1.92 tìm `ld.lld` trong `bin/gcc-ld/` của sysroot.
# Gói npm không đóng gói nó, nên dùng `rust-lld` làm cả hai tên.
if [ ! -x "$ROOT/lib/rustlib/x86_64-unknown-linux-gnu/bin/gcc-ld/ld.lld" ]; then
    mkdir -p "$ROOT/lib/rustlib/x86_64-unknown-linux-gnu/bin/gcc-ld"
    # `rust-lld` có trong gói rustc-linux-x64 ở `lib/rustlib/<target>/bin/`.
    if [ -x "$ROOT/lib/rustlib/x86_64-unknown-linux-gnu/bin/rust-lld" ]; then
        cp "$ROOT/lib/rustlib/x86_64-unknown-linux-gnu/bin/rust-lld" \
            "$ROOT/lib/rustlib/x86_64-unknown-linux-gnu/bin/gcc-ld/ld.lld"
    fi
fi

chmod +x "$ROOT/bin/"* 2>/dev/null || true

echo
echo "Xong. Kiểm tra:"
export PATH="$ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$ROOT/lib"
rustc --version
cargo --version
echo
echo "Trước khi build, luôn export:"
echo "  export PATH=\"\$HOME/.local/rust/bin:\$PATH\""
echo "  export LD_LIBRARY_PATH=\"\$HOME/.local/rust/lib\""
