# 33 — Lưu trữ & định dạng project (local-first)

> App không có backend → **toàn bộ dữ liệu người dùng nằm ở máy họ**. Nếu lưu sai, người dùng mất bài đã ghi. File này chốt: lưu ở đâu, định dạng nào, và cách không mất dữ liệu.

## 33.1. Bản đồ lưu trữ (2026)

| Công nghệ | Dung lượng | Ưu | Nhược | Dùng cho |
|---|---|---|---|---|
| **localStorage** | ~5–10 MB | Đơn giản, đồng bộ | Chặn main thread, chỉ string | Settings nhỏ |
| **IndexedDB** | Chrome ~60% đĩa, Firefox 10% (50% nếu `persist()`), **Safari ~1 GB/origin** | Blob/ArrayBuffer, transaction, index | API thô, cần versioning cẩn thận | Takes, sessions, autosave |
| **OPFS** | Chung pool với IDB | File thật, ghi streaming, sync handle trong worker | Safari chỉ có `createWritable` từ **26 (9/2025)** | Project lớn, audio |
| **Cache Storage** | Chung pool | Đơn giản cho response | Chỉ cho Request/Response | Sample, app shell |
| **File System Access** | Đĩa thật | File `.nfz` thật, người dùng thấy | Chrome/Edge; **không có Safari/Firefox** | Export/import, "Save as" |
| **File System (tải file)** | Đĩa thật | 100% trình duyệt | Không ghi đè được, phải chọn lại | Fallback export |

### Điểm chí tử: **Safari xoá toàn bộ storage sau 7 ngày không tương tác** (ITP)
- Áp dụng cho **mọi storage do script ghi** (IDB, OPFS, Cache) trừ khi site được "Add to Home Screen".
- → **Không bao giờ** hứa "dữ liệu của bạn an toàn trong trình duyệt". Luôn nhắc **xuất `.nfz`**.
- → Hiển thị "lần lưu cuối" + cảnh báo nếu > 3 ngày.
- `navigator.storage.persist()`: Chrome/Firefox hỏi hoặc tự cấp; Safari chỉ chắc chắn khi đã cài PWA. Gọi **ngay sau lần tương tác đầu tiên có ý nghĩa** (mở file / ghi âm).

## 33.2. Định dạng project `.nfz` — đặc tả v1

```
project.nfz  (zip, không nén audio/video đã nén)
├── manifest.json
├── song.mid                 # MIDI gốc hoặc MIDI đã sửa (nguồn sự thật)
├── assets/
│   ├── background.png|mp4   # tùy chọn
│   └── sheet.pdf            # tùy chọn
├── takes/
│   └── take-001.mid         # bản ghi của người dùng
├── sessions/
│   └── 2026-11-14.json      # log luyện tập
└── thumbnail.jpg            # ảnh xem trước (tùy chọn)
```

**`manifest.json` v1:**
```json
{
  "format": "nfz",
  "formatVersion": 1,
  "app": "piano-app",
  "appVersion": "1.0.0",
  "createdAt": "2026-11-14T10:00:00Z",
  "updatedAt": "2026-11-14T10:42:11Z",
  "title": "Fur Elise",
  "composer": "",
  "songFile": "song.mid",
  "durationSec": 183.4,
  "trackCount": 2,
  "settings": { "...": "chỉ các key khác default" },
  "keyframes": [ { "t": 0, "speed": 1.0, "zoom": 1.0 } ],
  "assets": [ { "file": "assets/background.png", "type": "image/png", "bytes": 81234 } ],
  "takes": [ { "file": "takes/take-001.mid", "createdAt": "...", "notes": 145 } ],
  "generator": { "ua": "...", "gpu": "..." }
}
```

**Nguyên tắc:**
1. **MIDI là nguồn sự thật** cho nốt. Settings/keyframes chỉ là cách hiển thị → có thể đổi mà không hỏng nhạc.
2. `formatVersion` tăng khi đổi schema; **migration** chạy khi mở file cũ (xem 33.4).
3. Chỉ lưu **khác biệt so với default** trong `settings` → file nhỏ, dễ đọc, dễ migrate.
4. **Không** nén lại file media (zip `store` cho mp4/ogg/png) → mở nhanh.
5. **Không** dùng đường dẫn tuyệt đối; mọi thứ tương đối trong zip (chống path traversal — file 27).
6. Thumbnail tùy chọn ≤ 100 KB (chụp canvas ở 640×360).

## 33.3. Autosave & phục hồi

| Lớp | Cơ chế | Tần suất |
|---|---|---|
| Settings | `localStorage` (debounce 300 ms) | mỗi thay đổi |
| Trạng thái trình phát (bài đang mở, vị trí) | IDB, 1 record | mỗi 5 s |
| Take đang ghi | Buffer trong RAM → IDB khi dừng | khi dừng |
| Project | IDB (blob `.nfz` hoặc bản rời) | mỗi 30 s **nếu có thay đổi** |
| Bản "an toàn" | IDB, giữ 3 bản gần nhất | mỗi 5 phút |

**Phục hồi sau crash:** khi mở app, nếu có `unsavedSession` → hỏi "Khôi phục phiên trước? (Fur Elise, 10:42)". Không tự động mở (gây bất ngờ).

**Không dùng `beforeunload` để chặn** trừ khi thật cần — gây khó chịu; thay bằng autosave + banner.

## 33.4. Migration & tương thích

```
openProject(file):
  m = readManifest(file)
  if m.format !== 'nfz' → báo lỗi rõ
  if m.formatVersion > CURRENT → "File tạo bởi bản mới hơn (1.2). Hãy cập nhật app."
  while m.formatVersion < CURRENT: m = migrations[m.formatVersion](m)
  validate(m)  # schema
  load(m)
```

- Mỗi migration là **hàm thuần**: `v1 → v2`. Có test với file mẫu mỗi phiên bản (commit vào `test/fixtures/projects/`).
- **Không bao giờ** sửa file người dùng tại chỗ khi mở: luôn làm việc trên bản copy trong RAM/IDB.
- Khi lưu đè, tạo `.bak` (hoặc bản trong IDB) trước.

## 33.5. Chiến lược "không mất dữ liệu" (3 lớp)

1. **Autosave** trong IDB (nhanh, nhưng có thể bị Safari xoá).
2. **File `.nfz` trên đĩa** do người dùng chọn (bền nhất; nhắc mỗi 10 phút nếu chưa từng lưu).
3. **Nhắc định kỳ**: banner "Bạn chưa xuất bản sao lưu" + nút một chạm. Với Safari: thêm câu "Safari có thể xoá dữ liệu trang sau 7 ngày không dùng".

**Ngoài ra:** nút "Xuất tất cả" → zip toàn bộ project + takes + sessions (một file để backup).

## 33.6. Đồng bộ (nếu sau này muốn)

Không làm ở v1–v2. Nếu cần:
- **Không** tự làm server. Dùng thư mục đồng bộ của người dùng (iCloud Drive/OneDrive/Google Drive) qua File System Access hoặc "chọn thư mục" → app ghi `.nfz` vào đó.
- Xung đột: so `updatedAt` + `deviceId`; giữ cả hai bản, không tự merge.
- Tuyệt đối không ghi đè âm thầm.

## 33.7. Checklist lưu trữ

- [ ] `navigator.storage.persist()` gọi sau tương tác đầu tiên, hiện kết quả.
- [ ] `navigator.storage.estimate()` hiển thị "đã dùng X / còn Y" trong Settings.
- [ ] Xử lý `QuotaExceededError`: thông báo + đề nghị xuất file + dọn cache sample.
- [ ] Test: Safari Private Browsing (IDB bị chặn) → app vẫn chạy, cảnh báo rõ.
- [ ] Test: xoá site data → app khôi phục trạng thái "trống" không lỗi.
- [ ] Test: mở file `.nfz` của phiên bản cũ hơn → migrate đúng.
- [ ] Test: `.nfz` hỏng/thiếu `manifest.json` → báo lỗi, không treo.
- [ ] `.nfz` mở được bằng `unzip` thường (người dùng có thể cứu dữ liệu bằng tay).
