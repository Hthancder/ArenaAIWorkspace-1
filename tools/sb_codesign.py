#!/usr/bin/env python3
"""sb_codesign.py — ký ad-hoc (SHA-256 CodeDirectory) cho Mach-O arm64, thuần Python.

Vì sao cần: tweak inject vào process hệ thống nên iOS cần ít nhất một chữ ký
ad-hoc hợp lệ (LC_CODE_SIGNATURE). Toolchain zig trên Linux không ký, và `ldid`
không có sẵn trong CI → trước đây binary ra **không có chữ ký**.

Cách dùng:
    python3 tools/sb_codesign.py <file.dylib> [file2 ...]

Yêu cầu: binary còn headerpad ≥ 0x200 byte giữa load commands và section đầu
(build với -Wl,-headerpad,0x1000 trong tools/zigcc-wrap.sh + Makefile).
"""
import hashlib
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1D

CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSSLOT_CODEDIRECTORY = 0

CS_ADHOC = 0x2
CD_HASHTYPE_SHA256 = 2
PAGE = 4096
LOG2_PAGE = 12

# CodeDirectory version 0x20100: 44 byte header
# version 0x20100: header = 9*u32 + 4*u8 + spare2 + scatterOffset = 48 byte
CD_VERSION = 0x20100
CD_HEADER_LEN = 48


class MachO:
    def __init__(self, path):
        self.path = path
        with open(path, "rb") as fh:
            self.data = bytearray(fh.read())
        d = self.data
        (magic, self.cputype, self.cpusubtype, self.filetype,
         self.ncmds, self.sizeofcmds, self.flags) = struct.unpack("<IIIIIII", d[:28])
        if magic != MH_MAGIC_64:
            raise SystemExit(f"{path}: không phải Mach-O 64 (magic {magic:#x})")
        self.cmds = []
        off = 32
        for _ in range(self.ncmds):
            cmd, size = struct.unpack("<II", d[off:off + 8])
            self.cmds.append((cmd, off, size))
            off += size
        self.lc_end = 32 + self.sizeofcmds

    def _segments(self):
        for cmd, off, size in self.cmds:
            if cmd != LC_SEGMENT_64:
                continue
            name = bytes(self.data[off + 8:off + 24]).rstrip(b"\0").decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack("<QQQQ", self.data[off + 24:off + 56])
            yield name, dict(cmd_off=off, vmaddr=vmaddr, vmsize=vmsize,
                             fileoff=fileoff, filesize=filesize)

    def segment(self, want):
        for name, info in self._segments():
            if name == want:
                return info
        return None

    def first_section_offset(self):
        for name, info in self._segments():
            if name != "__TEXT":
                continue
            off = info["cmd_off"]
            nsects = struct.unpack("<I", self.data[off + 64:off + 68])[0]
            if nsects == 0:
                continue
            sect = off + 72   # section_64 của section đầu tiên
            addr = struct.unpack("<Q", self.data[sect + 32:sect + 40])[0]
            fileoff = struct.unpack("<I", self.data[sect + 48:sect + 52])[0]
            return addr, fileoff
        return None

    def already_signed(self):
        for cmd, off, _size in self.cmds:
            if cmd == LC_CODE_SIGNATURE:
                dataoff, datasize = struct.unpack("<II", self.data[off + 8:off + 16])
                return dataoff, datasize
        return None


def build_code_directory(ident: bytes, page_hashes, code_limit: int) -> bytes:
    n_code = len(page_hashes)
    ident_offset = CD_HEADER_LEN
    hash_offset = ident_offset + len(ident) + 1
    length = hash_offset + n_code * 32

    header = struct.pack(
        ">IIIIIIIIIBBBBII",
        CSMAGIC_CODEDIRECTORY,   # magic
        length,                   # length
        CD_VERSION,               # version
        CS_ADHOC,                 # flags
        hash_offset,              # hashOffset
        ident_offset,             # identOffset
        0,                        # nSpecialSlots
        n_code,                   # nCodeSlots
        code_limit,               # codeLimit (u32 ở version 0x20100)
        32,                       # hashSize
        CD_HASHTYPE_SHA256,       # hashType
        0,                        # platform
        LOG2_PAGE,                # pageSize
        0,                        # spare2
        0,                        # scatterOffset (v0x20100)
    )
    assert len(header) == CD_HEADER_LEN, (len(header), CD_HEADER_LEN)
    return header + ident + b"\0" + b"".join(page_hashes)


# SuperBlob: header 12 byte + mỗi BlobIndex 8 byte (type u32, offset u32 tính
# từ đầu SuperBlob). Với 1 slot: CD bắt đầu ở 12 + 8 = 20.
SUPERBLOB_HEADER = 12
BLOBINDEX_SIZE = 8
CD_OFFSET = SUPERBLOB_HEADER + BLOBINDEX_SIZE   # = 20


def build_superblob(cd: bytes) -> bytes:
    index = struct.pack(">II", CSSLOT_CODEDIRECTORY, CD_OFFSET)
    body = index + cd
    header = struct.pack(">III", CSMAGIC_EMBEDDED_SIGNATURE,
                         SUPERBLOB_HEADER + len(body), 1)
    return header + body


def sign(path: str) -> None:
    m = MachO(path)
    existing = m.already_signed()
    if existing:
        print(f"{path}: đã có LC_CODE_SIGNATURE ({existing[1]} byte), bỏ qua")
        return

    sect = m.first_section_offset()
    if sect is None:
        raise SystemExit(f"{path}: không tìm được section đầu tiên của __TEXT")
    sect_addr, sect_fileoff = sect

    slack = sect_addr - m.lc_end
    if slack < 0x200:
        raise SystemExit(f"{path}: headerpad chỉ còn {slack:#x} — cần ≥ 0x200 "
                         f"(build với -Wl,-headerpad,0x1000)")

    # Vùng được ký = toàn bộ file hiện tại (đã đệm 0 cho tròn 16 byte),
    # chữ ký nằm ngay sau đó.
    sig_off = (len(m.data) + 15) & ~15
    code_limit = sig_off
    n_code = (code_limit + PAGE - 1) // PAGE
    ident = path.rsplit("/", 1)[-1].encode()

    cd_estimate = CD_HEADER_LEN + len(ident) + 1 + n_code * 32
    datasize = CD_OFFSET + cd_estimate

    # ---- 1. Đệm file + cập nhật header TRƯỚC khi hash ----
    # Mọi byte trong [0, code_limit) đều được hash, kể cả load command và
    # header của __LINKEDIT, nên phải ghi xong xuôi rồi mới tính hash.
    d = m.data
    if len(d) < sig_off:
        d.extend(b"\0" * (sig_off - len(d)))

    cmd_off = m.lc_end
    d[cmd_off:cmd_off + 16] = struct.pack("<IIII", LC_CODE_SIGNATURE, 16, sig_off, datasize)
    struct.pack_into("<I", d, 16, m.ncmds + 1)
    struct.pack_into("<I", d, 20, m.sizeofcmds + 16)

    # __LINKEDIT phải bao trùm cả chữ ký (độ dài cuối cùng đã biết trước)
    linkedit = m.segment("__LINKEDIT")
    if linkedit:
        total = sig_off + datasize
        filesize = total - linkedit["fileoff"]
        vmsize = (filesize + PAGE - 1) // PAGE * PAGE
        struct.pack_into("<Q", d, linkedit["cmd_off"] + 48, vmsize)
        struct.pack_into("<Q", d, linkedit["cmd_off"] + 56, filesize)

    # ---- 2. Hash từng trang của [0, code_limit) ----
    page_hashes = []
    for off in range(0, code_limit, PAGE):
        page_hashes.append(hashlib.sha256(bytes(d[off:min(off + PAGE, code_limit)])).digest())

    # ---- 3. CodeDirectory + SuperBlob ----
    cd = build_code_directory(ident, page_hashes, code_limit)
    assert len(cd) == cd_estimate, (len(cd), cd_estimate)
    blob = build_superblob(cd)
    assert len(blob) == datasize, (len(blob), datasize)

    # ---- 4. Nối chữ ký vào cuối file ----
    d.extend(blob)
    if len(d) % 16:
        d.extend(b"\0" * (16 - len(d) % 16))

    with open(path, "wb") as fh:
        fh.write(d)
    print(f"{path}: đã ký ad-hoc ({datasize} byte, {n_code} trang, codeLimit {code_limit:#x})")


def main() -> None:
    files = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not files:
        raise SystemExit("dùng: sb_codesign.py <file.dylib> [more...]")
    for f in files:
        try:
            sign(f)
        except SystemExit:
            raise
        except Exception as e:      # noqa: BLE001
            raise SystemExit(f"{f}: ký lỗi — {e}")


if __name__ == "__main__":
    main()
