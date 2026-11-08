# Lantern web mock

Frontend tĩnh, không dependency, nối với `mock-server/` cùng origin. Có dashboard, window picker, HVNC/VNC mode, luồng start/stop session, settings T1/T2 và các toggle camera/audio/micro ở mức UI.

Chạy cả frontend + backend từ repo root: `npm run mock`. Mở `http://127.0.0.1:4173`.

**Giới hạn:** hình desktop/camera/audio/micro là minh hoạ; không có capture, streaming, điều khiển hệ điều hành, authentication hay kết nối thiết bị thật. Backend chỉ lưu cài đặt mock và trạng thái phiên mock.
