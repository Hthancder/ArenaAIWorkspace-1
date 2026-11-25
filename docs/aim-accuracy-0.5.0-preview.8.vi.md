# 0.5.0-preview.8 — Aim settings: chỉ thêm high-impact

Ngày: 2026-11-12  
Phạm vi: UX settings và aim-accuracy fallback. **Chưa live-hitrate test; không anti-detection, không bypass anti-cheat và không bảo đảm thắng wall/random spread.**

## Audit: những setting đang thật sự ảnh hưởng lớn

| Nhóm | Setting | Ảnh hưởng |
|---|---|---|
| Lock | `Human-like amount` + `Aim profile` | Đường đi camera/gun; ease-in/out, không overshoot. Chỉ hiện ở Lock. |
| Target | `FOV` + `Keep target` | Phạm vi acquisition và chống flip frame-to-frame. |
| Safety | `Wallcheck` | Không gửi aim correction xuyên tường; fail closed khi obstacle contract thiếu/quá budget. |
| Accuracy | `Predict Auto` + `Lead adjustment` + `Estimated latency` | Bắn vị trí tương lai theo snapshots/tốc độ đạn, không chỉ chase hiện tại. |
| Accuracy-first mới | `Strict prediction` | Nếu snapshot thiếu/stale/uncertain hoặc confidence < 0.85 / reduced lead, **không aim**; nhường native aim thay vì đoán liều. |

Các setting khác chỉ tùy biến visual/convenience và không ảnh hưởng hit chance theo cách đáng thêm.

## Setting mới

**Strict prediction** — chỉ hiện khi `Predict Auto` bật, mặc định **tắt** để giữ source fallback hiện tại:

- OFF (mặc định): nếu chưa có snapshot/prediction hoặc confidence thấp, script vẫn có thể dùng direct-current-position fallback như trước; shot hiển thị trạng thái `direct-awaiting-snapshot`, `direct-prediction-unavailable`, `reduced-lead-uncertainty` khi có.
- ON: các candidate `approximate`, `confidence < .85`, hoặc `uncertain` bị reject `predictionUncertain`; nếu không còn phương án tốt, aim state là `no-candidate` và mouse/native intent không bị kéo.
- Không tạo vị trí phát hiện thêm, không xuyên tường, không "ngoài range bullet"; chỉ bỏ qua giải không đủ tự tin.
- Không ảnh hưởng Assist strength, smooth profile, Fire, movement, equip, shotgun RNG.

## Cải tiến thuật toán đã nghiên cứu nhưng không ship

Quadratic position/acceleration prediction đã được thử trên held-out benchmark. Nó làm p95 xấu hơn đường tuyến tính hiện tại ở straight/diagonal/curve/speed-change/zigzag; kết luận là 2–6 snapshots không đủ để suy ra acceleration đáng tin và dễ overlead. Implementation này được revert hoàn toàn; không thêm setting "acceleration" vì benchmark nói không đáng.

## Không thêm

- Slider `Human-like` riêng cho Assist: Assist đã có **Assist strength**; tách thêm sẽ trùng chức năng.
- `Nearest`/`Crosshair` priority: mục tiêu crosshair là metric hiện tại và phù hợp Lock; nearest gây side-lock không mong muốn.
- Reaction delay, noise, "anti-detection": không hữu ích cho accuracy, không được giả mạo human và không bảo đảm safety.
- Prediction acceleration toggle: benchmark regression; complexity và overfit không đáng.
- Random pellet spread prediction: không thể biết seed/shot cụ thể, shotgun vẫn phải chấp nhận RNG.

## Kiểm chứng

- Source implementation + menu parent/visibility: `predictionStrict` chỉ hiện khi `Predict Auto` bật.
- Test mới: strict mode reject uncertain fallback (`aimRejections.predictionUncertain=1`, wire direction native), permissive mode giữ fallback gần hitbox.
- `npm run check`: **150/150 PASS**.
- Chưa có live gameplay validation; strict mode là trade-off: an toàn/không đoán liều hơn, nhưng Lock sẽ không nhấp aim khi snapshot chưa đủ tốt.
