# Survev: đối chiếu ba kỹ thuật với mã nguồn

Ngày khảo sát: 2026-11-12. Repo: **survev/survev**. Commit đã đọc:
`3edee7e8bd07fda8a63905aab4c45b595b684a80` (package version `0.4.3`).

## 1. Kết luận trước

**Tốt nhất nếu có quyền sửa source/server riêng:** instrumentation ở source trong bản development, dùng tham chiếu và lifecycle rõ ràng; không dùng global prototype hook, không cần đoán field minified.

**Nếu chỉ so ba mẫu:**

- **Core Hook:** nền bootstrap đơn giản, ít can thiệp nhất; phù hợp nhất để nghiên cứu cơ chế capture, nhưng discovery “object nhiều key nhất” không đáng tin.
- **Neko:** ý tưởng tách bootstrap / discovery / frame callbacks tốt nhất trong ba mẫu về tổ chức runtime. Tuy nhiên bản mô tả có lỗi camera, không xử lý đủ input snapshot, và diễn giải sai packet. Không nên dùng nguyên mẫu.
- **Duality:** không nên chọn kiến trúc tổng thể. Phần signature discovery có giá trị nghiên cứu, nhưng lớp “ẩn / chống debug” làm tăng rủi ro, không chứng minh được tính vô hình, và có đoạn tự gây lỗi.

Không có mẫu nào được xác nhận “undetectable”, “zero overhead”, hay tương thích mọi build. Đây là đánh giá kiến trúc và source review, không phải benchmark FPS hay thử nghiệm cheat trên máy chủ công cộng.

## 2. Phạm vi và bằng chứng

Đã clone và đọc source chính thức, bao gồm:

- `client/src/main.ts`, `game.ts`, `input.ts`, `camera.ts`;
- `client/src/objects/player.ts`, `objectPool.ts`;
- `shared/net/joinMsg.ts`, `net.ts`, `shared/lib/bitBuffer.ts`;
- `shared/defs/register.ts`, các definition của súng/đạn/lựu đạn;
- `server/src/game/client.ts`, `objects/player.ts`, `weaponManager.ts`;
- Vite config và plugin Codefend.

Ngoài ra đã đọc `TickerListener.mjs` trong package `@pixi/ticker@7.4.3` từ npm. `client/package.json` khai báo `pixi.js-legacy ^7.4.3`; kiểm tra này xác nhận cơ chế của phiên bản 7.4.3, không khẳng định bundle live sử dụng đúng artifact ấy.

Ba đoạn người dùng gửi là excerpt có placeholder, không phải ba chương trình hoàn chỉnh. Chưa xác thực nguồn gốc, số phiên bản, payload hoặc các hàm bị lược bỏ của “Duality” và “Neko”. Không kết luận dựa trên tên thương mại của chúng.

**Giới hạn:** không lấy được build đang chạy trên survev.io để đối chiếu; commit public không đồng nghĩa bản deploy. Không build/chạy toàn bộ game, không kiểm tra anti-cheat live, không đo tỷ lệ capture thành công.

## 3. Luồng thật của game

```text
Application (instance tên App trong module, không tự trở thành window.App)
  ├─ pixi: PIXI.Application
  ├─ input: InputHandler
  └─ game: Game

pixi.ticker.add(Application.update, Application)
  └─ Application.update()
       ├─ nếu game.initialized và game.m_playing: game.update(dt)
       └─ input.flush() ở cuối frame

WebSocket onOpen
  ├─ connected = true
  └─ tạo/gửi JoinMsg

Game.init()
  ├─ tạo camera, playerBarn, lootBarn, renderer, các module...
  └─ initialized = true
```

Bằng chứng: [S1], [S2], [S3].

Điểm cần phân biệt: **Application không phải bản thân PIXI Application**. Heuristic có thể bắt object bao ngoài chứa `pixi` và `game`; PIXI instance là `app.pixi`.

`connected` là trạng thái transport, không phải “map, local player và mọi pool đã dùng được”. Đợi thêm 1.5 giây chỉ là heuristic thời gian. Init, nhận update đầu tiên, entity active và teardown là các mốc khác nhau.

## 4. Capture bằng Function.prototype.call

### 4.1 Chú thích “mọi obj.method() đều bị chặn” là sai

`obj.method()` không cần gọi qua property `Function.prototype.call`. Hook chỉ quan sát các lời gọi đi qua `.call` bị thay thế; lời gọi trực tiếp, native internal call, `.apply`, `Reflect.apply`, bound function có đường đi khác.

**Vậy tại sao vẫn có thể bắt Application?**

Trong source, Application đăng ký `this.update` cùng `this` làm ticker context [S1]. Trong PIXI ticker 7.4.3 đã đọc, `TickerListener.emit` thực hiện:

```js
this.context ? this.fn.call(this.context, deltaTime) : this.fn(deltaTime)
```

Đây là một đường gọi cụ thể phù hợp với hook: `thisArg` là Application. Không phải cơ chế intercept mọi hàm trong JavaScript.

### 4.2 So ba kiểu nhận diện

| Mẫu | Ưu điểm | Hạn chế |
|---|---|---|
| Core | Không cần tên field `pixi`; có timeout và guard | Heuristic rộng, dễ false positive; quét nhiều object; getter có thể có side effect |
| Duality | `nameInput` + `game` khớp cấu trúc source hiện tại | `game != null` vẫn chưa bảo đảm sẵn sàng; không được coi là ổn định qua mọi build |
| Neko | Kiểm tra `pixi`, `game`, `stage`, `ticker.add` rõ hơn | Vẫn phụ thuộc tên property và timing; thiếu guard rõ ràng trong excerpt |

Core dùng `obj.hasOwnProperty(k)` có thể hỏng nếu object null-prototype hoặc che khuất `hasOwnProperty`. Getter/proxy trong object bị quét có thể ném lỗi hoặc chạy code; catch không loại bỏ side effect.

“Gỡ hook ngay” chỉ hết chi phí hook đó. Callback mỗi frame, entity scan, drawing và các hook còn lại vẫn tốn chi phí. Timeout cũng chỉ chạy khi event loop có cơ hội xử lý.

Khôi phục global hook vô điều kiện có thể đè wrapper do thành phần khác cài sau. Cleanup tốt phải có ownership, idempotency và không làm mất thay đổi không thuộc mình.

## 5. Discovery và minification

### 5.1 Source cho biết mức ổn định khác nhau giữa các field

Vite production bật Codefend; plugin có regex nhằm vào nhóm tên `m_...` [S4]. Không được suy diễn rằng mọi key đều đổi, hoặc mọi key không có tiền tố đều là API được bảo đảm.

Trong snapshot, `nameInput`, `game`, `pixi`, `playerPool`, `playerIds`, `teamInfo`, `container`, `nameText` có mặt; nhiều state/method nội bộ mang tiền tố `m_` [S1], [S2], [S6].

### 5.2 “Object nhiều key nhất” và “array đầu tiên” không đủ

- Số key không xác định vai trò object.
- PlayerBarn có `playerIds` là mảng ID, còn entity nằm trong `playerPool`, pool có `m_pool` [S6], [S7].
- Mảng trong pool gồm cả slot inactive; pool tái sử dụng object và có thể thay mảng khi compact [S7]. Cache array vĩnh viễn có thể stale.
- WeakMap theo entity không tự bảo đảm đúng vòng đời: object pool có thể tái sử dụng cùng identity cho entity khác.
- `playerIds`/thông tin team không đồng nghĩa tất cả enemy entity đều đang có dữ liệu vị trí cập nhật.

Signature số lượng field, thứ tự key và `function.length === 3` chỉ là bộ lọc ứng viên. Thêm field, sửa constructor, default/rest parameter hoặc đổi transform có thể phá signature. Không tìm thấy `execGameTick` trong source client snapshot; luồng update chính là `Game.update(dt)` [S2]. Không thể coi heuristic tìm method arity 3 của Duality là được xác nhận.

Tốt hơn trong môi trường được phép: adapter theo commit/schema, kiểm tra nhiều invariant độc lập và từ chối chạy khi ambiguous. Discovery chỉ hỗ trợ chẩn đoán, không thay cho contract.

## 6. Neko: ba điểm quan trọng phải sửa cách hiểu

### 6.1 Camera: index 3 không phải zoom trực tiếp

Thứ tự field trong Camera [S5]:

```text
0 m_pos
1 m_ppu
2 m_zoom
3 m_targetZoom
4 m_screenWidth
5 m_screenHeight
6 m_shakeEnabled
7 m_shakeInt
...
```

Getter `Object.keys(cam)[3]` can thiệp target zoom, không phải `m_zoom`. Phép chiếu dùng `m_ppu * m_zoom`. Hiệu ứng tổng thể còn phụ thuộc vòng update gán lại camera; không được kết luận luôn “không có tác dụng”, nhưng chú thích và contract hiện tại sai.

### 6.2 Packet: offset có thể khớp nhưng chú thích sai nghĩa

Serializer Join thực tế [S8], [S9]:

1. MsgType Join ở lớp MsgStream;
2. protocol uint32;
3. joinToken chuỗi kết thúc null;
4. name có độ dài cố định `PlayerNameMaxLen = 16` byte;
5. useTouch, isMobile, bot;
6. các loadout field.

Vì vậy, đoạn quét chuỗi sau uint32 đang bỏ qua **joinToken**, không phải tên người chơi. Skip 16 byte tiếp theo bỏ qua **name**, không phải skin. Skip một bit là **useTouch**; bit kế tiếp là **isMobile**, không có trường Join mang tên autoLoot.

Do đó không nên kết luận đơn giản rằng offset hiện tại sai: với layout này, phép tính có thể đến đúng `isMobile`, nhưng mô tả ý nghĩa sai và thiếu ràng buộc schema/protocol. Server dùng isMobile cho mobile auto interaction và cả lựa chọn scope zoom [S10]; đây không phải công tắc chỉ thay đổi loot.

Patch send chung mọi WebSocket không tự xác thực endpoint hay protocol; header bằng 1 không đủ chứng minh payload là Join hợp lệ. Kiểm tra giới hạn mảng không thay thế được deserialize đúng schema. Không khuyến nghị sửa raw packet để thử nghiệm khi đã có source và serializer.

### 6.3 Pre/post ticker không cô lập đầy đủ input

Với callback app priority mặc định và các callback +10/-10, ý tưởng bọc quanh app tick là hợp lý cho ticker đã khảo sát. Nhưng `Application.update()` đã gọi `input.flush()` **trước khi post callback chạy** [S1], [S3].

`flush()` sao chép current state sang `keysOld`/`mouseButtonsOld`. Nếu chỉ phục hồi current state sau đó thì old state vẫn có thể chứa giá trị tạm. Edge detection pressed/released vì thế không tự được khôi phục. Input được ghi sau app tick thường dành cho frame kế tiếp, không phải packet đã gửi ở frame vừa xong.

“Phục hồi mousePos sau tick” không hoàn tác hướng nhìn/input message đã được game đọc, serialize hoặc gửi.

## 7. Duality: lớp stealth không phải lợi thế kiến trúc

- **Closed ShadowRoot:** `host.shadowRoot` không trả root, nhưng host vẫn tồn tại; đây không phải ranh giới bảo mật. Same-origin iframe tạo realm khác, không làm code vô hình với DevTools, extension có quyền phù hợp hay mọi cơ chế quan sát.
- **Pin native:** giữ tham chiếu có ích trước thay đổi về sau, nhưng chỉ nguyên bản nếu chưa bị thay trước đó. Gán `fn.apply` sửa object hàm; không tạo “miễn nhiễm anti-hook”.
- **toString + WeakMap:** có thể thay kết quả một số đường gọi, không bảo toàn identity/descriptors/hành vi. `.call` đã patch trong parent realm cũng không tự đồng nghĩa patch mọi realm khác.
- **Đệ quy async:** `(async function e() { return e() + e(); })()` gọi lại `e()` trước await; không phải promise ngủ vô hại. Có thể gây recursion overflow/rejection và tải tài nguyên ngay khi khởi tạo. Không chạy đoạn này trong kiểm tra.
- **Proxy/attachShadow traps:** attachShadow phải trả ShadowRoot; trả Promise phá contract. Proxy constructor dùng `new` đi qua `construct`, không phải `apply`; trap apply không chứng minh kiểm soát mọi cách tạo Proxy.
- **Tắt console/Error, freeze window:** giảm observability, làm hỏng code khác; freeze global không deep-freeze object con, có thể thất bại tùy môi trường. Không nên coi silent catch là hardening.
- **Font spoofing:** có thể ảnh hưởng iterator/API và không xóa mọi dấu vết. Excerpt còn lược bỏ logic iterator nên không xác minh được tính đúng.
- **Version gate:** là cơ chế version/update/redirect, không phải bằng chứng chống phát hiện. `fetch` trả Response, không tự là JSON; excerpt có placeholder nên chưa kết luận implementation hoàn chỉnh sai hay đúng.

Item DB trap có cơ sở trong source: definition register gọi Object.keys trên defs; các definition mp5/frag/bullet/explosion có thật [S11]. Nhưng trap phải tồn tại đúng lúc module evaluate; cài sau init có thể quá muộn. Không xác nhận toàn bộ trình tự Duality vì payload bị lược bỏ.

## 8. Các tuyên bố khác cần hạ mức tin cậy

**Bumpfire “vượt fire-rate”:** server xử lý gunUpdate theo cooldown và fire mode, fireWeapon gán cooldown theo fireDelay [S12]. Tạo nhiều cạnh click không chứng minh vượt giới hạn server. Cần phân biệt tự động kích semi-auto với tăng tốc độ bắn vượt luật.

**Infinite zoom / ESP toàn bản đồ:** server tạo vùng culling, chỉ gửi full/partial object trong vùng được chọn và gửi delete cho object ra khỏi vùng [S13]. Client zoom không tự tạo state thời gian thực của toàn bộ đối thủ ngoài phạm vi replication. Pool có thể chứa slot cũ/inactive.

**Đổi getter nghĩa là game không phát hiện:** sai. Thay descriptor/giá trị đọc vẫn là thay đổi có thể quan sát. Getter lưu raw không làm hook trở thành vô hình.

**Prediction:** phương trình intercept chỉ đúng dưới các giả định tốc độ đạn cố định, vận tốc mục tiêu cố định, cùng hệ tọa độ và thời gian. Clamp 3 giây/fallback khoảng cách chia speed là heuristic, không chứng minh nghiệm va chạm tồn tại. Cần xét speed <= 0, NaN, latency, interpolation và spawn offset.

**Velocity EMA:** gain cố định phụ thuộc tần số lấy mẫu. Vị trí render nội suy không đồng nghĩa vị trí server mới; đổi hướng và pool reuse có thể gây spike. Trong excerpt, reversal là tập con của sharpTurn khi cùng điều kiện speed, và phép gán raw cuối cùng khiến gain 0.98 không còn tác dụng ở nhánh hard reset.

**WeakMap alpha / style:** lưu giá trị gốc là ý tốt nhưng phải có cleanup đầy đủ. WeakMap không enumerable, không tự cung cấp danh sách object để restore. Snapshot alpha đầu tiên có thể lỗi thời nếu game chủ động đổi alpha sau đó. Nametag cũng cần restore descriptor/style; hai property __svGame/__svWant không tự bảo đảm giá trị ban đầu đúng.

**Config migration:** giữ version hữu ích, nhưng merge tùy ý JSON không xác thực kiểu/range. Chạy lại nhiều migration phải có test để tránh ghi đè preference có chủ ý của người dùng.

## 9. Kiến trúc nên thử trên bản local được phép

```text
Source development build
  → explicit debug adapter, versioned
  → lifecycle: app ready / game initialized / local entity ready / teardown
  → read-only state snapshots
  → overlay/diagnostics qua API renderer
  → automated invariants + profiling + cleanup
```

Ưu tiên:

1. Bridge chỉ bật ở development, dùng tham chiếu thật thay vì global scan.
2. Đọc state trước, không sửa input/network để xác thực discovery.
3. Contract có version/commit và phân biệt local player với spectated player.
4. Quản lý callback bằng disposer; teardown khi quit/reconnect/new match.
5. Không hủy console/Error, không anti-debug, không redirect ngoài ý muốn.
6. Test cold boot, tài nguyên load chậm, reconnect, chuyển trận, spectator, focus/blur, resize và object-pool reuse.
7. Khi đổi build mà invariant không khớp: ngừng tính năng, ghi lỗi rõ; không đoán và sửa state tiếp.

Bảng lựa chọn định tính, không phải số đo:

| Tiêu chí | Core | Duality excerpt | Neko excerpt | Source-level debug adapter |
|---|---|---|---|---|
| Dễ hiểu/kiểm tra | Tốt | Kém | Trung bình | Tốt nhất |
| Ít can thiệp global | Tương đối | Kém nhất | Trung bình | Tốt nhất |
| Chống đổi build | Heuristic | Signature dễ vỡ | Heuristic | Versioned contract |
| Vòng đời/cleanup | Một phần | Chưa rõ | Một phần | Có thể thiết kế rõ |
| Khuyên dùng nguyên mẫu | Không | Không | Không | Thiết kế phù hợp cho bản local |

**Chốt:** học bootstrap tối giản từ Core, học tách tầng runtime từ Neko, không mang lớp stealth của Duality vào. Có source thì explicit integration tốt hơn cả ba.

## 10. Kiểm tra tái lập trong workspace

```sh
node --test tests/survev-semantics.test.mjs
```

Sáu kiểm tra offline đã pass: direct call vs .call; thứ tự camera; ý nghĩa offset Join trên fixture giả; input old-state sau flush; ambiguity array đầu tiên; proxy identity vs native-looking toString.

Test dùng VM/fixture cô lập, không inject browser, không sửa hay gửi packet, không kiểm thử anti-cheat và không thay thế integration test của Survev. Camera/Join fixture được chép theo snapshot, không tự phát hiện upstream thay đổi. Đã đọc package ticker nhưng chưa chạy ticker trong browser.

## Nguồn mã cố định theo commit

- [S1] [Application: fields, ticker registration, update/flush](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/main.ts#L39-L1005)

- [S2] [Game: connect/init/update/input serialization](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/game.ts#L64-L800)

- [S3] [InputHandler: fields, flush, pressed/released](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/input.ts#L28-L98)

- [S4] [Production property obfuscation](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/vite-plugins/codefendPlugin.ts#L29-L65)

- [S5] [Camera field order and coordinate projection](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/camera.ts#L4-L41)

- [S6] [PlayerBarn and player metadata](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/objects/player.ts#L2630-L2670)

- [S7] [Object pool: reuse, inactive slots, compaction](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/src/objects/objectPool.ts#L24-L74)

- [S8] [Join serializer/deserializer](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/shared/net/joinMsg.ts#L3-L56)

- [S9] [String encoding](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/shared/lib/bitBuffer.ts#L409-L423)

- [S10] [Mobile auto interaction](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/server/src/game/objects/player.ts#L2024-L2100)

- [S11] [Definition registry initialization](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/shared/defs/register.ts#L18-L40)

- [S12] [Server gun cooldown](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/server/src/game/weaponManager.ts#L356-L398)

- [S13] [Server replication culling](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/server/src/game/client.ts#L486-L519)

- [PIXI ticker 7.4.3, package đã đọc](https://registry.npmjs.org/@pixi/ticker/-/ticker-7.4.3.tgz)

- [Vite production config](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/vite.config.ts), [client dependencies](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/client/package.json), [MsgStream/MsgType](https://github.com/survev/survev/blob/3edee7e8bd07fda8a63905aab4c45b595b684a80/shared/net/net.ts#L249-L285).
