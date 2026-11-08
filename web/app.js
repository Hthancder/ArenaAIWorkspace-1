(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const state = { connected: false, mode: 'hvnc', room: false, audio: true, mic: false, selectedWindow: 'desktop', cursor: true, quality: 'balanced', resolution: '1080' };
  // §58: trạng thái của đường "xem màn hình thật" (MJPEG). Tách khỏi `state`
  // của phiên mock để không trộn hai thứ có vòng đời khác nhau.
  // `metrics` chỉ chứa số **đo được** từ server. `frames === 0` ⇒ hiện "—",
  // không ước lượng, không nội suy. Sai một lần nữa là mất lòng tin.
  const live = { active: false, monitor: 0, fps: 15, startedAt: 0, ready: false, metrics: { frames: 0 } };

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
      const response = await fetch('/api/live/status', { cache: 'no-store' });
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
  const labels = { desktop: 'Toàn bộ màn hình', browser: 'Trình duyệt', notes: 'Ghi chú' };
  let toastTimer;
  let currentSessionId = null;
  const apiRequest = async (path, options = {}) => {
    const response = await fetch(path, { ...options, headers: { ...(options.body ? { 'content-type': 'application/json' } : {}), ...options.headers }, body: options.body ? JSON.stringify(options.body) : undefined });
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
  function updateMockWindow() {
    const content = {
      desktop: ['Màn hình nền', 'Phiên demo đã sẵn sàng', 'Đây là hình ảnh minh hoạ — chưa truyền hình ảnh thật.'],
      browser: ['Google Chrome — Tab mới', 'Trình duyệt đã được chọn', 'Window picker cập nhật theo lựa chọn của bạn.'],
      notes: ['Ghi chú — Notepad', 'Ghi chú đang mở', 'Nội dung minh hoạ trong cửa sổ riêng.']
    }[state.selectedWindow];
    $('#windowLabel').textContent = labels[state.selectedWindow];
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
    return `/api/live.mjpg?monitor=${live.monitor}&fps=${live.fps}`;
  }
  function renderLive() {
    const img = $('#liveImage');
    const holder = $('#liveView');
    const empty = $('#liveEmpty');
    const frame = $('#screenFrame');
    holder.classList.toggle('hidden', !live.active);
    empty.classList.toggle('hidden', live.active);
    frame.classList.toggle('live', live.active);
    $('#mockDesktop').classList.toggle('hidden', live.active);
    $('#liveBtn').classList.toggle('on', live.active);
    $('#liveBar').classList.toggle('hidden', !live.active);
    $('#liveBtnLabel').textContent = live.active ? 'Dừng xem máy thật' : 'Xem máy thật';
    $('#liveMeta').textContent = live.active
      ? `MJPEG thật · màn hình ${live.monitor} · tối đa ${live.fps} fps · không có tiếng/điều khiển`
      : '';
    renderMetrics();
    if (live.active) {
      if (img.dataset.src !== liveUrl()) { img.dataset.src = liveUrl(); img.src = liveUrl(); }
    } else if (img.dataset.src) {
      // Bỏ `src` là cách duy nhất để trình duyệt **đóng kết nối** stream;
      // nếu chỉ ẩn ảnh thì pipeline vẫn chạy và vẫn nóng máy.
      img.removeAttribute('src');
      img.dataset.src = '';
    }
  }
  let metricsTimer = 0;
  function startMetricsPolling() {
    clearInterval(metricsTimer);
    metricsTimer = setInterval(refreshMetrics, 1000);
  }
  function stopMetricsPolling() {
    clearInterval(metricsTimer);
    metricsTimer = 0;
  }

  function stopLive(notify = false) {
    if (!live.active) return;
    live.active = false;
    stopMetricsPolling();
    live.metrics = { frames: 0 };
    renderLive();
    if (notify) toast('Đã dừng xem màn hình thật.');
  }
  // Hỏi server một chỗ duy nhất: nút có dùng được không, và nếu không thì vì sao.
  async function refreshLiveStatus() {
    try {
      const response = await fetch('/api/live/status');
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
    renderLive();
    toast(live.active
      ? 'Đang xem màn hình thật (MJPEG). Đóng tab hoặc bấm Dừng để tắt capture.'
      : 'Đã dừng xem màn hình thật.');
  }

  function setConnected(active, notify = true) {
    state.connected = active;
    $('#connectBtn').classList.toggle('connected', active);
    $('#connectLabel').textContent = active ? 'Kết thúc phiên demo' : 'Bắt đầu phiên demo (mô phỏng)';
    $('#connectHint').textContent = active ? 'Đang mô phỏng · dữ liệu không rời trình duyệt' : 'Mô phỏng cục bộ · không truy cập thiết bị thật';
    $('#screenState').textContent = active ? 'Phiên demo đang hoạt động' : 'Đang chờ phiên demo';
    $('#sessionStatus').textContent = active ? 'Đã kết nối · demo' : 'Chưa kết nối';
    $('#sessionSubstatus').textContent = active ? 'Thiết bị mô phỏng · vừa bắt đầu' : 'Bắt đầu để thử giao diện';
    // Không đặt số ở đây: `24 ms` / `2.4 Mbps` từng là hằng số viết cứng, hiện
    // ra như số đo thật. Số giờ lấy từ `renderMetrics()` — đo trong server.
    $('.latency').classList.toggle('good', active && live.metrics.frames > 0);
    $('#mockMessageTitle').textContent = active ? 'Phiên demo đang hoạt động' : ({ desktop: 'Phiên demo đã sẵn sàng', browser: 'Trình duyệt đã được chọn', notes: 'Ghi chú đang mở' }[state.selectedWindow]);
    $('#cursorPointer').classList.toggle('hidden', !active || !state.cursor);
    if (notify && active) toast('Phiên mô phỏng bắt đầu. Muốn xem màn hình thật thì bấm "Xem máy thật".');
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
        const result = await apiRequest('/api/sessions', { method: 'POST', body: { mode: state.mode, windowId: state.selectedWindow, audio: state.audio } });
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
  $$('.window-option').forEach(btn => btn.addEventListener('click', () => {
    state.selectedWindow = btn.dataset.window;
    $$('.window-option').forEach(option => option.classList.toggle('selected', option === btn));
  }));
  $('#dialogConfirm').addEventListener('click', () => {
    updateMockWindow();
    closeOverlay('#dialogOverlay');
    toast(`Đã chọn: ${labels[state.selectedWindow]}.`);
  });
  $('#dialogClose').addEventListener('click', () => closeOverlay('#dialogOverlay'));
  $('#dialogCancel').addEventListener('click', () => closeOverlay('#dialogOverlay'));

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
    $('#diagnosticsIntro').textContent = 'Đang kiểm tra Windows, adapter, GStreamer và display driver…';
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
    if (id === 'aspect') $('#mockDesktop').dataset.aspect = value;
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
      const validWindowIds = new Set(windows.windows.map(win => win.id));
      if (!validWindowIds.has(state.selectedWindow)) state.selectedWindow = 'desktop';
      if (current.session) {
        currentSessionId = current.session.id;
        state.mode = current.session.mode;
        state.selectedWindow = current.session.windowId;
        syncMode(); updateMockWindow(); setConnected(true, false);
      }
      document.documentElement.dataset.api = health.ok ? 'online' : 'offline';
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
  $('#liveInstall').addEventListener('click', installGstreamer);
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
  $('#liveImage').addEventListener('error', () => {
    // Ảnh MJPEG lỗi (pipeline chết, GStreamer thiếu) ⇒ dừng trạng thái để người
    // dùng thấy thông báo thật thay vì một khung đen im lặng.
    if (!live.active) return;
    live.active = false;
    renderLive();
    toast('Không xem được màn hình thật: kiểm tra GStreamer và monitor index trong bảng chẩn đoán.');
  });
  $('#sendCtrlAltDel').addEventListener('click', () => toast(state.connected ? 'Phím tắt đang được mô phỏng; chưa gửi tới máy.' : 'Hãy bắt đầu phiên demo trước.'));
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
