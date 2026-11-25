# 0.5.0-preview.8 — Sửa mất setting khi reload

Ngày: 2026-11-12  
Phạm vi: menu/config persistence. **Chưa xác nhận trên live reload của người dùng; đây không phải bypass storage của browser.**

## Triệu chứng

ESP/native names hoặc setting khác vừa bật không giữ sau reload; người dùng phải bật lại.

## Nguyên nhân tìm được

Config cũ được ghi vào `localStorage` qua debounce 200 ms (`storageTimer`). Nếu page bị reload/ẩn trước khi timer chạy, write chưa diễn ra. Các handler `pagehide`/cleanup có gọi ghi, nhưng write phụ thuộc thứ tự unload và không có fallback báo rõ nếu `localStorage` bị browser/site chặn.

Các phần normalize/load `esp` (boolean) và key `duality-reborn.config.v1` đã được kiểm tra: `esp=true` round-trip qua `normalizeConfig(JSON.parse(...))` giữ nguyên.

## Sửa

- Mỗi `set()`/reset ghi **đồng bộ** vào `localStorage`; không còn chờ 200 ms.
- Flush config khi `beforeunload`, `pagehide`, blur và khi document chuyển hidden.
- `dispose()` dùng cùng flush helper.
- Nếu browser/site chặn `localStorage`, warning hiện trên console (`[Duality Reborn] localStorage write failed:`) và status menu nói cấu hình chỉ dùng trong bộ nhớ; script không fake-persist bằng cookie/telemetry.

## Test

- Existing menu/ESP tests vẫn pass.
- Test ESP filter xác nhận file storage đã cập nhật **ngay sau click**, không cần chờ timer.
- Dispatch `pagehide` và `loadConfig()` xác nhận cấu hình được nhận lại.
- `npm run check`: **149/149 PASS**; upstream source checks: **4/4 PASS**.

## Giới hạn

Nếu trình duyệt chặn `localStorage` cho survev.io/site policy/container, không có cách lưu bền vững từ trang mà không dùng cookie/IndexedDB/extension storage riêng. Bản này vẫn fail rõ ràng; cần cho phép storage của site hoặc dùng profile/browser cho phép lưu userscript.
