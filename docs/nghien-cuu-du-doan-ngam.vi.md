# Nghiên cứu dự đoán ngắm — chưa triển khai

Nguồn đối chiếu: Survev `08346fb6ea74c5a8b961a153d2d7d0411e31c8ff`, các định nghĩa súng/đạn và `server/src/game/weaponManager.ts`, `server/src/game/objects/player.ts`. Đây là phân tích mã nguồn, không phải xác minh trên trận đấu thực.

## Những giới hạn liên quan

- Máy chủ tính độ tản cho từng phát và từng viên; máy khách không biết trước các giá trị ngẫu nhiên. Recoil và độ tản không thể được dự đoán hoặc loại bỏ hoàn toàn bằng cách chỉnh hướng ngắm.
- Tốc độ di chuyển và thay đổi hướng phụ thuộc trạng thái, vật phẩm và các hiệu ứng. Người chơi có thể đổi hướng ngay; lịch sử vị trí không cho biết chính xác hành động trong tương lai.
- Hồ sơ súng hiện tại đọc tốc độ, tầm và thông số nòng từ định nghĩa được thu thập; có xử lý các hệ số perk đã xác định. Việc kiểm toán đầy đủ từng súng và điều kiện recoil vẫn chưa hoàn thành.

## Thử nghiệm chưa được áp dụng

Đã thử fit bậc hai có regularization trên tối đa sáu snapshot, sau đó ngoại suy gia tốc. Lỗi tính hệ số chặn ban đầu làm vị trí fit bị nhân với tổng trọng số; đã xác định được nguyên nhân và sửa trong thử nghiệm. Tuy nhiên kết quả sau khi sửa vẫn không đủ tốt để đưa vào userscript.

So sánh benchmark tổng hợp `node scripts/benchmark-aim.mjs` với bản trước thử nghiệm, cùng bộ seed và điều kiện mô phỏng, đơn vị world unit (wu):

| Chuyển động | Phiên bản | Trung vị sai lệch | Sai lệch p95 |
|---|---|---:|---:|
| Thẳng | Bản hiện hành | 0.388 | 3.139 |
| Thẳng | Fit bậc hai, có bất định gia tốc | 6.461 | 15.767 |
| Đường cong | Bản hiện hành | 2.573 | 6.646 |
| Đường cong | Fit bậc hai, có bất định gia tốc | 3.099 | 9.527 |
| Đảo hướng | Bản hiện hành | 4.835 | 17.043 |
| Đảo hướng | Fit bậc hai, có bất định gia tốc | 3.331 | 11.653 |

Một biến thể bỏ hạng bất định gia tốc vẫn làm p95 chuyển động thẳng tăng tới 13.789 wu. Các trade-off này đặc biệt bất lợi cho yêu cầu bắn xa, nên bản gia tốc **không được áp dụng**; source và userscript vẫn dùng bộ dự đoán trước đó. Không coi benchmark là tỷ lệ bắn trúng trong game: nó không mô phỏng độ tản, va chạm đầy đủ hay kỹ năng người chơi.

Việc còn lại: nghiên cứu và thử mô hình giữ được độ chính xác chuyển động thẳng đồng thời xử lý đổi hướng tốt hơn; kiểm tra toàn bộ dữ liệu súng và recoil theo nguồn; bổ sung kiểm thử, benchmark theo từng nhóm súng và xác minh thực tế trước khi tuyên bố cải thiện.
