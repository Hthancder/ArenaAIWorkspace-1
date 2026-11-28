# Aim: kiểm thử đa tình huống, không chỉ A–D

Phạm vi benchmark bot được mở rộng: ngoài đứng yên, chạy thẳng, A–D, dừng/chạy, zigzag, quay 90° và vòng cung, còn có mục tiêu tiến tới/lùi ra, đổi tốc độ, chuỗi đổi hướng không đều khác, đổi hướng không đều rồi chạy thẳng; người bắn cũng có thể chạy thẳng, đổi hướng, đi vòng, dừng/chạy hoặc zigzag. Khoảng cách ban đầu 6/12/35/70 wu; mỗi bên độc lập có/không boost và slowdown, 3 tốc độ đạn, các pha, jitter và backlog giả lập. Các loại không đại diện toàn bộ hành vi thực, và trường hợp tiến gần có thể đi xuyên người bắn vì mô hình **không có va chạm thân người**, đặc biệt khoảng cách nhỏ.

Lệnh `BOT_MODELS=current node scripts/benchmark-bot-duel.mjs --tick-collision`: 4.343.040 phát tương quan, 30/60/144 FPS giả lập, down/up 30/30, 80/80, 30/120 và 120/30 ms. Đây là tập phát triển đã xem, không phải đo live hay kiểm định độc lập. Không có spread, recoil, vật cản, va chạm người, client thật, gửi input thật, smoothing hay mô phỏng toàn bộ server. Score là chạm hình tròn mô phỏng hoặc fallback ngắm trực diện khi thiếu nghiệm, không bảo đảm đó là hướng chuột người dùng. Các nhóm có trọng số và tổ hợp khác nhau; không suy luận chênh lệch giữa các nhóm là hiệu quả do riêng tốc độ/FPS gây ra.

| Nhóm | Tỷ lệ chạm mô phỏng | Sai lệch ngoài bán kính trung bình (wu) |
|---|---:|---:|
| Tất cả | 54,1% | 1,145 |
| Mục tiêu đứng yên | 78,0% | 0,114 |
| Mục tiêu chạy thẳng | 75,8% | 0,162 |
| Mục tiêu tiến tới / lùi ra | 73,6% / 74,4% | 0,163 / 0,177 |
| Mục tiêu đổi tốc độ | 62,8% | 0,504 |
| Mục tiêu dừng/chạy | 37,1% | 1,869 |
| Mục tiêu quay 90° | 42,7% | 2,054 |
| Mục tiêu đi vòng | 55,4% | 0,662 |
| Mục tiêu zigzag | 38,5% | 1,944 |
| Mục tiêu không đều / không đều thay thế | 35,3% / 26,0% | 1,508 / 2,604 |
| Người bắn chạy thẳng / đi vòng | 51,6% / 37,2% | 1,080 / 1,390 |
| Người bắn dừng/chạy | 36,1% | 2,088 |

Trong cùng benchmark, nhóm khoảng cách ban đầu 6/12/35/70 có 68,2/62,0/47,5/38,7%; nhóm 30/60/144 FPS có 54,1/54,2/54,0%. Cỡ mẫu lớn không làm các phát trên cùng quỹ đạo trở nên độc lập. Không so những số tổng này với bản benchmark trước vì bộ tình huống và khoảng cách đã thay đổi.

## Thử cải tiến nhưng chưa bật

Thử giảm lead nếu lịch sử chứa nhiều lần đổi hướng gắt, 2–5 lần/900 ms, thay vì đặc cách A–D. Ở holdout quick đã được dùng và xem trong quá trình phát triển, ngưỡng 4 cải thiện nhóm không đều 39,9→43,1%, không đều thay thế 30,4→30,7%, tổng 59,9→60,2%. Tuy nhiên, ở quick tập phát triển khác, cùng ngưỡng làm thu hẹp rồi thoát giảm 60,5→57,0%, trong khi các nhóm không đều không cải thiện. Không đưa vào runtime. Đây là bộ dữ liệu tổng hợp giới hạn, không thể kết luận một phương pháp tối ưu cho mọi chuyển động hoặc dự đoán chính xác hành động chưa được gửi.

Chiếu vị trí người bắn theo input cũng chỉ là thử nghiệm: ở holdout quick có xu hướng cải thiện chạy thẳng nhưng đã thấy hồi quy khi người bắn A–D nhanh. Không bật theo trung bình tổng. Đánh giá controller Human-like dùng `scripts/benchmark-controller-motion.mjs`: có 30/60/144 FPS mô phỏng nhưng chỉ mô hình một chiều, không thể thay cho duel hay gameplay live. Tiếp tục ưu tiên cả nhiều tình huống lẫn an toàn input/Wallcheck, không chỉ tối ưu một mẫu.
