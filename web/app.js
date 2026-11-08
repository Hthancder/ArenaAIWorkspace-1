(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const state = { connected: false, mode: 'hvnc', room: false, audio: true, mic: false, selectedWindow: 'desktop', cursor: true, quality: 'balanced', resolution: '1080' };
  const labels = { desktop: 'Toàn bộ màn hình', browser: 'Trình duyệt', notes: 'Ghi chú' };
  let toastTimer;

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
  function setConnected(active) {
    state.connected = active;
    $('#connectBtn').classList.toggle('connected', active);
    $('#connectLabel').textContent = active ? 'Kết thúc phiên demo' : 'Bắt đầu phiên demo';
    $('#connectHint').textContent = active ? 'Đang mô phỏng · dữ liệu không rời trình duyệt' : 'Mô phỏng cục bộ · không truy cập thiết bị thật';
    $('#screenState').textContent = active ? 'Phiên demo đang hoạt động' : 'Đang chờ phiên demo';
    $('#sessionStatus').textContent = active ? 'Đã kết nối · demo' : 'Chưa kết nối';
    $('#sessionSubstatus').textContent = active ? 'Thiết bị mô phỏng · vừa bắt đầu' : 'Bắt đầu để thử giao diện';
    $('#latencyText').textContent = active ? '24 ms' : '—';
    $('#bandwidthText').textContent = active ? '2.4 Mbps' : '—';
    $('.latency').classList.toggle('good', active);
    $('#mockMessageTitle').textContent = active ? 'Phiên demo đang hoạt động' : ({ desktop: 'Phiên demo đã sẵn sàng', browser: 'Trình duyệt đã được chọn', notes: 'Ghi chú đang mở' }[state.selectedWindow]);
    $('#cursorPointer').classList.toggle('hidden', !active || !state.cursor);
    if (active) toast('Phiên demo bắt đầu — thiết bị thật chưa được kết nối.');
    else toast('Phiên demo đã kết thúc.');
  }
  function openOverlay(id) {
    const el = $(id);
    el.classList.remove('hidden');
    const dialog = $('.dialog', el);
    if (dialog) dialog.setAttribute('tabindex', '-1');
    $('.dialog', el)?.focus();
  }
  function closeOverlay(id) { $(id).classList.add('hidden'); }

  $('#connectBtn').addEventListener('click', () => setConnected(!state.connected));
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
  $('#micBtn').addEventListener('click', () => {
    state.mic = !state.mic;
    setToggle($('#micToggle'), state.mic);
    toast(state.mic ? 'Micro mô phỏng đã bật — chưa thu âm thật.' : 'Micro mô phỏng đã tắt.');
  });
  $('#settingsOpen').addEventListener('click', () => openOverlay('#settingsOverlay'));
  $('#settingsMini').addEventListener('click', () => openOverlay('#settingsOverlay'));
  $('#settingsClose').addEventListener('click', () => closeOverlay('#settingsOverlay'));
  $('#settingsDone').addEventListener('click', () => closeOverlay('#settingsOverlay'));
  $('#qualitySelect').addEventListener('change', event => {
    state.quality = event.target.value;
    $('.quality-indicator').innerHTML = `<i></i> ${state.quality === 'sharp' ? 'Rõ nét' : state.quality === 'smooth' ? 'Mượt' : 'HD'}`;
    toast(`Chất lượng: ${event.target.selectedOptions[0].text}.`);
  });
  $('#resolutionSelect').addEventListener('change', event => {
    state.resolution = event.target.value;
    const val = state.resolution === '720' ? '720p' : state.resolution === 'native' ? 'Theo cửa sổ' : '1080p';
    $('#screenResolution').textContent = `${val} · 30 FPS (demo)`;
    toast(`Kích thước xem: ${val}.`);
  });
  $('#cursorSetting').addEventListener('click', () => {
    state.cursor = !state.cursor;
    setToggle($('#cursorSetting'), state.cursor);
    $('#cursorPointer').classList.toggle('hidden', !state.connected || !state.cursor);
  });
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
  $('#sendCtrlAltDel').addEventListener('click', () => toast(state.connected ? 'Phím tắt đang được mô phỏng; chưa gửi tới máy.' : 'Hãy bắt đầu phiên demo trước.'));
  $('#blankScreen').addEventListener('click', () => toast('Màn hình riêng tư chưa được kết nối với máy thật.'));
  $('#helpBtn').addEventListener('click', () => toast('Bản mock tương tác: mọi thao tác chỉ thay đổi giao diện này.'));
  $('#aboutMock').addEventListener('click', () => toast('Chưa có truyền hình ảnh, camera, micro hay lệnh tới máy thật.'));
  $$('.nav-item').forEach(btn => btn.addEventListener('click', () => toast(`${btn.textContent.trim()} — mục này thuộc mock giao diện.`)));
  $$('.overlay').forEach(overlay => overlay.addEventListener('click', event => {
    if (event.target === overlay) overlay.classList.add('hidden');
  }));
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') $$('.overlay').forEach(el => el.classList.add('hidden'));
  });
})();
