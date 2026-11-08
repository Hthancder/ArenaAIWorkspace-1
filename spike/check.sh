#!/bin/sh
# Exactly what .github/workflows/ci.yml does, minus the Windows job.
# Use this when Actions cannot run (see spec §56.8) or when you just want the
# answer in 3 seconds instead of 2 minutes.
#
#   ./spike/check.sh
#
# Needs cargo on PATH. Rust 1.95 from npm, if static.rust-lang.org is blocked:
#   npm install -g @rust-sandbox/rust-1-95-x86_64-linux
#   export PATH="$HOME/.local/rust/bin:$PATH"
set -eu
cd "$(dirname "$0")"

echo "== rustc/cargo"
cargo --version
rustc --version

echo "== build (-D warnings: a warning is a failure)"
RUSTFLAGS="-D warnings" cargo build --offline

echo "== clippy (skipped if the component is not installed)"
if cargo clippy --version >/dev/null 2>&1; then
    cargo clippy --offline --all-targets -- -D warnings
else
    echo "   clippy not installed -> skipped (CI runs it)"
fi

echo "== tests"
cargo test --offline

echo "== smoke-run"
cargo run --offline --quiet -- --demo >/dev/null
echo "   rd --demo exited 0"

echo "== app (lantern-mock: the .exe the user actually runs)"
RUSTFLAGS="-D warnings" cargo build --offline --manifest-path ../app/Cargo.toml
cargo test --offline --manifest-path ../app/Cargo.toml
../app/target/debug/lantern-mock --check
echo "   app tests + --check green"

echo "== web (zero-dep UI syntax + tests)"
if command -v node >/dev/null 2>&1; then
    node --check ../web/app.js
    ( cd ../ && npm test --silent )
else
    echo "   node not installed -> skipped"
fi

echo "== all green"
