#!/usr/bin/env python3
"""Kiểm tra .deb của SiriBridge: Mach-O phải là arm64 (KHÔNG arm64e), không có layout rootful.

Dùng: python3 tools/verify_deb.py <file.deb> <package_arch_mong_doi>
"""
import os
import struct
import subprocess
import sys
import tempfile

CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_MASK = 0x00FFFFFF   # bỏ bit capability (arm64e = 0x80000002)
MACHO_64_LE = 0xFEEDFACF


def fail(msg: str) -> None:
    print(f"LỖI: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if len(sys.argv) != 3:
        fail("cần 2 tham số: <file.deb> <package_arch>")
    deb, expected_arch = sys.argv[1], sys.argv[2]

    # --- 1. Trường Architecture trong control ---
    control = subprocess.run(["dpkg-deb", "-f", deb], capture_output=True, text=True, check=True).stdout
    arch = None
    for line in control.splitlines():
        if line.lower().startswith("architecture:"):
            arch = line.split(":", 1)[1].strip()
    if arch != expected_arch:
        fail(f"Architecture='{arch}', cần '{expected_arch}'")
    print(f"OK control Architecture = {arch}")

    # --- 2. Bung gói, kiểm tra layout ---
    tmp = tempfile.mkdtemp(prefix="sbverify-")
    subprocess.run(["dpkg-deb", "-x", deb, tmp], check=True)

    # rootless cài dưới var/jb/…, roothide cài ở gốc gói — tìm theo tên
    def find(rel_tail: str) -> str:
        for base, _dirs, files in os.walk(tmp):
            for name in files:
                path = os.path.join(base, name)
                if path.replace(tmp, "").lstrip("/").endswith(rel_tail):
                    return path
        return ""

    dylib = find("Library/MobileSubstrate/DynamicLibraries/SiriBridge.dylib")
    if not dylib:
        fail("thiếu Library/MobileSubstrate/DynamicLibraries/SiriBridge.dylib")
    prefs = find("Library/PreferenceBundles/SiriBridgePrefs.bundle/SiriBridgePrefs")
    if not prefs:
        fail("thiếu SiriBridgePrefs bundle")
    loader = find("Library/PreferenceLoader/Preferences/SiriBridge.plist")
    if not loader:
        fail("thiếu PreferenceLoader entry → sẽ không hiện trong Settings")

    rel = os.path.relpath(dylib, tmp)
    print(f"OK layout: {rel}")
    if "var/jb/" in rel and expected_arch == "iphoneos-arm64e":
        print("CẢNH BÁO: gói roothide lại dùng layout /var/jb", file=sys.stderr)
    if "var/jb/" not in rel and expected_arch == "iphoneos-arm64":
        fail("gói rootless phải cài vào /var/jb")

    # --- 3. Mach-O: arm64 thuần ---
    for path in (dylib, prefs):
        with open(path, "rb") as fh:
            head = fh.read(16)
        magic = struct.unpack("<I", head[0:4])[0]
        cpu, subtype = struct.unpack("<II", head[4:12])
        if magic != MACHO_64_LE:
            fail(f"{os.path.basename(path)} không phải Mach-O 64 little-endian ({magic:#x})")
        if cpu != CPU_TYPE_ARM64:
            fail(f"{os.path.basename(path)} cputype={cpu:#x}, cần arm64")
        base_subtype = subtype & CPU_SUBTYPE_MASK
        if base_subtype != 0:
            fail(f"{os.path.basename(path)} cpusubtype={subtype:#x} → không phải arm64 ALL")
        print(f"OK {os.path.basename(path)}: Mach-O arm64, cpusubtype={subtype:#x} (ALL, không arm64e)")

    size = os.path.getsize(deb)
    if size < 20000:
        fail(f"gói quá nhỏ ({size} B) — có thể thiếu binary")
    print(f"OK kích thước gói: {size} B")
    print("TẤT CẢ KIỂM TRA ĐỀU ĐẠT")


if __name__ == "__main__":
    main()
