#!/bin/sh
# Kiểm JPEG encoder bằng **bộ giải mã độc lập** (ImageMagick), không phải bằng
# chính code Rust đã sinh ra nó.
#
# Vì sao cần: test tự viết chỉ kiểm những gì tôi nghĩ ra để kiểm. Lỗi thật đầu
# tiên của encoder này — thiếu bảng lượng tử số 1 — đi qua **toàn bộ** test Rust
# mà ImageMagick bắt được ngay ở lần đầu.
#
#   ./scripts/check-jpeg.sh
#
# Bỏ qua (mã 0) nếu máy không có ImageMagick: đây là kiểm thêm, không phải cổng
# bắt buộc cho CI.
set -eu
cd "$(dirname "$0")/.."

if ! command -v identify >/dev/null 2>&1; then
    echo "   ImageMagick không có -> bỏ qua kiểm JPEG ngoài"
    exit 0
fi

export PATH="${HOME}/.local/rust/bin:${PATH}"
fail=0

for spec in "64 48 70" "127 93 40" "320 200 75" "641 361 90" "1 1 50"; do
    set -- $spec
    width=$1; height=$2; quality=$3
    rm -f /tmp/out.jpg
    if ! LANTERN_DUMP="$width $height $quality" \
        cargo test --quiet --offline --manifest-path app/Cargo.toml write_sample -- --ignored >/dev/null 2>&1; then
        echo "   ${width}x${height}: KHÔNG sinh được file"
        fail=1
        continue
    fi
    if identify /tmp/out.jpg >/dev/null 2>&1; then
        actual=$(identify -format "%wx%h" /tmp/out.jpg)
        if [ "$actual" = "${width}x${height}" ]; then
            size=$(wc -c < /tmp/out.jpg)
            echo "   ok: ${width}x${height} q${quality} -> ${size} byte"
        else
            echo "   SAI KÍCH THƯỚC: ${width}x${height} -> ${actual}"
            fail=1
        fi
    else
        echo "   KHÔNG ĐỌC ĐƯỢC: ${width}x${height} q${quality}"
        identify /tmp/out.jpg 2>&1 | head -2
        fail=1
    fi
done

[ "$fail" = "0" ] && echo "   JPEG đọc được bằng bộ giải mã độc lập ở mọi kích thước"
exit "$fail"
