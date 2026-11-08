#!/usr/bin/env python3
"""Biên dịch nhánh `#[cfg(windows)]` **trên Linux**.

Vì sao cần: `#![cfg(windows)]` từng làm cả `capture.rs` biến mất khỏi build
Linux, nên mọi lỗi kiểu dữ liệu và mọi dead-code của nhánh Windows chỉ hiện
trong CI Windows (4–6 phút/vòng). Cách này lật `#[cfg(windows)]` thành bật,
`#[cfg(not(windows))]` thành tắt, rồi chạy `cargo check -D warnings` — cùng
lúc bắt lỗi kiểu, `unused_mut` và `dead_code` của nhánh Windows.

Không thay thế build Windows thật (link, ABI, chạy thật); chỉ là vòng lặp
phản hồi nhanh. Bản Windows vẫn là bước cuối trong CI.
"""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "app" / "src"
WEB = ROOT / "web"


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = pathlib.Path(tmp)
        shutil.copytree(ROOT / "app", tmp_path / "app", dirs_exist_ok=True)
        # `app` có path dependency `../spike` (dùng lại thư viện luật của spec
        # thay vì chép — §57.1). Chỉ copy `app` thì cargo không resolve được
        # `rd-spike` và script báo "không biên dịch sạch" trong khi code sạch:
        # đó là script sai, không phải code sai.
        shutil.copytree(
            ROOT / "spike",
            tmp_path / "spike",
            dirs_exist_ok=True,
            ignore=shutil.ignore_patterns("target"),
        )
        shutil.copytree(WEB, tmp_path / "web", dirs_exist_ok=True)
        for path in (tmp_path / "app" / "src").glob("*.rs"):
            text = path.read_text()
            # Giữ `#[cfg(unix)]` nguyên: bỏ nó đi thì hai hàm `os_random`
            # (unix + windows) cùng tồn tại và báo E0428 — script tự tạo ra
            # lỗi của chính nó. Chỉ bỏ `#[cfg(windows)]`, phần còn lại vẫn
            # được biên dịch đúng một lần.
            # Nhánh unix phải **tắt**, không phải giữ: trên Linux `cfg(unix)`
            # đúng, nên giữ lại thì `os_random` được định nghĩa hai lần (unix
            # + windows) và script tự tạo ra E0428. Script này mô phỏng *hình
            # dạng* code Windows, nên chỉ nhánh Windows được sống.
            text = re.sub(r"#\[cfg\(unix\)\]", "#[cfg(any())]", text)
            text = text.replace("#[cfg(windows)]", "")
            text = re.sub(r"#\[cfg\(not\(windows\)\)\]", "#[cfg(any())]", text)
            text = text.replace("#![cfg_attr(not(windows), allow(dead_code))]", "")
            # Mọi `#[link(name = ...)]` đều phải bỏ: trên Linux không có
            # `kernel32`/`advapi32`, và mục đích của script này là kiểm **hình
            # dạng** code Windows (dead_code, unused_mut), không phải link.
            # Bản đầu chỉ xoá `kernel32` nên `advapi32` (thêm cùng `RealEntropy`
            # trong `auth_wire.rs`) làm script báo đỏ trong khi code đúng.
            text = re.sub(r'#\[link\(\s*name\s*=\s*"[^"]+"\s*\)\]', "", text)
            path.write_text(text)
        result = subprocess.run(
            ["cargo", "check", "--offline", "--all-targets"],
            cwd=tmp_path / "app",
            capture_output=True,
            text=True,
        )
        output = (result.stdout + result.stderr).strip()
        # Chỉ quan tâm dòng chẩn đoán; "Checking"/"Finished"/"generated N
        # warnings" là nhiễu tổng kết.
        lines = [
            line
            for line in output.splitlines()
            if line.startswith(("warning:", "error:")) and "generated" not in line
            or line.strip().startswith("--> ")
        ]
        if lines or result.returncode != 0:
            print("\n".join(lines[:60]))
            print("\n✗ nhánh Windows không biên dịch sạch trên Linux", file=sys.stderr)
            return 1
        print("ok — nhánh #[cfg(windows)] biên dịch sạch (dead_code, unused_mut, kiểu dữ liệu)")
        return 0


if __name__ == "__main__":
    sys.exit(main())
