(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const state = { connected: false, mode: 'hvnc', room: false, audio: true, mic: false, selectedWindow: 'desktop', cursor: true, quality: 'balanced', resolution: '1080' };
  // §58: trạng thái của đường "xem màn hình thật" (MJPEG). Tách khỏi `state`
  // của phiên mock để không trộn hai thứ có vòng đời khác nhau.
  // `metrics` chỉ chứa số **đo được** từ server. `frames === 0` ⇒ hiện "—",
  // không ước lượng, không nội suy. Sai một lần nữa là mất lòng tin.
  const live = { active: false, monitor: 0, fps: 15, startedAt: 0, ready: false, metrics: { frames: 0 } };
  // `native` = exe thật (DXGI trong cùng file). `false` = `npm run mock`.
  // Đây là thứ duy nhất quyết định trang này tự gọi mình là "demo" hay là app
  // thật; trước bản này nó luôn gọi mình là demo dù chạy trên máy Windows thật.
  let nativeApp = false;

  function renderMetrics() {
    const m = live.metrics || { frames: 0 };
    const has = live.active && m.frames > 0;
    $('#latencyText').textContent = has ? `${m.msPerFrame.toFixed(0)} ms` : '—';
    $('#bandwidthText').textContent = has ? `${m.mbps.toFixed(1)} Mbps` : '—';
    // Góc dưới phải từng ghi "1080p · 30 FPS (demo)" — số bịa. Giờ chỉ nói
    // đúng những gì biết.
    const res = $('#screenResolution');
    if (res) {
      res.textContent = has
        ? `${m.width}×${m.height} · ${m.fps.toFixed(1)} FPS`
        : (live.active ? 'Đang chờ frame' : 'Chưa có phiên');
    }
    const detail = $('#liveMetrics');
    if (detail) {
      detail.textContent = has
        ? `${m.frames} frame · ${m.width}×${m.height} · ${m.fps.toFixed(1)} fps · ${m.kbPerFrame.toFixed(0)} KB/frame · encode ${m.msPerFrame.toFixed(0)} ms`
        : (live.active ? 'Đang chờ frame đầu tiên…' : '');
    }
  }

  async function refreshMetrics() {
    if (!live.active) { renderMetrics(); return; }
    try {
      const response = await authorisedFetch('/api/live/status', { cache: 'no-store' });
      const status = await response.json();
      live.metrics = status.metrics || { frames: 0 };
    } catch { /* giữ số cũ; không bịa số mới */ }
    renderMetrics();
  }
  const settingDefs = [
    { id:'quality', title:'Chất lượng hình ảnh', hint:'Ưu tiên rõ nét hay mượt khi mạng yếu?', group:'view', scope:'device', effect:'Ngay', terms:'mờ nét blur sharp lag chậm mạng', options:[['auto','Tự động'],['sharp','Nét'],['smooth','Mượt']] },
    { id:'display', title:'Kiểu hiển thị', hint:'Chọn theo việc bạn đang làm.', group:'view', scope:'device', effect:'Ngay', terms:'màn hình độ phân giải chữ nhỏ to đọc', options:[['real','Dùng thật'],['comfortable','Vừa mắt'],['large-text','Chữ to'],['sharp','Nét']] },
    { id:'aspect', title:'Tỉ lệ khung hình', hint:'Cách vừa nội dung vào khung xem.', group:'view', scope:'device', effect:'Ngay', terms:'đầy vừa fit crop tỉ lệ', options:[['fit','Vừa'],['fill','Đầy'],['100','100%']] },
    { id:'touch', title:'Cách chạm trên điện thoại', hint:'Chọn thao tác cuộn hoặc rê chuột.', group:'input', scope:'device', effect:'Ngay', terms:'mobile điện thoại scroll chuột ảo', options:[['scroll','Hai ngón cuộn'],['mouse','Chuột ảo']] },
    { id:'cursor-mode', title:'Con trỏ từ xa', hint:'Cách hiển thị con trỏ trong màn hình.', group:'input', scope:'server', effect:'Phiên sau', terms:'cursor chuột vị trí', options:[['auto','Tự động'],['local','Cục bộ'],['video','Theo video']] },
    { id:'keyboard', title:'Bàn phím', hint:'“Theo ý định” phù hợp hầu hết trường hợp.', group:'input', scope:'server', effect:'Phiên sau', terms:'gõ keyboard ime thô nhập', options:[['intent','Theo ý định'],['raw','Thô · dùng IME máy kia']] },
    { id:'audio', title:'Âm thanh phiên', hint:'Chọn có hỏi trước khi phát âm thanh không.', group:'sound', scope:'server', effect:'Ngay', terms:'tiếng loa audio hỏi', options:[['ask','Hỏi mỗi phiên'],['on','Bật'],['off','Tắt']] },
    { id:'volume', title:'Âm lượng nghe', hint:'Âm lượng phát trên thiết bị bạn đang dùng.', group:'sound', scope:'device', effect:'Ngay', terms:'tiếng nhỏ to loa volume', range:true },
    { id:'hide-screen', title:'Ẩn khỏi màn hình thật', hint:'Ẩn cửa sổ đang điều khiển trên máy chủ.', group:'device', scope:'server', effect:'Phiên sau', terms:'ẩn hvnc vnc riêng tư màn hình', toggle:true },
    { id:'hide-taskbar', title:'Ẩn cả taskbar', hint:'Chỉ áp dụng trong phiên điều khiển.', group:'device', scope:'server', effect:'Ngay', terms:'taskbar thanh công cụ ẩn', toggle:true },
    { id:'language', title:'Ngôn ngữ', hint:'Ngôn ngữ giao diện.', group:'device', scope:'device', effect:'Ngay', terms:'language tiếng việt english', options:[['vi','Tiếng Việt'],['en','English · mock']] },
    { id:'theme', title:'Giao diện', hint:'Chọn sáng, tối hoặc theo thiết bị.', group:'device', scope:'device', effect:'Ngay', terms:'theme dark sáng tối hệ thống', options:[['light','Sáng'],['dark','Tối'],['system','Theo hệ thống']] }
  ];
  const advancedDefs = [
    {id:'max-bitrate',title:'Bitrate trần',hint:'Giới hạn dữ liệu khi mạng yếu.',section:'Muốn nét hơn / mượt hơn',terms:'mờ nét mạng bitrate',options:[['5','5 Mbps'],['10','10 Mbps · mặc định'],['15','15 Mbps']]},
    {id:'max-fps',title:'Tốc độ khung hình',hint:'Chọn mức tối đa cho phiên.',section:'Muốn nét hơn / mượt hơn',terms:'fps mượt giật',options:[['15','15 FPS'],['30','30 FPS · mặc định'],['60','60 FPS']]},
    {id:'keyframe',title:'Khung hình chủ',hint:'Khoảng gửi khung hình đầy đủ.',section:'Muốn nét hơn / mượt hơn',terms:'keyframe video khựng',options:[['1','1 giây'],['2','2 giây · mặc định'],['3','3 giây']]},
    {id:'scaler',title:'Độ sắc nét khi co giãn',hint:'Thuật toán nội suy hình ảnh.',section:'Muốn nét hơn / mượt hơn',terms:'scaler sharpen mờ nét',options:[['balanced','Cân bằng · mặc định'],['sharp','Sắc nét'],['fast','Nhanh']]},
    {id:'sharpen',title:'Làm nét chữ',hint:'Tăng nét nhẹ sau khi co giãn.',section:'Muốn nét hơn / mượt hơn',terms:'sharpen text chữ',options:[['off','Tắt · mặc định'],['low','Nhẹ']]},
    {id:'jitter',title:'Ưu tiên độ trễ',hint:'Đổi độ trễ lấy hình ảnh ổn định hơn.',section:'Muốn ít trễ hơn',terms:'trễ lag chậm jitter',options:[['low','Ít trễ · mặc định'],['smooth','Mượt hơn']]},
    {id:'cursor-echo',title:'Phản hồi con trỏ tức thì',hint:'Hiển thị vị trí dự đoán khi mạng trễ.',section:'Muốn ít trễ hơn',terms:'chuột cursor lag trễ',options:[['on','Bật · mặc định'],['off','Tắt']]},
    {id:'ripple',title:'Hiệu ứng chạm',hint:'Tắt vòng sáng nếu gây rối mắt.',section:'Muốn ít trễ hơn',terms:'ripple animation chạm',options:[['on','Bật · mặc định'],['off','Tắt']]},
    {id:'resolution',title:'Độ phân giải đầu ra',hint:'Tự động theo màn hình hoặc chọn mức thấp hơn.',section:'Màn hình & toạ độ',terms:'resolution màn hình 720 1080',options:[['auto','Tự động · mặc định'],['1080','1080p'],['720','720p']]},
    {id:'dpi',title:'Tỉ lệ giao diện Windows',hint:'Dùng khi chữ trên máy chủ quá nhỏ.',section:'Màn hình & toạ độ',terms:'dpi scale chữ nhỏ',options:[['100','100% · mặc định'],['125','125%'],['150','150%']]},
    {id:'monitor',title:'Màn hình ưu tiên',hint:'Chọn màn hình khi máy có nhiều display.',section:'Màn hình & toạ độ',terms:'monitor display màn hình',options:[['primary','Màn hình chính · mặc định'],['2','Màn hình 2']]},
    {id:'keyboard-layout',title:'Bố cục bàn phím máy chủ',hint:'Chỉ đổi nếu phím gõ ra ký tự sai.',section:'Bàn phím',terms:'keyboard layout gõ sai',options:[['system','Theo máy chủ · mặc định'],['vi','Tiếng Việt'],['en','English']]},
    {id:'input-rate',title:'Tốc độ nhập tối đa',hint:'Giữ mặc định trừ khi bị rớt phím.',section:'Bàn phím',terms:'rate limit input phím rớt',options:[['60','60 sự kiện/s · mặc định'],['100','100 sự kiện/s']]},
    {id:'block-win-lock',title:'Chặn phím khoá máy',hint:'Không gửi Win+L tới máy chủ.',section:'Bàn phím',terms:'win l lock khoá màn hình',options:[['on','Chặn · mặc định'],['off','Cho phép']]},
    {id:'listen-port',title:'Cổng kết nối',hint:'Đổi cổng cần khởi động lại dịch vụ.',section:'Bàn giao kết nối',terms:'port cổng kết nối',effect:'Khởi động lại',options:[['8443','8443 · mặc định'],['443','443']]},
    {id:'certificate',title:'Chứng chỉ HTTPS',hint:'Không có lựa chọn tắt mã hoá.',section:'Bàn giao kết nối',terms:'TLS SSL cert chứng chỉ HTTPS',options:[['self','Tự tạo · mặc định'],['custom','Chứng chỉ riêng']]},
    {id:'stun-turn',title:'Kết nối ngoài mạng nhà',hint:'Chỉ cấu hình khi không dùng được tailnet.',section:'Bàn giao kết nối',terms:'stun turn relay internet WAN',options:[['auto','Tự động · mặc định'],['tailnet','Chỉ tailnet']]},
    {id:'latency-hud',title:'HUD độ trễ',hint:'Hiện số liệu nhỏ trong màn hình phiên.',section:'Chẩn đoán',terms:'debug latency hud chẩn đoán',options:[['off','Tắt · mặc định'],['on','Bật']]},
    {id:'log-level',title:'Chi tiết nhật ký',hint:'Không tắt nhật ký bảo mật.',section:'Chẩn đoán',terms:'log debug nhật ký',options:[['normal','Thông thường · mặc định'],['verbose','Chi tiết']]},
    {id:'encoder',title:'Bộ mã hoá video',hint:'Tự động chọn Intel QSV trên máy này.',section:'GPU mã hoá',terms:'gpu encoder nvenc qsv nvidia intel',options:[['auto','Tự động · QSV'],['qsv','Intel QSV'],['nvenc','NVIDIA']]}
  ];
  const allSettingDefs = [...settingDefs, ...advancedDefs];
  const settingDefaults = Object.fromEntries(allSettingDefs.map(def => [def.id, def.range ? 70 : def.options ? def.options[0][0] : false]));
  let settings = (() => { try { return { ...settingDefaults, ...JSON.parse(localStorage.getItem('lantern-mock-settings') || '{}') }; } catch { return { ...settingDefaults }; } })();
  let settingsGroup = 'all';
  // Nhãn cửa sổ **động**: giờ đến từ `GET /api/windows` (§5.4 EnumWindows),
  // không còn ba chuỗi viết cứng. `desktop` vẫn là mục đặc biệt (stream cả màn
  // hình, §5.3 VNC) vì nó không phải một hwnd nào.
  const labels = { desktop: 'Toàn bộ màn hình' };
  // Snapshot §41.3 #3: client **chỉ** mở được `wid` trong snapshot này (TTL
  // 3 s). Không phải để tiện — nếu thiếu, server trả 403 `window.unknown` và
  // đây chính là chỗ người dùng thấy "bấm không được".
  let windowSnapshot = '';
  let realWindows = [];
  // §6.4 — bộ điều khiển cắm vào khung hình live. `null` = chưa cắm (chưa có
  // phiên, hoặc tính năng tắt). Đây là thứ khiến "xem" thành "dùng được".
  let liveController = null;
  let liveFrame = { width: 0, height: 0 };
  let inputModule = null;
  let toastTimer;
  let currentSessionId = null;
  // §7.1: đã đặt mật khẩu thì **mọi** route cần quyền đòi token, và token phải
  // đi kèm mỗi request. Dùng `authFetch` (nạp động) chứ không `fetch` trần:
  // `fetch` trần chỉ hoạt động khi máy chưa có mật khẩu — tức là app chạy được
  // ở lần chạy đầu và **hỏng sau khi người dùng đặt mật khẩu**, đúng lúc họ
  // tưởng mọi thứ đã xong.
  let authFetchModule = null;
  const authorisedFetch = async (path, options = {}) => {
    if (!authFetchModule) {
      authFetchModule = import('./auth.js').then((module) => module.authFetch).catch(() => null);
    }
    const send = await authFetchModule;
    return (send || fetch)(path, options);
  };
  const apiRequest = async (path, options = {}) => {
    const response = await authorisedFetch(path, { ...options, headers: { ...(options.body ? { 'content-type': 'application/json' } : {}), ...options.headers }, body: options.body ? JSON.stringify(options.body) : undefined });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || `http_${response.status}`);
    return payload;
  };

  function toast(message) {
    const el = $('#toast');
    el.textContent = message;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 2600);
  }
  function setToggle(el, active) {
    el.classList.toggle('on', active);
    el.setAttribute('aria-pressed', String(active));
  }
  function syncMode() {
    $$('.mode-btn').forEach(btn => btn.classList.toggle('active', btn.dataset.mode === state.mode));
    $('#sessionMode').textContent = state.mode === 'hvnc' ? 'Cửa sổ riêng' : 'Toàn màn hình';
    $('#mockWindow').classList.toggle('compact', state.mode === 'hvnc');
    if (state.mode === 'vnc' && state.selectedWindow !== 'desktop') {
      state.selectedWindow = 'desktop';
      $('#windowLabel').textContent = labels.desktop;
      $$('.window-option').forEach(btn => btn.classList.toggle('selected', btn.dataset.window === 'desktop'));
      updateMockWindow();
    }
  }
  /**
   * §5.4 — hiện danh sách cửa sổ **thật** trong dialog chọn.
   *
   * Dùng `textContent` cho mọi chuỗi: title do app bên thứ ba đặt, nên nó có
   * thể chứa `<script>` (§41.4 T5). `innerHTML` với dữ liệu server là lỗ hổng
   * XSS kinh điển, và CSP không cứu được nếu ta tự chèn thẻ.
   */
  function renderWindowOptions() {
    const box = $('#windowOptions');
    if (!box) return;
    box.replaceChildren();
    // `desktop` luôn có mặt: trên Linux `EnumWindows` trả rỗng (§58.3), và nếu
    // danh sách rỗng thì người dùng còn ít nhất một lựa chọn dùng được.
    const choices = [{ wid: 'desktop', title: 'Toàn bộ màn hình', app: 'Desktop', min: false, elevated: false }]
      .concat(realWindows);
    for (const choice of choices) {
      const button = document.createElement('button');
      button.className = 'window-option' + (choice.wid === state.selectedWindow ? ' selected' : '');
      button.dataset.window = choice.wid;
      // Không có thumbnail (chưa nối §5.4 `PrintWindow`) ⇒ icon chữ cái đầu
      // của app, thay vì một ô ảnh rỗng trông như hỏng.
      const icon = document.createElement('span');
      icon.className = 'option-icon';
      icon.textContent = (choice.app || '?').slice(0, 1).toUpperCase();
      const text = document.createElement('span');
      const title = document.createElement('b');
      title.textContent = choice.title || choice.app || choice.wid;
      const small = document.createElement('small');
      // §5.4: nói rõ trạng thái, vì "cửa sổ thu nhỏ" và "chạy quyền admin" là
      // hai thứ người dùng cần biết **trước** khi bấm.
      const bits = [choice.app];
      if (choice.min) bits.push('đang thu nhỏ');
      if (choice.elevated) bits.push('quyền admin — chỉ xem được');
      small.textContent = bits.filter(Boolean).join(' · ');
      text.append(title, small);
      const check = document.createElement('span');
      check.className = 'option-check';
      check.textContent = '✓';
      button.append(icon, text, check);
      box.append(button);
    }
  }

  function updateMockWindow() {
    const content = {
      desktop: ['Màn hình nền', 'Phiên demo đã sẵn sàng', 'Đây là hình ảnh minh hoạ — chưa truyền hình ảnh thật.'],
      browser: ['Google Chrome — Tab mới', 'Trình duyệt đã được chọn', 'Window picker cập nhật theo lựa chọn của bạn.'],
      notes: ['Ghi chú — Notepad', 'Ghi chú đang mở', 'Nội dung minh hoạ trong cửa sổ riêng.']
    }[state.selectedWindow] || ['Cửa sổ đã chọn', state.selectedWindow, ''];
    $('#windowLabel').textContent = labels[state.selectedWindow] || state.selectedWindow;
    $('#mockWindowTitle').textContent = content[0];
    $('#mockMessageTitle').textContent = content[1];
    $('#mockMessageText').textContent = content[2];
    $$('.window-option').forEach(btn => btn.classList.toggle('selected', btn.dataset.window === state.selectedWindow));
  }
  // ---------------------------------------------------------------------
  // §58 — "Xem máy thật": MJPEG, không WebRTC.
  // Nút này chỉ sống trong bản exe Windows (nơi có gst-launch-1.0 + DXGI).
  // Trên `npm run mock` nó tự ẩn, vì để một nút luôn lỗi còn tệ hơn không có nút.
  // ---------------------------------------------------------------------
  function liveUrl() {
    // `live.fps` là **lựa chọn của người dùng** (hiện trên slider). Tab ẩn dùng
    // `live.hiddenFps` riêng: sửa `live.fps` sẽ làm slider nhảy về 5, và người
    // dùng quay lại thấy lựa chọn của mình bị đổi mà không hiểu vì sao.
    // Thứ tự ưu tiên: chế độ yếu (1 fps) > tab ẩn (5 fps) > lựa chọn người dùng.
    // Chế độ yếu thắng vì nó là hành động **có chủ ý** của người dùng.
    const fps = live.weakNet ? 1 : (live.hiddenFps || live.fps);
    return `/api/live.mjpg?monitor=${live.monitor}&fps=${fps}`;
  }
  /**
   * §6.4 + §6.5 — cắm chuột/bàn phím vào khung hình **live** trên trang chính.
   *
   * Trước bản này, điều khiển chỉ có ở trang `/live` (mở tab riêng). Người
   * dùng xem màn hình thật trên trang chính và **bấm không có gì xảy ra** —
   * với họ đó là "app hỏng", không phải "tính năng ở tab khác". Đây là mảnh
   * biến bản xem thành bản dùng được.
   *
   * Nạp `input.js` **động**: nó là ES module, và `app.js` là script cổ điển.
   * Nạp tĩnh sẽ đổi `app.js` thành module và `npm test` đọc nó như text sẽ
   * không còn phản ánh đúng — tách đường nạp để hai bài test độc lập nhau.
   */
  async function attachLiveInput() {
    if (liveController || !live.ready) return;
    try {
      inputModule = inputModule || await import('/input.js');
    } catch { return; }
    const img = $('#liveImage');
    if (!img) return;
    const sessionId = currentSessionId || await (async () => {
      try {
        const response = await authorisedFetch('/api/sessions/current', { cache: 'no-store' });
        const data = await response.json();
        return data.session ? data.session.id : '';
      } catch { return ''; }
    })();
    if (!sessionId) return;
    const post = async (path, body) => {
      const isBinary = body instanceof Blob;
      // §7.1: phải qua `authFetch`. Đây là đường **gửi chuột/bàn phím** — nếu nó
      // dùng `fetch` trần thì sau khi đặt mật khẩu, hình vẫn chạy mà **không
      // điều khiển được**, và không có lỗi nào hiện ra vì `post` không kiểm
      // `response.ok` (gói `move` 12 byte, không ai đọc body).
      await authorisedFetch(path, {
        method: 'POST',
        headers: isBinary ? { 'content-type': 'application/octet-stream' }
                          : { 'content-type': 'application/json' },
        body: isBinary ? body : JSON.stringify(body),
        cache: 'no-store',
      });
    };
    const attached = inputModule.attach(img, {
      sid: sessionId,
      post,
      // §6.10.3: toạ độ chuẩn hoá theo **khung hình**, nên phải là kích thước
      // thật của frame MJPEG vừa vẽ, không phải kích thước thẻ <img>.
      frame: () => liveFrame,
      // §6.10.3: chế độ hiển thị đổi phép quy đổi toạ độ. Đọc từ **DOM** mỗi
      // lần click (qua dataset) thay vì chụp lại: người dùng đổi Fit→Fill giữa
      // phiên là chuyện thường, và giá trị chụp lại sẽ làm mọi click sau đó lệch.
      mode: () => $('#mockDesktop').dataset.aspect || 'fit',
    });
    // §6.4.6: `Esc` làm trình duyệt nhả lock **mà không hỏi trang**; nhãn UI phải
    // theo trạng thái thật, nếu không nó nói "đang bật" sau khi đã tắt.
    attached.controller.onLockChange = renderRelativeLock;
    liveController = attached.controller;
    // §30.7: bàn phím điện thoại chỉ có nghĩa khi đã có controller (nó gửi qua
    // cùng đường phím).
    attachChips().catch(() => {});
    inputModule.installUnloadRelease(liveController, {
      beacon: (path, body) => navigator.sendBeacon(path, body),
      addEventListener: (name, fn) => window.addEventListener(name, fn),
    });
    return liveController;
  }

  function detachLiveInput() {
    if (!liveController) return;
    // §6.4.7: nhả **mọi** phím/chuột trước khi gỡ. Nếu không, phím đang giữ
    // (Ctrl, Shift) ở lại trạng thái down trên máy remote và mọi thao tác sau
    // đều sai — bug đã gặp ở trang /live.
    // §30.7: nhả chip **trước** — `releaseAll` của controller không biết
    // `ChipState` đang giữ Ctrl, nên Ctrl đó sẽ sống qua lần kết nối sau.
    detachChips();
    try { liveController.releaseAll('detach'); } catch {}
    try { liveController.detach(); } catch {}
    liveController = null;
  }

  function renderLive() {
    const img = $('#liveImage');
    const holder = $('#liveView');
    const empty = $('#liveEmpty');
    const frame = $('#screenFrame');
    // §6.10.3: chế độ hiển thị áp lên **khung hình live**, không chỉ lên
    // `.mock-desktop` (bản giả trước khi có stream thật). Trước bản này setting
    // đổi `data-aspect` của desktop giả, nên đổi Fit→Fill **không ảnh hưởng gì**
    // tới hình thật — người dùng bấm và không thấy gì xảy ra.
    holder.dataset.aspect = $('#mockDesktop').dataset.aspect || 'fit';
    holder.classList.toggle('hidden', !live.active);
    empty.classList.toggle('hidden', live.active);
    frame.classList.toggle('live', live.active);
    $('#mockDesktop').classList.toggle('hidden', live.active);
    $('#liveBtn').classList.toggle('on', live.active);
    $('#liveBar').classList.toggle('hidden', !live.active);
    $('#liveBtnLabel').textContent = live.active ? 'Dừng xem máy thật' : 'Xem máy thật';
    // §50.4: tab bar là chỗ **duy nhất** người dùng còn nhìn khi họ ở tab khác —
    // và đó chính là lúc họ cần biết phiên đang chạy hay đã đứt.
    setTabTitle(live.active);
    if (!live.active) {
      // Tắt hẳn thì xoá cờ "đã thấy frame": lần Start sau là một stream mới,
      // và một ảnh lỗi ngay lập tức phải báo lý do thay vì đếm ngược 60 giây.
      live.firstFrameSeen = false;
      reconnectStartedAt = 0;
      if (reconnectTimer) { clearInterval(reconnectTimer); reconnectTimer = null; }
      $('#liveReconnect')?.classList.add('hidden');
    }
    // Trước bản này dòng này ghi "không có tiếng/điều khiển" — đúng lúc đó,
    // nhưng giờ điều khiển **có**. Ghi sai sự thật ở đây tệ hơn không ghi gì:
    // người dùng đọc "không điều khiển được" rồi không thử bấm.
    $('#liveMeta').textContent = live.active
      ? `MJPEG thật · màn hình ${live.monitor} · tối đa ${live.fps} fps · bấm để điều khiển · không có tiếng`
      : '';
    renderMetrics();
    if (live.active) {
      if (img.dataset.src !== liveUrl()) { img.dataset.src = liveUrl(); img.src = liveUrl(); }
      // Cắm điều khiển **sau** khi ảnh có src: `attach` cần phần tử đã tồn tại
      // trong layout để tính toạ độ. Không `await` — đây là render, và nạp
      // module không được chặn vẽ khung hình.
      attachLiveInput();
    } else if (img.dataset.src) {
      detachLiveInput();
      // Bỏ `src` là cách duy nhất để trình duyệt **đóng kết nối** stream;
      // nếu chỉ ẩn ảnh thì pipeline vẫn chạy và vẫn nóng máy.
      img.removeAttribute('src');
      img.dataset.src = '';
    }
  }
  // `naturalWidth/Height` là kích thước **thật** của frame MJPEG vừa vẽ — dùng
  // để chuẩn hoá toạ độ (§6.10.3). Không dùng `getBoundingClientRect()`: khung
  // hình bị co giãn theo CSS, nên toạ độ pixel màn hình không bằng toạ độ chuột.
  document.addEventListener('DOMContentLoaded', () => {
    const img = $('#liveImage');
    if (!img) return;
    img.addEventListener('load', () => {
      liveFrame = { width: img.naturalWidth, height: img.naturalHeight };
    });
  });

  let metricsTimer = 0;
  function startMetricsPolling() {
    clearInterval(metricsTimer);
    metricsTimer = setInterval(refreshMetrics, 1000);
  }
  function stopMetricsPolling() {
    clearInterval(metricsTimer);
    metricsTimer = 0;
  }

  /**
   * Bật đường xem màn hình thật.
   *
   * **Hàm này từng không tồn tại** trong khi `offerResume()` gọi nó trong
   * `try { await startLive(); } catch {}`. Kết quả: bấm "Tiếp tục" ở hộp thoại
   * nối lại phiên **không làm gì cả** — `ReferenceError` bị `catch` rỗng nuốt,
   * `live.active` vẫn `false`, và trang vẫn hiện desktop giả trong khi một phiên
   * thật đang mở trên máy. Không có lỗi nào hiện ra, nên không ai lần được.
   */
  async function startLive({ notify = false } = {}) {
    if (live.active) return;
    // Hỏi lại server: trạng thái có thể đã đổi (driver vừa nạp, vừa cắm màn
    // hình thứ hai). Rẻ — một request — và tránh bật một khung hình sẽ lỗi.
    await refreshLiveStatus();
    if (!live.ready) {
      toast($('#liveBtn').title || 'Chưa xem được màn hình thật trên máy này.');
      return;
    }
    live.active = true;
    live.startedAt = Date.now();
    live.firstFrameSeen = false;
    startMetricsPolling();
    setTimeout(refreshMetrics, 300);
    renderLive();
    if (notify) toast('Đang xem màn hình thật.');
  }

  /**
   * Đổi mọi nhãn "demo / mô phỏng" thành nhãn thật khi chạy trong `exe`.
   *
   * Danh sách này cố ý **liệt kê từng chỗ** thay vì tìm-thay chuỗi: mỗi câu là
   * một lời hứa với người dùng, và câu sai ở đây là câu nói "sản phẩm này
   * không thật" ngay trên sản phẩm thật.
   */
  function applyNativeLabels() {
    const pill = $('.demo-pill');
    if (pill) pill.innerHTML = '<i></i> LANTERN · ĐANG CHẠY';
    const connect = $('#connectLabel');
    if (connect && !state.connected) connect.textContent = 'Bắt đầu phiên';
    const hint = $('#connectHint');
    if (hint && !state.connected) hint.textContent = 'Chạy trên máy này · DXGI + JPEG trong exe';
    const state_ = $('#screenState');
    if (state_ && !live.active) state_.textContent = 'Sẵn sàng xem màn hình';
    const sub = $('#sessionSubstatus');
    if (sub && !state.connected) sub.textContent = 'Bấm để bắt đầu';
    const note = $('#connectionNote');
    if (note) note.textContent = 'Kết nối cục bộ · không qua mạng ngoài';
    const tipTitle = $('#tipTitle');
    if (tipTitle) tipTitle.textContent = 'Màn hình thật, điều khiển thật';
    const tip = $('#tipCardBody');
    if (tip) tip.textContent = 'Phiên chạy ngay trong exe này: DXGI chụp màn hình, JPEG nén trong tiến trình, SendInput điều khiển chuột/bàn phím. Không cần cài GStreamer hay driver nào. Chưa có tiếng và WebRTC (§52.4, §37).';
    const footer = $('#footerMode');
    if (footer) footer.textContent = 'Bản chạy thật · DXGI + JPEG trong exe';
    const watermark = $('#mockWatermark');
    if (watermark) watermark.textContent = '';
  }

  function stopLive(notify = false) {
    if (!live.active) return;
    live.active = false;
    // §50.1 #5: người dùng có thể đã chuyển sang app khác. Dừng do **họ bấm**
    // thì không cần chuông (họ đang ở đây), nhưng dừng vì mất kết nối thì cần.
    if (notify) announce('end').catch(() => {});
    stopMetricsPolling();
    live.metrics = { frames: 0 };
    renderLive();
    if (notify) toast('Đã dừng xem màn hình thật.');
  }
  // Hỏi server một chỗ duy nhất: nút có dùng được không, và nếu không thì vì sao.
  async function refreshLiveStatus() {
    try {
      const response = await authorisedFetch('/api/live/status');
      if (!response.ok) return;
      const status = await response.json();
      if (typeof status.available !== 'boolean') return;
      live.ready = status.available;
      renderLiveStatus(status);
    } catch { /* server cũ: không có route này */ }
  }

  function renderLiveStatus(status) {
    $('#liveBtn').classList.remove('hidden');
    $('#liveBtn').classList.toggle('unavailable', !status.available);
    $('#liveBtn').title = status.available ? '' : (status.detail || 'Chưa sẵn sàng');
    $('#connectionNote').textContent = status.available ? '' : (status.detail || '');
    // Không còn bước cài đặt nào: capture + JPEG nằm trong exe. Nếu không dùng
    // được thì lý do là môi trường (Linux, RDP, driver), không phải "thiếu phần mềm".
  }

  function toggleLive() {
    if ($('#liveBtn').classList.contains('unavailable')) {
      // Nói **lý do cụ thể** thay vì bật một khung đen — đây là khác biệt giữa
      // "app lỗi" và "máy chưa cài GStreamer".
      toast($('#liveBtn').title || 'Chưa xem được màn hình thật.');
      return;
    }
    live.active = !live.active;
    if (live.active) { live.startedAt = Date.now(); startMetricsPolling(); setTimeout(refreshMetrics, 300); }
    else stopMetricsPolling();
    // §50.1 #5: báo bằng tiếng/rung. `toggleLive` chạy **từ một click**, nên
    // `AudioContext` đã được mở khoá ở `pointerdown` ngay trước đó — đây là thời
    // điểm duy nhất trong luồng mà tiếng chuông chắc chắn kêu được.
    announce(live.active ? 'start' : 'end').catch(() => {});
    renderLive();
    toast(live.active
      ? 'Đang xem màn hình thật (MJPEG). Đóng tab hoặc bấm Dừng để tắt capture.'
      : 'Đã dừng xem màn hình thật.');
  }

  function setConnected(active, notify = true) {
    state.connected = active;
    $('#connectBtn').classList.toggle('connected', active);
    const real = nativeApp;
    $('#connectLabel').textContent = active ? 'Kết thúc phiên' : (real ? 'Bắt đầu phiên' : 'Bắt đầu phiên demo (mô phỏng)');
    $('#connectHint').textContent = active
      ? (real ? 'Đang chạy · phiên trên máy này' : 'Đang mô phỏng · dữ liệu không rời trình duyệt')
      : (real ? 'Chạy trên máy này · DXGI + JPEG trong exe' : 'Mô phỏng cục bộ · không truy cập thiết bị thật');
    $('#screenState').textContent = active ? (real ? 'Phiên đang hoạt động' : 'Phiên demo đang hoạt động')
                                           : (real ? 'Sẵn sàng xem màn hình' : 'Đang chờ phiên demo');
    $('#sessionStatus').textContent = active ? (real ? 'Đã kết nối' : 'Đã kết nối · demo') : 'Chưa kết nối';
    $('#sessionSubstatus').textContent = active
      ? (real ? 'Đang chạy trên máy này · vừa bắt đầu' : 'Thiết bị mô phỏng · vừa bắt đầu')
      : (real ? 'Bấm để bắt đầu' : 'Bắt đầu để thử giao diện');
    // Không đặt số ở đây: `24 ms` / `2.4 Mbps` từng là hằng số viết cứng, hiện
    // ra như số đo thật. Số giờ lấy từ `renderMetrics()` — đo trong server.
    $('.latency').classList.toggle('good', active && live.metrics.frames > 0);
    $('#mockMessageTitle').textContent = active ? 'Phiên demo đang hoạt động' : ({ desktop: 'Phiên demo đã sẵn sàng', browser: 'Trình duyệt đã được chọn', notes: 'Ghi chú đang mở' }[state.selectedWindow]);
    $('#cursorPointer').classList.toggle('hidden', !active || !state.cursor);
    if (notify && active) toast(nativeApp ? 'Phiên đã bắt đầu. Bấm "Xem máy thật" để thấy màn hình.' : 'Phiên mô phỏng bắt đầu. Muốn xem màn hình thật thì bấm "Xem máy thật".');
    else if (notify) toast('Phiên mock đã kết thúc.');
  }
  function openOverlay(id) {
    // The spec allows one surface at a time: replace, never stack dialogs.
    $$('.overlay').forEach(overlay => overlay.classList.add('hidden'));
    const el = $(id);
    el.classList.remove('hidden');
    document.body.classList.add('has-overlay');
    const dialog = $('.dialog', el);
    if (dialog) dialog.setAttribute('tabindex', '-1');
    $('.dialog', el)?.focus();
  }
  function closeOverlay(id) {
    $(id).classList.add('hidden');
    if ($$('.overlay').every(overlay => overlay.classList.contains('hidden'))) document.body.classList.remove('has-overlay');
  }

  $('#connectBtn').addEventListener('click', async () => {
    $('#connectBtn').disabled = true;
    try {
      if (!state.connected) {
        stopLive(); // một bề mặt tại một thời điểm (§49.3)
        // §6.13: *"App chạy quyền admin (nếu server không elevated) | UIPI |
        // Cảnh báo **trước** khi bắt đầu"*.
        //
        // Picker đã ghi "quyền admin — chỉ xem được" cạnh cửa sổ, nhưng người
        // dùng có thể đã chọn từ trước đó và không đọc lại. Bắt đầu một phiên
        // mà **không điều khiển được** rồi mới phát hiện là trải nghiệm tệ nhất
        // trong danh sách: họ tưởng app hỏng.
        //
        // Hỏi, không chặn: xem được vẫn có ích (đọc số liệu, chụp lại).
        const picked = (realWindows || []).find(win => win.wid === state.selectedWindow);
        if (picked && picked.elevated) {
          const proceed = window.confirm(
            'Cửa sổ này chạy quyền admin. Windows chặn gửi chuột/bàn phím vào nó từ '
            + 'một app không elevated (UIPI), nên bạn sẽ **xem được nhưng không điều '
            + 'khiển được**.\n\nVẫn bắt đầu?'
          );
          if (!proceed) return;
        }
        // §41.3 #3: `snapshotId` **phải** đi kèm `wid`, nếu không server không
        // kiểm được `wid` có thuộc danh sách vừa trả hay không ⇒ 403.
        const result = await apiRequest('/api/sessions', { method: 'POST', body: { mode: state.mode, windowId: state.selectedWindow, snapshotId: windowSnapshot, audio: state.audio } });
        currentSessionId = result.session.id;
        setConnected(true);
      } else {
        if (currentSessionId) await apiRequest(`/api/sessions/${currentSessionId}`, { method: 'DELETE' });
        currentSessionId = null;
        setConnected(false);
      }
    } catch (error) { toast(error.message === 'session_already_active' ? 'Đã có phiên mock đang hoạt động ở nơi khác.' : 'Không gọi được mock backend. Hãy chạy `npm run mock`.'); }
    finally { $('#connectBtn').disabled = false; }
  });
  $$('.mode-btn').forEach(btn => btn.addEventListener('click', () => {
    state.mode = btn.dataset.mode;
    syncMode();
    toast(state.mode === 'hvnc' ? 'Đã chuyển sang chế độ cửa sổ riêng.' : 'Đã chuyển sang chế độ toàn màn hình.');
  }));
  $('#windowPicker').addEventListener('click', () => {
    if (state.mode === 'vnc') toast('Window picker chỉ áp dụng cho chế độ Cửa sổ riêng.');
    else openOverlay('#dialogOverlay');
  });
  // **Uỷ quyền** sự kiện: các nút giờ do `renderWindowOptions` sinh ra sau khi
  // có dữ liệu, nên gắn listener lúc load sẽ không bao giờ chạy.
  $('#windowOptions')?.addEventListener('click', event => {
    const btn = event.target.closest('.window-option');
    if (!btn) return;
    state.selectedWindow = btn.dataset.window;
    $$('.window-option').forEach(option => option.classList.toggle('selected', option === btn));
  });
  $('#dialogConfirm').addEventListener('click', () => {
    // §6.11.1: cùng một nút, hai ý nghĩa khác nhau tuỳ overlay đang hỏi gì.
    // Không kiểm thì bấm "Tiếp tục" sẽ **đồng thời** chọn cửa sổ giả: hai
    // handler chạy, và người dùng thấy toast "Đã chọn: …" sau khi nối lại
    // phiên — sai và khó hiểu.
    if ($('#dialogConfirm').dataset.action === 'resume') return;
    updateMockWindow();
    closeOverlay('#dialogOverlay');
    toast(`Đã chọn: ${labels[state.selectedWindow] || state.selectedWindow}.`);
  });
  $('#dialogClose').addEventListener('click', () => closeOverlay('#dialogOverlay'));
  $('#dialogCancel').addEventListener('click', () => {
    // Hộp "Tiếp tục phiên" dùng chung overlay: trả `action` về rỗng khi huỷ,
    // nếu không nút "Chọn cửa sổ" ở lần sau sẽ im lặng không làm gì.
    delete $('#dialogConfirm').dataset.action;
    closeOverlay('#dialogOverlay');
  });

  $('#roomViewBtn').addEventListener('click', () => {
    state.room = !state.room;
    setToggle($('#roomToggle'), state.room);
    $('#roomPanel').classList.toggle('hidden', !state.room);
    toast(state.room ? 'Đã mở khung xem phòng mô phỏng.' : 'Đã đóng khung xem phòng.');
  });
  $('#audioBtn').addEventListener('click', () => {
    state.audio = !state.audio;
    setToggle($('#audioToggle'), state.audio);
    toast(state.audio ? 'Âm thanh mô phỏng đã bật.' : 'Âm thanh mô phỏng đã tắt.');
  });
  function syncQuickVolume(value) {
    const volume = Math.max(0, Math.min(100, Number(value) || 0));
    $('#audioVolume').value = String(volume);
    $('#audioVolumeValue').value = `${volume}%`;
    $('#audioVolumeValue').textContent = `${volume}%`;
  }
  $('#audioVolume').addEventListener('input', event => syncQuickVolume(event.currentTarget.value));
  $('#audioVolume').addEventListener('change', event => saveSetting('volume', Number(event.currentTarget.value)));
  $('#micBtn').addEventListener('click', () => {
    state.mic = !state.mic;
    setToggle($('#micToggle'), state.mic);
    toast(state.mic ? 'Micro mô phỏng đã bật — chưa thu âm thật.' : 'Micro mô phỏng đã tắt.');
  });
  // §41.4 T5 — output của probe là dữ liệu từ MÁY THẬT (Get-PnpDevice, tên app,
  // driver, tên Wi-Fi) và có thể chứa bất kỳ ký tự nào. Nó KHÔNG được đi qua
  // innerHTML: mọi thứ ở đây tạo bằng createElement + textContent. Đổi dòng này
  // thành template string là mở lại XSS, nên có test grep chặn (server.test.js).
  function renderDiagnostics(checks) {
    const list = $('#diagnosticsList');
    list.replaceChildren();
    for (const item of checks) {
      const row = document.createElement('div');
      row.className = 'diagnostic-row';

      const badge = document.createElement('span');
      const status = ['pass', 'fail', 'warn'].includes(item.status) ? item.status : 'warn';
      badge.className = `diagnostic-status ${status}`;
      badge.textContent = status === 'pass' ? '✓' : status === 'fail' ? '×' : '!';

      const copy = document.createElement('span');
      copy.className = 'diagnostic-copy';
      const title = document.createElement('b');
      title.textContent = String(item.title ?? '');
      const output = document.createElement('small');
      output.textContent = String(item.output || item.advice || '');
      copy.append(title, output);
      if (item.advice && item.output) {
        const advice = document.createElement('em');
        advice.textContent = String(item.advice);
        copy.append(advice);
      }

      row.append(badge, copy);
      list.append(row);
    }
  }
  let diagnosticsReport = null;
  $('#runDiagnostics').addEventListener('click', async () => {
    openOverlay('#diagnosticsOverlay');
    // Không nhắc GStreamer: chữ đó khiến người dùng đi cài một thứ app không
    // còn dùng (§58.15). Kiểm cái **thật sự** quyết định đường này.
    $('#diagnosticsIntro').textContent = 'Đang kiểm tra Windows, adapter đồ hoạ và display driver…';
    $('#diagnosticsList').innerHTML = '<div class="diagnostic-row"><span class="diagnostic-status pending">…</span><span>Đang chạy các phép kiểm tra chỉ đọc</span></div>';
    $('#captureResult').classList.add('hidden');
    $('#captureProbe').disabled = true;
    try {
      diagnosticsReport = await apiRequest('/api/diagnostics');
      if (diagnosticsReport.mock) {
        $('#diagnosticsIntro').textContent = 'Preview UI không có quyền đọc phần cứng. Dùng exe Windows để chạy probe thật.';
        renderDiagnostics([{ status: 'warn', title: 'Chẩn đoán phần cứng chỉ có trong Lantern mock exe.' }]);
        $('#captureProbe').disabled = true;
      } else {
        const checks = diagnosticsReport.checks || [];
        const pass = checks.filter(item => item.status === 'pass').length;
        $('#diagnosticsIntro').textContent = `${pass}/${checks.length} kiểm tra đạt. Không có thay đổi hệ thống nào được thực hiện.`;
        renderDiagnostics(checks);
        $('#captureProbe').disabled = false;
      }
    } catch { $('#diagnosticsIntro').textContent = 'Không nhận được báo cáo. Hãy chạy standalone Lantern mock exe trên Windows.'; $('#diagnosticsList').replaceChildren(); }
  });
  $('#diagnosticsClose').addEventListener('click', () => closeOverlay('#diagnosticsOverlay'));
  $('#diagnosticsDone').addEventListener('click', () => closeOverlay('#diagnosticsOverlay'));
  $('#captureProbe').addEventListener('click', async () => {
    const button = $('#captureProbe');
    if (!diagnosticsReport || diagnosticsReport.mock) {
      $('#captureResult').classList.remove('hidden');
      $('#captureResult').textContent = 'Chạy kiểm tra máy thật trước; probe capture chỉ khả dụng trong Windows exe.';
      button.disabled = true;
      return;
    }
    button.disabled = true; button.textContent = 'Đang capture…';
    $('#captureResult').classList.remove('hidden'); $('#captureResult').textContent = 'Mở preview DXGI 5 giây, sau đó thử QSV 1080p60…';
    try {
      const result = await apiRequest('/api/diagnostics/capture', { method: 'POST', body: { monitorIndex: Number($('#monitorIndex').value) } });
      diagnosticsReport.capture = result;
      $('#captureResult').textContent = `${result.status === 'pass' ? 'PASS' : 'WARN'} · ${result.output || result.advice || 'Không có chi tiết.'}`;
    } catch (error) { $('#captureResult').textContent = `Không chạy được: ${error.message}`; }
    finally { button.disabled = false; button.textContent = 'Chạy 5 giây'; }
  });
  $('#downloadReport').addEventListener('click', () => {
    if (!diagnosticsReport) return;
    const blob = new Blob([JSON.stringify(diagnosticsReport, null, 2)], { type: 'application/json' });
    const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = 'lantern-p0-report.json'; link.click(); URL.revokeObjectURL(link.href);
  });
  $('#settingsOpen').addEventListener('click', () => openOverlay('#settingsOverlay'));
  $('#settingsMini').addEventListener('click', () => openOverlay('#settingsOverlay'));
  $('#settingsClose').addEventListener('click', () => closeOverlay('#settingsOverlay'));
  $('#settingsDone').addEventListener('click', () => closeOverlay('#settingsOverlay'));
  function renderSettings() {
    const query = $('#settingsSearch').value.trim().toLocaleLowerCase();
    const source = settingsGroup === 'advanced' ? advancedDefs : settingsGroup === 'all' && query ? allSettingDefs : settingDefs;
    const rows = source.filter(def => (settingsGroup === 'all' || settingsGroup === 'advanced' || def.group === settingsGroup) && (!query || `${def.title} ${def.hint} ${def.terms}`.toLocaleLowerCase().includes(query)));
    let previousSection = '';
    $('#settingsItems').innerHTML = rows.length ? rows.map(def => {
      const sectionHeading = def.section && def.section !== previousSection ? `<h4 class="advanced-section">${def.section}</h4>` : '';
      previousSection = def.section || '';
      const value = settings[def.id];
      let control;
      if (def.range) control = `<div class="range-control"><input type="range" min="0" max="100" step="5" value="${value}" data-setting="${def.id}" aria-label="${def.title}"><b>${value}%</b></div>`;
      else if (def.toggle) control = `<button class="toggle-setting ${value ? 'on' : ''}" data-setting="${def.id}" aria-pressed="${value}" aria-label="${def.title}"><i></i></button>`;
      else control = `<select data-setting="${def.id}" aria-label="${def.title}">${def.options.map(([key,label]) => `<option value="${key}" ${key===value?'selected':''}>${label}</option>`).join('')}</select>`;
      const valLabel = def.options && def.options.find(o => o[0] === value)?.[1];
      const override = def.scope === 'device' ? '<button class="override-reset" data-reset="'+def.id+'" title="Bỏ tuỳ chỉnh riêng cho thiết bị này">Dùng chung</button>' : '';
      return `${sectionHeading}<div class="setting-row" data-setting-row="${def.id}"><span class="setting-copy"><b>${def.title}</b><small>${def.hint}</small><em>${def.scope === 'device' ? 'Riêng thiết bị này' : def.scope === 'server' ? 'Thiết lập máy chủ' : 'Nâng cao'} · ${def.effect === 'Khởi động lại' ? 'cần khởi động lại' : def.effect === 'Phiên sau' ? 'áp dụng từ phiên sau' : 'áp dụng ngay'}</em></span><div class="setting-control">${control}${override}</div></div>`;
    }).join('') : '<div class="settings-empty">Không tìm thấy cài đặt phù hợp. Thử “mờ”, “trễ” hoặc “tiếng”.</div>';
    const total = settingsGroup === 'advanced' ? '20' : settingsGroup === 'all' && !query ? '12' : `${rows.length}`;
    $('[data-settings-group="all"] span').textContent = total;
    $$('#settingsItems [data-setting]').forEach(control => {
      const eventName = control.tagName === 'BUTTON' ? 'click' : control.type === 'range' ? 'change' : 'change';
      control.addEventListener(eventName, event => {
        if (control.tagName === 'BUTTON') event.preventDefault();
        saveSetting(control.dataset.setting, control.tagName === 'BUTTON' ? !settings[control.dataset.setting] : control.type === 'range' ? Number(control.value) : control.value);
      });
    });
    $$('#settingsItems [data-reset]').forEach(button => button.addEventListener('click', () => saveSetting(button.dataset.reset, settingDefaults[button.dataset.reset])));
  }
  function saveSetting(id, value) {
    settings[id] = value;
    try { localStorage.setItem('lantern-mock-settings', JSON.stringify(settings)); } catch {}
    apiRequest('/api/settings', { method: 'PATCH', body: { [id]: value } }).catch(() => {});
    $('#settingsSaved').textContent = 'Đã lưu trên thiết bị này';
    if (id === 'quality') {
      $('.quality-indicator').innerHTML = `<i></i> ${value === 'sharp' ? 'Nét' : value === 'smooth' ? 'Mượt' : 'HD'}`;
      state.quality = value;
    }
    if (id === 'volume') { syncQuickVolume(value); toast(`Âm lượng nghe: ${value}%.`); }
    if (id === 'audio') { state.audio = value !== 'off'; setToggle($('#audioToggle'), state.audio); }
    if (id === 'cursor-mode') { state.cursor = value !== 'local'; $('#cursorPointer').classList.toggle('hidden', !state.connected || !state.cursor); }
    if (id === 'hide-taskbar') $('.desktop-taskbar').classList.toggle('hidden', Boolean(value));
    if (id === 'theme') document.body.dataset.theme = value;
    if (id === 'display') $('#screenResolution').textContent = `${value === 'large-text' ? 'Chữ to' : value === 'comfortable' ? 'Vừa mắt' : value === 'sharp' ? 'Nét' : '1920 × 1080'} · demo`;
    if (id === 'aspect') {
      $('#mockDesktop').dataset.aspect = value;
      // §6.10.3: khung hình **live** là thứ người dùng thật sự nhìn. Đổi setting
      // mà chỉ áp lên desktop giả nghĩa là bấm không thấy gì xảy ra.
      $('#liveView').dataset.aspect = value;
    }
    if (id === 'touch') $('#mockDesktop').dataset.touch = value;
    renderSettings();
    const changed = allSettingDefs.find(def => def.id === id);
    if (changed?.effect === 'Phiên sau') toast('Đã lưu — áp dụng từ phiên sau.');
    else if (changed?.effect === 'Khởi động lại') toast('Đã lưu — cần khởi động lại dịch vụ để áp dụng.');
    else if (advancedDefs.includes(changed)) toast(`Đã lưu: ${changed.title}.`);
  }
  $('#settingsSearch').addEventListener('input', renderSettings);
  $$('.settings-nav button').forEach(button => button.addEventListener('click', () => {
    settingsGroup = button.dataset.settingsGroup;
    $$('.settings-nav button').forEach(item => item.classList.toggle('selected', item === button));
    renderSettings();
  }));
  $('#resetSettings').addEventListener('click', () => {
    settings = { ...settingDefaults };
    try { localStorage.removeItem('lantern-mock-settings'); } catch {}
    state.audio = true; state.cursor = true;
    setToggle($('#audioToggle'), true);
    syncQuickVolume(settingDefaults.volume);
    document.body.dataset.theme = 'light';
    $('.desktop-taskbar').classList.remove('hidden');
    // Không đặt lại số bịa khi khôi phục mặc định — chỗ này từng ghi
    // "1080p · 30 FPS (demo)" và người dùng đọc thành số đo thật.
    renderMetrics();
    $('#settingsSearch').value = ''; settingsGroup = 'all';
    $$('.settings-nav button').forEach(item => item.classList.toggle('selected', item.dataset.settingsGroup === 'all'));
    renderSettings();
    toast('Đã khôi phục cài đặt mặc định.');
  });
  renderSettings();
  state.audio = settings.audio !== 'off';
  setToggle($('#audioToggle'), state.audio);
  syncQuickVolume(settings.volume);
  state.cursor = settings['cursor-mode'] !== 'local';
  $('.desktop-taskbar').classList.toggle('hidden', Boolean(settings['hide-taskbar']));
  document.body.dataset.theme = settings.theme;
  $('.quality-indicator').innerHTML = `<i></i> ${settings.quality === 'sharp' ? 'Nét' : settings.quality === 'smooth' ? 'Mượt' : 'HD'}`;
  $('#screenResolution').textContent = `${settings.display === 'large-text' ? 'Chữ to' : settings.display === 'comfortable' ? 'Vừa mắt' : settings.display === 'sharp' ? 'Nét' : '1920 × 1080'} · demo`;
  $('#mockDesktop').dataset.aspect = settings.aspect;
  $('#liveView').dataset.aspect = settings.aspect;
  $('#mockDesktop').dataset.touch = settings.touch;
  async function hydrateMockApi() {
    // Nút "Xem máy thật" mặc định ẩn. Chỉ hiện khi **cả hai** đúng: server này có
    // đường live (bản exe Windows, không phải `npm run mock`) VÀ máy có GStreamer
    // + plugin d3d11. Nếu không, nút sẽ là một cái bẫy bấm-vào-rồi-lỗi.
    refreshLiveStatus();
    try {
      const [health, stored, device, windows, current] = await Promise.all([
        apiRequest('/api/health'), apiRequest('/api/settings'), apiRequest('/api/device'), apiRequest('/api/windows'), apiRequest('/api/sessions/current')
      ]);
      settings = { ...stored.settings, ...settings };
      syncQuickVolume(settings.volume);
      try { localStorage.setItem('lantern-mock-settings', JSON.stringify(settings)); } catch {}
      renderSettings();
      state.audio = settings.audio !== 'off'; state.cursor = settings['cursor-mode'] !== 'local';
      setToggle($('#audioToggle'), state.audio);
      $('.desktop-taskbar').classList.toggle('hidden', Boolean(settings['hide-taskbar']));
      document.body.dataset.theme = settings.theme;
      $('.quality-indicator').innerHTML = `<i></i> ${settings.quality === 'sharp' ? 'Nét' : settings.quality === 'smooth' ? 'Mượt' : 'HD'}`;
      $('#screenResolution').textContent = `${settings.display === 'large-text' ? 'Chữ to' : settings.display === 'comfortable' ? 'Vừa mắt' : settings.display === 'sharp' ? 'Nét' : '1920 × 1080'} · demo`;
      $('#connectHint').textContent = `${device.name} · mock backend sẵn sàng · không truy cập máy thật`;
      $('.demo-pill').innerHTML = '<i></i> MOCK API · ONLINE';
      // Schema của §8.1 là `wid`, không phải `id` — bản trước đọc `win.id` nên
      // luôn thấy `undefined` và rơi về 'desktop', tức là **window picker
      // không bao giờ hoạt động** dù server trả đúng.
      windowSnapshot = windows.snapshotId || '';
      realWindows = (windows.windows || []).filter(win => win && win.wid);
      for (const win of realWindows) labels[win.wid] = win.title || win.app || win.wid;
      const validWindowIds = new Set(['desktop', ...realWindows.map(win => win.wid)]);
      if (!validWindowIds.has(state.selectedWindow)) state.selectedWindow = 'desktop';
      renderWindowOptions();
      if (windows.note) {
        // §58.3: nếu danh sách rỗng vì lý do nền tảng, **nói** thay vì để
        // người dùng tưởng máy không có app nào đang mở.
        const hint = $('#windowPickerHint');
        if (hint) hint.textContent = realWindows.length === 0 ? windows.note : '';
      }
      if (current.session) {
        currentSessionId = current.session.id;
        state.mode = current.session.mode;
        state.selectedWindow = current.session.windowId;
        syncMode(); updateMockWindow(); setConnected(true, false);
      }
      // §58: trên bản thật, **màn hình phải là màn hình thật ngay khi mở trang**.
      //
      // Trước bản này, trang mở ra với một desktop giả vẽ bằng CSS — người dùng
      // đang chạy exe trên chính máy đó nhưng thấy một cửa sổ Explorer giả, và
      // phải đi tìm một nút nhỏ ở góc mới thấy được màn hình của mình. Không có
      // lý do nào để bản thật lại mặc định hiện thứ giả.
      if (nativeApp && health.capture !== 'none') {
        startLive().catch(() => {});
      }
      document.documentElement.dataset.api = health.ok ? 'online' : 'offline';
      // §58: server nói nó là bản gì. `native` ⇒ trang này là app thật, và mọi
      // nhãn "demo/mô phỏng" phải biến mất — chúng nói sai về sản phẩm đang
      // chạy và khiến người dùng không dám bấm.
      nativeApp = health.mode === 'native';
      document.documentElement.dataset.native = nativeApp ? 'true' : 'false';
      if (nativeApp) applyNativeLabels();
    } catch {
      $('.demo-pill').innerHTML = '<i></i> LOCAL MOCK';
      document.documentElement.dataset.api = 'offline';
    }
  }
  hydrateMockApi();
  $('#fullscreenBtn').addEventListener('click', async () => {
    try {
      if (!document.fullscreenElement) await $('#screenFrame').requestFullscreen();
      else await document.exitFullscreen();
    } catch { toast('Trình duyệt không cho phép phóng to tại đây.'); }
  });
  $('#mockDesktop').addEventListener('pointermove', event => {
    if (!state.connected || !state.cursor) return;
    const rect = event.currentTarget.getBoundingClientRect();
    $('#cursorPointer').style.left = `${Math.max(4, Math.min(96, (event.clientX - rect.left) / rect.width * 100))}%`;
    $('#cursorPointer').style.top = `${Math.max(4, Math.min(90, (event.clientY - rect.top) / rect.height * 100))}%`;
  });
  $('#liveBtn').addEventListener('click', toggleLive);
  // # Dòng chết đã xoá: `$('#liveInstall').addEventListener('click', installGstreamer)`
  //
  // Cả `#liveInstall` lẫn `installGstreamer` **không tồn tại** ở đâu trong repo
  // (đã grep). `$('#liveInstall')` trả `null` ⇒ `.addEventListener` ném
  // `TypeError` ngay lúc chạy ⇒ **mọi dòng sau nó không được thực thi**.
  //
  // Đó là lý do một loạt tính năng "đã viết xong" không có tác dụng trong trình
  // duyệt: handler của chúng nằm sau dòng này. Không test tĩnh nào bắt được —
  // `node --check` chỉ kiểm cú pháp, và chuỗi `#liveInstall` là hợp lệ.
  // §58.15 đã bỏ GStreamer, nên nút cài đó không còn lý do tồn tại.
  /**
   * §50.1 #6 (P2) — chế độ "mạng rất yếu": **1 fps, chỉ bàn phím**.
   *
   * # Vì sao tắt chuột chứ không chỉ hạ fps
   *
   * Ở 1 fps, hình cập nhật mỗi giây một lần. Bấm chuột bằng **ảnh cũ** là bấm
   * vào chỗ một giây trước nút đó nằm ở đâu — thao tác nguy hiểm hơn không làm
   * gì. Bàn phím thì khác: gõ chữ không phụ thuộc việc bạn thấy con trỏ ở đâu.
   * Spec ghi đúng cặp đó: *"1 fps + chỉ bàn phím"*.
   *
   * # Không đổi lựa chọn của người dùng
   *
   * Dùng `live.weakNet` như `live.hiddenFps`: slider fps phải giữ nguyên giá trị
   * người dùng chọn, nếu không tắt chế độ yếu xong thì FPS của họ đã bị đổi mà
   * không biết.
   */
  async function setWeakNet(enabled) {
    live.weakNet = enabled;
    const button = $('#liveWeakNet');
    button.setAttribute('aria-pressed', enabled ? 'true' : 'false');
    button.classList.toggle('on', enabled);

    if (liveController) {
      // §50.1 #6: chỉ bàn phím ⇒ tắt đường chuột của **cùng** controller, không
      // tạo controller thứ hai (hai controller cùng gửi input là hai nguồn sự
      // thật, và `releaseAll` của cái này không biết cái kia đang giữ gì).
      liveController.setPointerEnabled(!enabled);
    }

    if (!live.active) return;
    // Đổi fps ⇒ mở lại response với fps mới. `dataset.src` phải cập nhật cùng
    // lúc, nếu không `renderLive` tưởng chưa đổi.
    const img = $('#liveImage');
    const url = liveUrl();
    img.dataset.src = url;
    img.src = url;
    $('#liveMeta').textContent = enabled
      ? 'Mạng rất yếu · 1 fps · chỉ bàn phím (chuột tắt để không bấm nhầm vào ảnh cũ)'
      : `MJPEG thật · màn hình ${live.monitor} · tối đa ${live.fps} fps · bấm để điều khiển · không có tiếng`;
  }

  /**
   * §50.4 — tiêu đề tab = tên cửa sổ đang xem; favicon đổi màu theo trạng thái.
   *
   * # Vì sao đáng làm dù chỉ vài dòng
   *
   * Mở 5 tab (workspace, `/live`, tài liệu, tab của tab…) thì "Lantern" ở cả 5
   * không nói được tab nào là cái đang xem màn hình. Và khi phiên đứt, tab bar là
   * chỗ **duy nhất** người dùng còn nhìn — nếu họ đang ở tab khác.
   *
   * Favicon vẽ bằng SVG inline (`data:`), không phải file `.ico`: một asset nữa
   * là một route nữa là một chỗ có thể 404 im lặng (§58.15 bài học).
   */
  const FAVICON_COLOURS = {
    idle: '#8b9a92',    // xám: chưa có phiên
    live: '#3fa06a',    // xanh: đang xem máy thật
    error: '#d0453e',   // đỏ: mất kết nối / lỗi
  };

  function setFavicon(stateName) {
    const colour = FAVICON_COLOURS[stateName] || FAVICON_COLOURS.idle;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">`
      + `<rect width="32" height="32" rx="7" fill="${colour}"/>`
      + `<rect x="8" y="10" width="16" height="10" rx="1.5" fill="#fff"/>`
      + `<rect x="13" y="21" width="6" height="2" fill="#fff"/></svg>`;
    let link = document.querySelector('link[rel="icon"]');
    if (!link) {
      link = document.createElement('link');
      link.rel = 'icon';
      document.head.appendChild(link);
    }
    // `encodeURIComponent` chứ không base64: SVG đọc được khi mở devtools, và
    // không có rủi ro encoding của base64 với ký tự UTF-8 trong tương lai.
    link.href = `data:image/svg+xml,${encodeURIComponent(svg)}`;
  }

  /**
   * §50.4: tiêu đề tab nói **đang xem cửa sổ nào**.
   *
   * Bỏ tên app dài dòng khi chưa có phiên: tab bar cắt còn 20 ký tự, nên phần
   * đầu phải là thứ phân biệt được, không phải "Lantern — Điều khiển từ xa".
   */
  function setTabTitle(active) {
    if (!active) {
      document.title = 'Lantern';
      setFavicon('idle');
      return;
    }
    const picked = (realWindows || []).find(win => win.wid === state.selectedWindow);
    const where = !picked
      ? (state.selectedWindow === 'desktop' ? 'Toàn màn hình' : state.selectedWindow)
      : (picked.title || picked.app || picked.wid);
    // Cắt tên cửa sổ: tiêu đề tab dài bị cắt từ **cuối**, nên tên app ở cuối
    // biến mất trước — đúng phần ít thông tin hơn.
    const short = where.length > 40 ? `${where.slice(0, 39)}…` : where;
    document.title = `${short} · Lantern`;
    setFavicon(live.active ? 'live' : 'idle');
  }

  /**
   * §6.4.6 — nút "chuột tương đối (game)".
   *
   * Bật ⇒ xin pointer lock trên **khung hình**. Trình duyệt chỉ cho xin trong
   * một gesture, nên phải gọi ngay trong handler click — không `await` gì trước.
   *
   * Nhãn trạng thái đổi qua `controller.onLockChange` chứ không phải sau khi gọi
   * `requestPointerLock()`: hàm đó **trả về trước** khi lock được cấp, và có thể
   * bị từ chối. Đặt nhãn theo kết quả thật, không theo ý định.
   */
  $('#liveRelative').addEventListener('click', () => {
    if (!liveController) {
      toast('Bật "Xem máy thật" trước, rồi bấm lại.');
      return;
    }
    if (liveController.locked) {
      liveController.exitRelativePointer();
      return;
    }
    const started = liveController.requestRelativePointer();
    if (!started) {
      // Nói rõ vì sao: Safari/Firefox cũ không hỗ trợ, và iOS **không có** —
      // spec ghi đúng điều đó (§6.4.6: "iOS: không có, dùng touch mode").
      toast('Trình duyệt này không hỗ trợ chuột tương đối. Trên điện thoại hãy dùng chạm.');
    }
  });

  function renderRelativeLock(locked) {
    const button = $('#liveRelative');
    if (!button) return;
    button.setAttribute('aria-pressed', locked ? 'true' : 'false');
    button.classList.toggle('on', locked);
    if (locked) {
      toast('Chuột tương đối đang bật. Bấm Esc để thoát.');
    }
  }

  $('#liveWeakNet').addEventListener('click', () => {
    setWeakNet(!live.weakNet).catch(() => {});
  });

  $('#liveFullscreen').addEventListener('click', async () => {
    try {
      if (!document.fullscreenElement) await $('#screenFrame').requestFullscreen();
      else await document.exitFullscreen();
    } catch { toast('Trình duyệt không cho phép phóng to tại đây.'); }
  });
  $('#liveOpen').addEventListener('click', () => {
    // Mở tab riêng: trên điện thoại đây là đường ngắn nhất để "nhìn thấy nhà".
    window.open(`/live?monitor=${live.monitor}&fps=${live.fps}`, '_blank', 'noopener');
  });
  $('#liveMonitor').addEventListener('change', event => {
    live.monitor = Math.max(0, Math.min(8, Number(event.target.value) || 0));
    renderLive();
  });
  $('#liveFps').addEventListener('change', event => {
    live.fps = Math.max(1, Math.min(30, Number(event.target.value) || 15));
    renderLive();
  });
  /**
   * §50.1 #4 (P1) + §6.11.2 — "Tab ẩn >10 s ⇒ server hạ 5 fps" và **không kẹt
   * phím** khi rời tab.
   *
   * # Vì sao `visibilitychange` chứ không chỉ `blur`
   *
   * `blur` bắn khi **cửa sổ** mất focus — trên desktop, bấm sang app khác.
   * Nhưng trên **điện thoại**, chuyển sang Zalo rồi quay lại **không** làm mất
   * focus theo cách đó: trang chỉ chuyển sang hidden. Không có `visibilitychange`
   * thì phím đang giữ (Ctrl, Shift, một phím chữ) **ở lại trạng thái down** trên
   * máy thật. Người dùng quay lại, gõ một chữ, và nhận Ctrl+chữ — đúng bug
   * §50.1 #4 mô tả: *"phải **không** mất phiên và **không** kẹt phím"*.
   *
   * # Vì sao hạ fps thay vì dừng
   *
   * Spec §6.11.2: *"Tab ẩn >10 s | server giảm 60→5 fps, **giữ** kết nối"*.
   * Dừng hẳn thì quay lại phải nạp lại stream từ đầu (mất vài giây, và với
   * MJPEG là mở HTTP response mới). Hạ fps giữ kết nối và ngừng đốt CPU.
   *
   * Độ trễ 10 s: người dùng chuyển tab **1 giây** để tra gì đó rồi quay lại thì
   * không nên thấy hình đổi độ mượt. Đây đúng con số spec ghi.
   */
  const HIDDEN_DELAY_MS = 10_000;
  let hiddenTimer = null;

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      // Nhả phím/chuột **ngay**, không chờ 10 s: một phím giữ 10 giây trên máy
      // thật đã đủ để tự lặp (auto-repeat) và gõ vào cửa sổ người dùng đang mở.
      if (liveController) {
        try { liveController.releaseAll('hidden'); } catch { /* đã gỡ */ }
      }
      if (hiddenTimer) clearTimeout(hiddenTimer);
      hiddenTimer = setTimeout(() => {
        hiddenTimer = null;
        // Không kiểm `document.hidden` lần nữa: nếu người dùng đã quay lại thì
        // handler `else` bên dưới đã huỷ timer này.
        if (!live.active) return;
        live.hiddenFps = 5;
        // Đặt `src` mới **một lần**, không mỗi frame: đây là open lại response
        // với fps thấp hơn. `dataset.src` phải cập nhật cùng lúc, nếu không
        // `renderLive` tưởng chưa đổi và không làm gì.
        const img = $('#liveImage');
        const url = liveUrl();
        img.dataset.src = url;
        img.src = url;
      }, HIDDEN_DELAY_MS);
    } else {
      if (hiddenTimer) { clearTimeout(hiddenTimer); hiddenTimer = null; }
      if (!live.active) return;
      // Quay lại: khôi phục fps đã chọn. Nếu chưa bị hạ thì không làm gì —
      // không reload stream cho một lần chuyển tab 1 giây.
      if (live.hiddenFps) {
        live.hiddenFps = 0;
        const img = $('#liveImage');
        const url = liveUrl();
        img.dataset.src = url;
        img.src = url;
      }
    }
  });

  /**
   * §50.1 #3 — mất kết nối: **giữ ảnh cuối + đồng hồ "đã mất N giây"**.
   *
   * # Vì sao không tắt `live.active`
   *
   * Bản trước đặt `live.active = false` ngay khi `<img>` báo lỗi. Hệ quả: một
   * nhịp mạng mất 2 giây xoá **toàn bộ** khung hình và hiện màn hình trắng +
   * "Chưa bật xem máy thật" — người dùng tưởng app chết, bấm Start lại, và tự
   * tạo cho mình phiên thứ hai (hoặc nhận 409). Spec gọi đúng trạng thái này:
   * *"màn hình trắng + spinner làm bạn tưởng app chết; ảnh cuối + đồng hồ cho
   * biết **đang thử lại**, không phải đã chết"*.
   *
   * # Vì sao tự thử lại
   *
   * MJPEG là một HTTP response dài. Rớt Wi-Fi 3 giây thì response chết, nhưng
   * server vẫn chạy. Nạp lại `<img src>` là đủ để tiếp tục — không cần tạo
   * phiên mới. Chỉ báo thất bại thật khi đã thử quá `RECONNECT_GIVE_UP_MS`.
   */
  /**
   * §30.7 — bàn phím cho điện thoại: hàng chip sticky modifier + phần tử nhận
   * phím.
   *
   * # Vì sao có một `<textarea>` 1×1 px
   *
   * Bàn phím của hệ điều hành chỉ mở khi một phần tử **nhập được** có focus.
   * Khung hình là `<img>`, không nhập được. Nên cần một phần tử nhập thật, nhưng
   * nó phải **không chiếm layout** — nếu không nó đẩy video xuống, đúng thứ §30.7
   * cấm.
   *
   * Ta không lấy nội dung của `<textarea>`: mỗi `keydown` đi qua đường phím bình
   * thường (§6.5) và **chặn** ký tự mặc định, nên nó không bao giờ tích luỹ chữ.
   * Cách này đúng hơn đọc `value`: IME tiếng Việt tạo chuỗi nhiều bước, và đọc
   * `value` sẽ gửi cả cụm thay vì từng phím như bàn phím thật.
   */
  let chipModule = null;
  let chipController = null;
  let keyboardWatcher = null;

  async function attachChips() {
    if (!liveController || chipController) return;
    try {
      chipModule = chipModule || await import('/chip.js');
    } catch {
      // Server cũ: không có `/chip.js`. Chip không hoạt động, và đó là tất cả —
      // không được làm hỏng phần điều khiển chuột/bàn phím đã có.
      return;
    }
    const row = $('#chipRow');
    chipController = chipModule.attachChips(row, {
      send: (vk, down, mods) => {
        // Gửi qua **cùng** đường phím của `input.js` (§6.5): `{t:"key",down,vk,mods}`.
        // Không có đường thứ hai — hai đường là hai bộ luật.
        liveController?.sendKey?.(vk, down === 1, mods);
      },
    });
    row.classList.remove('hidden');

    // §30.7: video **co lại** khi bàn phím mở, không bị che.
    const view = $('#liveView');
    keyboardWatcher = chipModule.watchKeyboard(
      typeof window !== 'undefined' ? window.visualViewport : null,
      (inset) => view.style.setProperty('--keyboard-inset', `${inset}px`),
    );
  }

  function detachChips() {
    if (chipController) {
      // Nhả modifier trước khi gỡ: Ctrl "khoá" còn sống qua lần mở sau là Ctrl
      // vô hình đang bật, và người dùng không hiểu vì sao gõ chữ ra lệnh.
      chipController.reset();
      chipController.detach();
      chipController = null;
    }
    if (keyboardWatcher) { keyboardWatcher(); keyboardWatcher = null; }
    $('#chipRow')?.classList.add('hidden');
  }

  /**
   * §30.7: mở bàn phím HĐH. Chỉ gọi **từ một gesture** — trình duyệt chặn
   * `focus()` ngoài gesture, và trên iOS nó im lặng không mở.
   */
  function openKeyboard() {
    const sink = $('#keyboardSink');
    if (!sink) return false;
    try {
      sink.focus({ preventScroll: true });
      return document.activeElement === sink;
    } catch {
      return false;
    }
  }

  function closeKeyboard() {
    // Nhả modifier **trước** khi mất focus: nếu không, `ChipState` còn Ctrl và
    // lần mở bàn phím sau gõ chữ đầu tiên ra lệnh.
    chipController?.reset();
    const sink = $('#keyboardSink');
    if (sink) sink.blur();
  }

  $('#chipDone').addEventListener('click', () => closeKeyboard());
  // §30.7: *"Không tự đóng bàn phím khi chạm video (gây ức chế) — chỉ đóng khi
  // bấm Ẩn hoặc vuốt xuống."* Nên KHÔNG có handler đóng nào trên khung hình.
  // Mở thì có: chạm vào khung hình là mở để gõ.
  $('#liveImage').addEventListener('click', () => {
    if (!live.active || !liveController) return;
    openKeyboard();
  });

  // §50.1 #5: báo bằng tiếng/rung khi phiên bắt đầu và kết thúc. Nạp động và
  // **không** chặn render: tính năng báo hiệu không được làm chậm việc vẽ hình.
  let alertModule = null;
  const alertReady = () => {
    if (!alertModule) {
      alertModule = import('/alert.js').catch(() => null);
    }
    return alertModule;
  };
  /** `true` nếu đã báo được bằng tiếng hoặc rung. */
  async function announce(kind) {
    const module = await alertReady();
    if (!module) return false;
    try { return module.notify(kind); } catch { return false; }
  }
  // Trình duyệt chặn âm thanh tới khi có tương tác — mở khoá ở lần đầu.
  const primeAlert = () => {
    alertReady().then(module => { try { module?.prime(); } catch {} });
  };
  document.addEventListener('pointerdown', primeAlert, { once: true });
  document.addEventListener('keydown', primeAlert, { once: true });

  const RECONNECT_GIVE_UP_MS = 60_000;
  let reconnectTimer = null;
  let reconnectStartedAt = 0;

  function showReconnecting() {
    const banner = $('#liveReconnect');
    if (!banner) return;
    banner.classList.remove('hidden');
    const seconds = Math.max(0, Math.round((Date.now() - reconnectStartedAt) / 1000));
    // Đồng hồ là thứ **chứng minh** app còn sống. Không có nó, một ảnh đứng
    // yên và một app treo trông giống hệt nhau.
    banner.textContent = `Mất hình ${seconds} giây — đang thử lại…`;
  }

  $('#liveImage').addEventListener('error', () => {
    if (!live.active) return;
    // `dataset.src` đang được đặt ⇒ ảnh lỗi ngay lần đầu, tức là stream **chưa
    // từng** chạy (thiếu quyền, không capture được). Trường hợp này phải báo
    // ngay bằng lý do thật, không đếm ngược 60 giây cho một thứ sẽ không bao
    // giờ thành công.
    if (!live.firstFrameSeen) {
      live.active = false;
      renderLive();
      toast('Không xem được màn hình thật. Mở bảng chẩn đoán để xem lý do cụ thể.');
      return;
    }
    if (!reconnectStartedAt) reconnectStartedAt = Date.now();
    showReconnecting();
    // §50.4: đỏ ở tab bar **trước** khi hết 60 giây — đây là tín hiệu sớm nhất
    // mà người dùng ở tab khác nhận được.
    setFavicon('error');
    if (reconnectTimer) return;
    reconnectTimer = setInterval(() => {
      if (!live.active) { clearInterval(reconnectTimer); reconnectTimer = null; return; }
      showReconnecting();
      if (Date.now() - reconnectStartedAt > RECONNECT_GIVE_UP_MS) {
        clearInterval(reconnectTimer);
        reconnectTimer = null;
        reconnectStartedAt = 0;
        live.active = false;
        renderLive();
        // §50.1 #5: đây là trường hợp chuông **quan trọng nhất** — phiên đứt
        // trong khi người dùng đã rời màn hình. Báo tiếng trước, rồi toast:
        // người dùng có thể không ở tab này để đọc toast.
        announce('end').catch(() => {});
        toast('Mất hình quá 60 giây. Bấm "Xem máy thật" để thử lại.');
        return;
      }
      // `cache-bust`: cùng URL thì trình duyệt có thể dùng response đã chết
      // trong cache thay vì mở kết nối mới.
      const img = $('#liveImage');
      if (img) img.src = `${liveUrl()}&r=${Date.now()}`;
    }, 1000);
  });

  // §50.1 #3: ảnh cuối hiện lại ⇒ tắt banner và xoá đồng hồ. Không làm thì
  // banner "đang thử lại" nằm trên hình đang chạy bình thường.
  $('#liveImage').addEventListener('load', () => {
    live.firstFrameSeen = true;
    if (reconnectTimer) { clearInterval(reconnectTimer); reconnectTimer = null; }
    reconnectStartedAt = 0;
    $('#liveReconnect')?.classList.add('hidden');
  });
  /**
   * §6.11.1 — "Tiếp tục phiên đang mở?" sau khi tải lại trang.
   *
   * # Vấn đề thật
   *
   * Phiên nằm ở **server**, không ở tab. F5 (hoặc đóng tab nhầm, hoặc tab
   * crash) làm mất toàn bộ trạng thái client trong khi server vẫn đang chạy
   * phiên. Người dùng thấy "Chưa kết nối", bấm Start, và nhận
   * `409 session_already_active` — hoặc tệ hơn, phải đi tìm cách tắt phiên cũ
   * mà UI không có nút đó.
   *
   * Spec nói rõ: **hỏi** "Tiếp tục phiên đang mở? [Tiếp tục] [Huỷ]", không tự
   * chiếm lại. Lý do: phiên cũ có thể đang được tab khác dùng thật; tự động
   * chiếm sẽ đá người đang xem ra mà không nói gì.
   *
   * Chỉ chạy khi **đã đăng nhập** — trước đó request trả 401 và hộp hỏi sẽ
   * hiện lên trên màn hình khoá, che mất form đăng nhập.
   */
  async function offerResume() {
    let sessions;
    try {
      const data = await apiRequest('/api/sessions/mine');
      sessions = data.sessions || [];
    } catch {
      return; // chưa đăng nhập, hoặc server cũ: không có gì để tiếp tục
    }
    if (!sessions.length || state.connected) return;
    const session = sessions[0];
    // Không có `sid` thì không tiếp tục được — bỏ qua thay vì hỏi rồi lỗi.
    if (!session.id) return;

    const title = $('#dialogTitle');
    const body = $('#dialogDescription');
    const confirm = $('#dialogConfirm');
    if (!title || !body || !confirm) return;

    // Nói rõ **cửa sổ nào** đang được chia sẻ: người dùng cần biết mình sắp mở
    // lại thứ gì trước khi đồng ý, nhất là khi phiên được tạo từ thiết bị khác.
    //
    // Trường thật của `session_json` là `windowId` (đã kiểm bằng curl); bản đầu
    // của đoạn này đọc `windowTitle`/`window` — hai tên **không tồn tại** — nên
    // hộp hỏi luôn nói "màn hình" kể cả khi phiên đang chia sẻ một cửa sổ cụ
    // thể. Một `||` nối ba tên đoán là ba cơ hội để nói sai.
    const where = session.windowId === 'desktop' || !session.windowId
      ? 'toàn màn hình'
      : `cửa sổ ${session.windowId}`;
    title.textContent = 'Tiếp tục phiên đang mở?';
    body.textContent = `Máy vẫn đang chia sẻ ${where} từ một tab khác hoặc từ trước khi tải lại trang. Tiếp tục để dùng lại phiên đó, hoặc huỷ và tạo phiên mới.`;
    confirm.textContent = 'Tiếp tục';
    confirm.dataset.action = 'resume';
    openOverlay('#dialogOverlay');

    const resume = async () => {
      confirm.removeEventListener('click', resume);
      // Trả `action` về rỗng, nếu không thì **mọi** lần mở picker sau đó đều
      // bị handler cũ bỏ qua và nút "Chọn cửa sổ" không làm gì nữa.
      delete confirm.dataset.action;
      closeOverlay('#dialogOverlay');
      currentSessionId = session.id;
      // §6.11.1: giữ nguyên `sid`. Không tạo phiên mới — phiên cũ vẫn còn
      // capture đang chạy, tạo mới sẽ bị `409 session_already_active`.
      setConnected(true, false);
      $('#connectLabel').textContent = 'Kết thúc phiên';
      toast('Đã nối lại phiên đang mở.');
      try { await startLive(); } catch { /* stream có lỗi riêng của nó */ }
    };
    confirm.addEventListener('click', resume);
  }

  // §7.1: chỉ hỏi sau khi mở khoá, không chồng lên màn hình đăng nhập.
  window.addEventListener('lantern:unlocked', () => { offerResume().catch(() => {}); }, { once: true });
  // Đã đăng nhập sẵn (cookie còn hạn) thì không có sự kiện nào bắn ra.
  if (!$('#authOverlay') || $('#authOverlay').classList.contains('hidden')) {
    offerResume().catch(() => {});
  }

  // §6.13 — `Ctrl+Alt+Del`: **không gửi được**, và phải nói thật.
  //
  // Windows chặn tổ hợp này từ Vista (SAS chỉ dành cho đường bảo mật của hệ
  // điều hành). `SendInput` gửi được ba phím đó nhưng Windows **bỏ qua** khi nó
  // tạo SAS — nên "giả vờ gửi" là nói dối đúng chỗ nguy hiểm: người dùng bấm
  // rồi chờ một màn hình khoá không bao giờ hiện.
  //
  // Spec nói: *"Ẩn phím; tooltip giải thích"*. Nút vẫn ở đó (không xoá: người
  // dùng cần biết **vì sao** thiếu), nhưng bấm vào thì giải thích, và nó không
  // giả vờ là đã gửi.
  $('#sendCtrlAltDel').addEventListener('click', () => toast(
    'Windows chặn Ctrl+Alt+Del từ Vista (Secure Attention Sequence). '
    + 'Muốn khoá máy: dùng nút Start trên máy thật, hoặc gửi Win+L (không bị chặn).'
  ));
  $('#blankScreen').addEventListener('click', () => toast('Màn hình riêng tư chưa được kết nối với máy thật.'));
  $('#helpBtn').addEventListener('click', () => toast('Bản mock tương tác: mọi thao tác chỉ thay đổi giao diện này.'));
  $('#aboutMock').addEventListener('click', () => toast('Chưa có truyền hình ảnh, camera, micro hay lệnh tới máy thật.'));
  $$('.nav-item').forEach(btn => btn.addEventListener('click', () => toast(`${btn.textContent.trim()} — mục này thuộc mock giao diện.`)));
  $$('.overlay').forEach(overlay => overlay.addEventListener('click', event => {
    if (event.target === overlay) closeOverlay(`#${overlay.id}`);
  }));
  document.addEventListener('keydown', event => {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      if ($('#settingsOverlay').classList.contains('hidden')) openOverlay('#settingsOverlay');
      $('#settingsSearch').focus();
    }
    if (event.key === 'Escape') {
      const top = $$('.overlay').find(el => !el.classList.contains('hidden'));
      if (top) closeOverlay(`#${top.id}`);
    }
  });
})();
