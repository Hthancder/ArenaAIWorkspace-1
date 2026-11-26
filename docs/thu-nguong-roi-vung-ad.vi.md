# Thử phát hiện rời vùng A–D sớm hơn

## Ứng viên

Thử trong bản sao tạm `aim.mjs`, đổi riêng biên vượt vùng `margin` từ 0,06 xuống 0. Không thay source runtime hay userscript. Snapshot bên ngoài biên cũ sẽ bỏ midpoint ngay thay vì đợi vượt thêm 0,06. Đây là một ứng viên đơn giản, không dự đoán hướng tương lai.

Để tái hiện từ root repo:

```sh
mkdir -p .cache/aim-reaction-experiment
cp src/aim.mjs src/core.mjs .cache/aim-reaction-experiment/
python3 - <<'PY'
p = '.cache/aim-reaction-experiment/aim.mjs'
s = open(p).read()
assert s.count('const margin = .06;') == 1
open(p, 'w').write(s.replace('const margin = .06;', 'const margin = 0;'))
PY
node scripts/benchmark-aim-reaction.mjs
AIM_MODULE="file://$PWD/.cache/aim-reaction-experiment/aim.mjs" node scripts/benchmark-aim-reaction.mjs
node scripts/benchmark-midpoint-stability.mjs
AIM_MODULE="file://$PWD/.cache/aim-reaction-experiment/aim.mjs" node scripts/benchmark-midpoint-stability.mjs
node scripts/benchmark-micro-strafe.mjs --human
AIM_MODULE="file://$PWD/.cache/aim-reaction-experiment/aim.mjs" node scripts/benchmark-micro-strafe.mjs --human
```

## Kết quả tổng hợp

- Benchmark reaction 33 Hz đều, 60 phase: thoát cùng trục từ giữa vùng không đổi, sau snapshot đầu phát hiện trung vị/p95 60,6/60,6 ms. Thoát vuông góc: 0/30,3 → 0/0 ms. Đây là thời gian phân loại, không phải input hay va chạm.
- Benchmark ổn định A–D tổng hợp, mỗi trường hợp 5.010 mẫu, 30 phase: biên độ 0,6, tần số 1,5 Hz, nhiễu đo 0,015: tỷ lệ mẫu có midpoint 100% → 96,91%; số lần chuyển từ có sang không có midpoint 0 → 155. Tất cả chuyển đổi trong quỹ đạo tuần hoàn không có thoát; không có nghĩa mỗi lần gây một phát hụt. Kết quả khác nhau theo biên độ/tần số/nhiễu.
- Mô hình micro-strafe có `AimController` Human-like: A–D 1,2, radius 0,75 median/p95 0,437/2,365 không đổi; thoát cùng trục median/p95 riêng giai đoạn thoát 4,505/7,919 → 4,504/7,919; thoát vuông góc width 3 phần tổng 1,110/6,168 → 1,116/6,192. Proxy sai số, không phải tỷ lệ trúng. Mô hình này không chạy sender thật.

Hai bộ benchmark dùng các quỹ đạo và nhiễu khác nhau, nên không xem một kết quả giống nhau là bằng chứng ứng viên an toàn. Kết luận: ứng viên chỉ cải thiện nhận diện một dạng thoát, không giúp trường hợp cùng trục ở bộ reaction, đồng thời tăng chuyển đổi không mong muốn trong bài A–D có nhiễu. **Không tích hợp**.

Nguồn upstream tích hợp đã kiểm tra bốn biến thể cho luồng sender; chưa đo thời gian browser thực, mạng hay server. Việc tiếp theo là xây fixture đo từ receiver đến input thực và mở rộng trace; không suy diễn độ trễ hoặc hiệu quả live từ proxy.
