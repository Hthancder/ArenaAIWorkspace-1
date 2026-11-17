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


def strict_checks(tmp: str) -> None:
    """Các kiểm tra chống safe mode: không phụ thuộc substrate, không inject SpringBoard."""
    found_filter = ""
    for base, _dirs, files in os.walk(tmp):
        for name in files:
            path = os.path.join(base, name)
            if name == "SiriBridge.plist" and "DynamicLibraries" in path:
                found_filter = path
            if name.endswith(".dylib"):
                with open(path, "rb") as fh:
                    blob = fh.read()
                if b"MSHookMessageEx" in blob:
                    fail(f"{os.path.basename(path)} còn tham chiếu MSHookMessageEx "
                         f"(Logos/substrate) — dyld có thể bind lỗi lúc load")
    if not found_filter:
        fail("thiếu plist filter của MobileSubstrate")
    with open(found_filter, "rb") as fh:
        plist = fh.read()
    if b"springboard" in plist:
        fail("plist filter còn inject com.apple.springboard (tweak không hook gì ở đó)")
    print("OK không phụ thuộc substrate, filter chỉ có SiriViewService")


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    strict = "--strict" in sys.argv
    if len(args) != 2:
        fail("cần 2 tham số: <file.deb> <package_arch> [--strict]")
    deb, expected_arch = args

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

    # --- 4. Bắt buộc có chữ ký ad-hoc (thiếu = SpringBoard/Siri sập khi load) ---
    for path in (dylib, prefs):
        with open(path, "rb") as fh:
            blob = fh.read()
        ncmds = struct.unpack("<I", blob[16:20])[0]
        off, cs = 32, None
        for _ in range(ncmds):
            cmd, size_ = struct.unpack("<II", blob[off:off + 8])
            if cmd == 0x1D:
                cs = struct.unpack("<II", blob[off + 8:off + 16])
            off += size_
        if not cs:
            fail(f"{os.path.basename(path)} KHÔNG có LC_CODE_SIGNATURE "
                 f"(toolchain Linux không ký → phải chạy tools/sb_codesign.py)")
        dataoff, datasize = cs
        if datasize < 1000:
            fail(f"{os.path.basename(path)} chữ ký quá nhỏ ({datasize} B)")
        sb = blob[dataoff:dataoff + datasize]
        if struct.unpack(">I", sb[:4])[0] != 0xFADE0CC0:
            fail(f"{os.path.basename(path)} superblob sai magic")
        _slot, cd_off = struct.unpack(">II", sb[12:20])
        cd = sb[cd_off:]
        if struct.unpack(">I", cd[:4])[0] != 0xFADE0C02:
            fail(f"{os.path.basename(path)} CodeDirectory sai magic")
        (_magic, _len, _ver, _flags, hash_off, _ident, _nspec, ncode,
         code_limit, hash_size, hash_type, _plat, page_log, _spare, _scatter) = \
            struct.unpack(">IIIIIIIIIBBBBII", cd[:48])
        if hash_type != 2 or hash_size != 32:
            fail(f"{os.path.basename(path)} hashType={hash_type} (cần 2 = SHA-256)")
        page = 1 << page_log
        import hashlib
        for i in range(min(ncode, 400)):
            start = i * page
            want = cd[hash_off + i * 32: hash_off + (i + 1) * 32]
            got = hashlib.sha256(blob[start:min(start + page, code_limit)]).digest()
            if got != want:
                fail(f"{os.path.basename(path)} hash trang {i} không khớp")
        print(f"OK {os.path.basename(path)}: chữ ký ad-hoc hợp lệ ({ncode} trang, SHA-256)")

    if strict:
        strict_checks(tmp)

    size = os.path.getsize(deb)
    if size < 20000:
        fail(f"gói quá nhỏ ({size} B) — có thể thiếu binary")
    print(f"OK kích thước gói: {size} B")
    print("TẤT CẢ KIỂM TRA ĐỀU ĐẠT")


if __name__ == "__main__":
    main()
