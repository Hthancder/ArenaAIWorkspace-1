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
# Và `~/.local` không được snapshot, nên toolchain mất sau mỗi phiên. Script này
# dựng lại từ gói npm.
#
# # Vì sao **hai** toolchain
#
# CI (`dtolnay/rust-toolchain@stable`) dùng một bản **stable mới**, còn bản mới
# nhất đóng trên npm là 1.99. Lint thay đổi theo version:
#
# * clippy 1.92 (npm cũ) **không** báo `while_let_loop` ở `upload.rs`, CI báo ⇒
#   push xong mới biết, sửa rồi push lại — một vòng lặp tốn thời gian.
# * clippy **0.1.99** báo đúng lỗi đó (đã kiểm bằng cách tái tạo lỗi).
#
# Nên: dùng **1.99** cho `cargo clippy` (gần CI nhất), và 1.92 làm bản dự phòng
# nếu 1.99 vướng.
#
# # Cách dùng
#
#     ./scripts/install-rust.sh
#     export PATH="$HOME/.local/rust/bin:$PATH"          # 1.99: build + clippy
#     export LD_LIBRARY_PATH="$HOME/.local/rust/lib"
#     cargo test --manifest-path app/Cargo.toml
#
# # Bốn cái bẫy đã gặp (mỗi cái tốn một vòng)
#
# 1. Gói `rustc` **chỉ có driver**, thiếu `rust-std` ⇒ `can't find crate for 'std'`.
# 2. Ba gói (rustc/cargo/rust-std) phải **cùng** version.
# 3. rustc đòi **linker self-contained** trong sysroot, gói npm không có
#    `gcc-ld/ld.lld` ⇒ phải chép `rust-lld` (có trong gói rustc) vào đó, kèm
#    `libLLVM.so.*` mà nó cần.
# 4. `package/bin/rustc` là **wrapper** gọi `../vendor/rustc/bin/rustc`; cài kiểu
#    này không có `vendor/` nên wrapper chết. Dùng binary **thật** ở
#    `package/rustc/bin/rustc`.
set -euo pipefail

# Mặc định trong **repo** (`.toolchain/`), không phải `~/.local`.
#
# Lý do: `~/.local` là thư mục **không** được snapshot, và trong sandbox nó còn
# bị xoá **giữa các lệnh bash** — toolchain dựng xong biến mất trước lệnh tiếp
# theo. `.toolchain/` nằm trong workspace, đã có trong `.gitignore`, nên sống
# qua các lệnh (và qua các turn nếu snapshot giữ nó).
ROOT="${RD_RUST_ROOT:-$PWD/rust-toolchain}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/x"

fetch() { # $1 = tên gói (@scope/name), $2 = tên file .tgz, $3 = thư mục đích
    # URL npm cho package có scope: `@scope%2Fname`. `@` phải để **nguyên** —
    # encode thành `%40` thì registry trả 404 (đã kiểm: `%40…` 404, `@…%2F…` 200).
    local encoded
    encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe='@'))" "$1")
    echo "  ↓ $1"
    curl -sL --fail -o "$TMP/pkg.tgz" "https://registry.npmjs.org/$encoded/-/$2"
    # **Mỗi gói một thư mục riêng.** Giải nén cả bốn gói vào cùng một chỗ thì
    # gói sau ghi đè `package/rustc/` của gói trước, và `std` biến mất —
    # không có lỗi nào, chỉ là `can't find crate for 'std'`.
    mkdir -p "$3"
    tar xzf "$TMP/pkg.tgz" -C "$3"
}

install_one() { # $1 = version rustc, $2.. = gói npm
    local rustc_version="$1"; shift
    echo "Dựng toolchain $rustc_version …"
    # Dọn **chỉ** các thư mục giải nén của lần trước, không đụng `pkg.tgz`.
    rm -rf "$TMP"/x[0-9]* "$TMP/pkg.tgz"
    # Mỗi tham số dạng "@scope/name|tên-file.tgz".
    local index=0
    for pkg in "$@"; do
        index=$((index + 1))
        fetch "${pkg%%|*}" "${pkg##*|}" "$TMP/x$index"
    done

    rm -rf "$ROOT"; mkdir -p "$ROOT/bin" "$ROOT/lib/rustlib/x86_64-unknown-linux-gnu"

    # Binary **thật**, không phải wrapper `package/bin/*` (xem bẫy 4).
    find "$TMP/x"*/package"" -path "*/rustc/bin/rustc" -exec cp {} "$ROOT/bin/" \;
    find "$TMP/x"*/package"" -path "*/cargo/bin/cargo" -exec cp {} "$ROOT/bin/" \;
    find "$TMP/x"*/package"" -path "*/clippy-preview/bin/*" -exec cp {} "$ROOT/bin/" \;
    cp "$TMP/x"*/package"/rustc/lib/"*.so* "$ROOT/lib/" 2>/dev/null || true

    # `std` cho target (bẫy 1 + 2).
    local std_dir
    std_dir=$(find "$TMP/x"*/package"" -maxdepth 1 -name "rust-std-*" | head -1)
    if [ -n "$std_dir" ]; then
        cp -r "$std_dir/lib/rustlib/x86_64-unknown-linux-gnu/"* \
            "$ROOT/lib/rustlib/x86_64-unknown-linux-gnu/"
    fi

    # Linker self-contained (bẫy 3).
    local target_bin="$ROOT/lib/rustlib/x86_64-unknown-linux-gnu/bin"
    local src_lld="$TMP/x"*/package"/rustc/lib/rustlib/x86_64-unknown-linux-gnu/bin/rust-lld"
    if [ -x "$src_lld" ]; then
        mkdir -p "$target_bin/gcc-ld"
        cp "$src_lld" "$target_bin/rust-lld"
        cp "$src_lld" "$target_bin/gcc-ld/ld.lld"
        cp "$src_lld" "$target_bin/gcc-ld/lld"
    fi
    chmod +x "$ROOT/bin/"* 2>/dev/null || true
}

# 1.99 = bản mới nhất trên npm; clippy 0.1.99 đã kiểm là bắt đúng lint mà CI
# stable báo (`while_let_loop`) và bản 1.92 bỏ sót.
install_one 1.99.0 \
    "@toolchain-bin/rustc-1.99.0-x86_64-unknown-linux-gnu|rustc-1.99.0-x86_64-unknown-linux-gnu-1.99.0.tgz" \
    "@toolchain-bin/cargo-1.99.0-x86_64-unknown-linux-gnu|cargo-1.99.0-x86_64-unknown-linux-gnu-0.100.0.tgz" \
    "@toolchain-bin/clippy-1.99.0-x86_64-unknown-linux-gnu|clippy-1.99.0-x86_64-unknown-linux-gnu-0.1.99.tgz" \
    "@toolchain-bin/rust-std-1.99.0-x86_64-unknown-linux-gnu|rust-std-1.99.0-x86_64-unknown-linux-gnu-1.99.0-1.tgz"

echo
echo "Xong. Kiểm tra:"
export PATH="$ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$ROOT/lib"
rustc --version
cargo --version
clippy-driver --version
echo
echo "Trước khi build, luôn export:"
echo "  export PATH=\"$ROOT/bin:\$PATH\""
echo "  export LD_LIBRARY_PATH=\"$ROOT/lib\""
echo "  export RUSTFLAGS=\"-C link-self-contained=no -C link-arg=-fuse-ld=bfd\""
echo
echo "RUSTFLAGS là bắt buộc: gói npm 1.99 không kèm linker self-contained, và"
echo "sandbox không có \`ld.lld\` — nó có \`ld.bfd\`. Thiếu RUSTFLAGS thì mọi build"
echo "chết ở khâu link với \"self-contained linker was requested\"."
echo
echo "LƯU Ý: \"$ROOT\" bị dọn giữa các lệnh bash trong sandbox này (chỉ file"
echo "tracked trong git sống sót). Nên chạy install + build trong **một** lệnh:" 
echo "  ./scripts/install-rust.sh && export ... && cargo test"
