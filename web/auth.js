// §7.1 + §41: màn hình **khoá** — đặt mật khẩu lần đầu, rồi đăng nhập.
//
// # Vì sao đây là khối chặn lớn nhất chứ không phải "tính năng phụ"
//
// Server từ chối mọi thao tác khi đã đặt mật khẩu mà request không có token,
// nhưng UI **không có form nào**. Người dùng mở exe ra, thấy giao diện quen
// thuộc, bấm gì cũng 401, và không có chỗ nào để đặt mật khẩu. Đó là "app
// không dùng được", không phải "thiếu tính năng".
//
// # Token đi đâu
//
// `access` (15 phút) ở trong bộ nhớ JS — mất khi tải lại trang, và **không**
// vào `localStorage`: XSS đọc được `localStorage`, còn token trong closure thì
// không. Thứ sống qua tải lại trang là refresh token trong cookie `HttpOnly`
// (§41.6), mà JS không đọc được — nên tải lại trang thì `/api/refresh` phát
// access mới từ cookie đó.
//
// # Vì sao là file riêng (ES module)
//
// CSP `default-src 'self'` (§41.4 T5) chặn inline script. Nhúng JS vào HTML
// nghĩa là trang hiện ra nhưng **không có script nào chạy** — lỗi im lặng, đã
// gặp một lần với `/live`.

const overlay = document.getElementById('authOverlay');
const title = document.getElementById('authTitle');
const intro = document.getElementById('authIntro');
const form = document.getElementById('authForm');
const userField = document.getElementById('authUser');
const passField = document.getElementById('authPass');
const passField2 = document.getElementById('authPass2');
const passWrap = document.getElementById('authPassWrap');
const submit = document.getElementById('authSubmit');
const errorBox = document.getElementById('authError');

let unlocked = false;
let mode = 'login';

/**
 * Access token **trong bộ nhớ**, không phải `localStorage`.
 *
 * Export `authFetch` để phần còn lại của app dùng — route nào quên header thì
 * nhận 401 và người dùng thấy "app hỏng" thay vì "chưa đăng nhập".
 */
let accessToken = '';
/** Promise đang refresh, để 10 request đồng thời chỉ tạo **một** vòng refresh. */
let refreshing = null;

function showError(message) {
  errorBox.textContent = message;
  errorBox.classList.remove('hidden');
}

function clearError() {
  errorBox.textContent = '';
  errorBox.classList.add('hidden');
}

/**
 * `fetch` có gắn `Authorization` và **tự refresh một lần** khi 401.
 *
 * Refresh đúng một lần, không lặp: nếu token mới vẫn bị từ chối thì đó là lỗi
 * thật (bị thu hồi, sai `sub`), lặp lại chỉ tạo vòng vô hạn và đốt lockout.
 */
export async function authFetch(path, options = {}) {
  const send = (token) => {
    const headers = new Headers(options.headers || {});
    if (token) headers.set('authorization', `Bearer ${token}`);
    return fetch(path, { ...options, headers });
  };
  let response = await send(accessToken);
  if (response.status !== 401) return response;
  // Hết hạn 15 phút. Thử đổi refresh cookie lấy access mới.
  const fresh = await refreshAccess();
  if (!fresh) return response;
  return send(fresh);
}

async function refreshAccess() {
  if (refreshing) return refreshing;
  refreshing = (async () => {
    try {
      const response = await fetch('/api/refresh', { method: 'POST' });
      if (!response.ok) return '';
      const data = await response.json();
      accessToken = data.access || '';
      return accessToken;
    } catch {
      return '';
    } finally {
      refreshing = null;
    }
  })();
  return refreshing;
}

/**
 * Chọn chế độ: lần đầu thì **đặt** mật khẩu, sau đó thì đăng nhập.
 *
 * Dò bằng `/api/auth/state` (công khai, trả đúng một boolean). Không dò bằng
 * cách gọi `/api/login` với mật khẩu giả: mỗi lần tải trang sẽ tính là một lần
 * sai và tự khoá mình sau 5 lần (§41.2 P4).
 */
async function detect() {
  try {
    const response = await fetch('/api/auth/state', { cache: 'no-store' });
    const data = await response.json().catch(() => ({}));
    // Server cũ (artifact trước bản này) không có route ⇒ 404 ⇒ rơi về `login`,
    // an toàn hơn `setup`: setup trên server đã cấu hình trả 409 và
    // `already_configured` tự chuyển chế độ.
    mode = data.configured === false ? 'setup' : 'login';
  } catch {
    mode = 'login';
  }
  // Đã đăng nhập rồi (refresh cookie còn hạn) thì vào thẳng, không bắt gõ lại.
  // Tải lại trang là mất `accessToken`, nên phải thử refresh — đây là đường
  // bình thường, không phải trường hợp lỗi.
  if (mode === 'login' && (await refreshAccess())) {
    unlocked = true;
    unlockUi();
    return;
  }
  render();
}

function render() {
  const setup = mode === 'setup';
  title.textContent = setup ? 'Đặt mật khẩu' : 'Đăng nhập';
  intro.textContent = setup
    ? 'Lần đầu chạy. Mật khẩu này bảo vệ phiên xem máy — tối thiểu 12 ký tự (§4373).'
    : 'Nhập mật khẩu bạn đã đặt để mở phiên.';
  submit.textContent = setup ? 'Đặt mật khẩu' : 'Mở khoá';
  // Ô nhập lại chỉ có ở chế độ đặt: gõ sai một ký tự rồi không đăng nhập được
  // nữa là cách tự khoá mình dễ nhất, và không có đường khôi phục.
  passWrap.classList.toggle('hidden', !setup);
  passField.autocomplete = setup ? 'new-password' : 'current-password';
}

function unlockUi() {
  overlay.classList.add('hidden');
  document.body.classList.remove('locked');
  // Cho phần còn lại của app biết để nạp dữ liệu — không dùng tên sự kiện tuỳ
  // ý, mà qua callback `onUnlocked` đã đăng ký.
  window.dispatchEvent(new CustomEvent('lantern:unlocked'));
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  clearError();
  const user = userField.value.trim();
  const password = passField.value;
  if (!user) return showError('Chưa nhập tên đăng nhập.');
  if (!password) return showError('Chưa nhập mật khẩu.');
  if (mode === 'setup') {
    if (password !== passField2.value) return showError('Hai lần nhập không khớp.');
    // Kiểm ngay ở client để người dùng không phải chờ một vòng mạng cho một lỗi
    // chắc chắn xảy ra. Server **vẫn** kiểm lại — client không được tin.
    if (password.length < 12) {
      return showError(`Mật khẩu phải dài ít nhất 12 ký tự (đang ${password.length}).`);
    }
  }

  submit.disabled = true;
  try {
    const path = mode === 'setup' ? '/api/setup' : '/api/login';
    const response = await fetch(path, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ u: user, p: password }),
    });
    if (response.ok) {
      const data = await response.json().catch(() => ({}));
      // `/api/setup` trả `{"ok":true}` — chưa có token. Đặt xong thì **đăng
      // nhập luôn** bằng chính mật khẩu vừa nhập, để người dùng không phải gõ
      // lại một lần nữa trên cùng một form.
      if (data.access) {
        accessToken = data.access;
      } else {
        const login = await fetch('/api/login', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ u: user, p: password }),
        });
        const loginData = await login.json().catch(() => ({}));
        accessToken = loginData.access || '';
        if (!login.ok) {
          showError('Đã đặt mật khẩu nhưng chưa đăng nhập được. Hãy thử lại.');
          mode = 'login';
          render();
          return;
        }
      }
      // Không lưu mật khẩu ở đâu cả. Refresh token nằm trong cookie `HttpOnly`.
      passField.value = '';
      passField2.value = '';
      unlocked = true;
      unlockUi();
      return;
    }
    const data = await response.json().catch(() => ({}));
    const messages = {
      weak_password: 'Mật khẩu quá ngắn — cần ít nhất 12 ký tự.',
      already_configured: 'Máy này đã có mật khẩu. Hãy đăng nhập.',
      invalid_credentials: 'Sai tên đăng nhập hoặc mật khẩu.',
      locked_out: 'Sai quá nhiều lần. Thử lại sau ít phút.',
      no_password_set: 'Chưa có mật khẩu trên máy này.',
    };
    if (data.error === 'already_configured') {
      mode = 'login';
      render();
    }
    showError(messages[data.error] || `Không mở được (${response.status}).`);
  } catch {
    showError('Không kết nối được tới server. Kiểm tra app còn chạy không.');
  } finally {
    submit.disabled = false;
  }
});

// `locked` để CSS chặn cuộn và che phần sau, tránh người dùng bấm vào giao diện
// chưa có quyền rồi thấy toàn lỗi 401.
document.body.classList.add('locked');
detect();

export function onUnlocked(callback) {
  if (unlocked) callback();
  else window.addEventListener('lantern:unlocked', callback, { once: true });
}
