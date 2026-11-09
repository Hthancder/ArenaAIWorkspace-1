// §50.1 #5 (P2) — âm thanh/rung báo khi phiên **bắt đầu** và **kết thúc**.
//
// # Vì sao cần với 1 người dùng
//
// Người dùng bật phiên rồi **rời màn hình** — đó là toàn bộ mục đích của remote
// desktop. Khi phiên đứt (mạng, máy kia ngủ, ai đó tắt app), họ không biết cho
// tới lần sau nhìn vào. Spec nói đúng: *"biết ngay khi phiên bị ngắt, không phải
// nhìn màn hình"*.
//
// # Vì sao WebAudio thay vì file .mp3
//
// Một file âm thanh là một asset nữa phải có route, phải nằm trong exe, và khi
// thiếu thì **im lặng** — đúng loại lỗi đã gặp với `/live.js`. WebAudio sinh
// tông trực tiếp, không cần asset, và không thể "404".
//
// # Autoplay: đây là giới hạn thật, phải nói rõ
//
// Trình duyệt chặn `AudioContext` cho tới khi có tương tác của người dùng. Ta
// **không** lách: tạo context ở lần click đầu tiên, và nếu context bị `suspended`
// thì **rung** thay thế (`navigator.vibrate`) — rung không bị chặn. Nếu cả hai
// không được thì tiếng chuông **không kêu**, và điều đó đúng: im lặng tốt hơn
// giả vờ đã báo. `notify()` trả `false` để nơi gọi biết và có thể hiện toast.

/** Tông của hai sự kiện: lên (bắt đầu) và xuống (kết thúc). */
const TONES = {
  // Bắt đầu: hai nốt **lên** — tai người đọc "lên" là "tốt/đã mở".
  start: [660, 880],
  // Kết thúc: hai nốt **xuống**, thấp hơn — đọc là "đóng/mất".
  end: [520, 350],
};

let context = null;
/** `true` khi đã có tương tác của người dùng ⇒ được phép tạo `AudioContext`. */
let primed = false;

/**
 * Gọi ở **lần tương tác đầu tiên** (click/keydown).
 *
 * Không tạo `AudioContext` ngay khi tải trang: trình duyệt tạo nó ở trạng thái
 * `suspended`, và tiếng chuông đầu tiên sẽ **im** dù code đúng. Tạo sau tương
 * tác thì nó chạy được ngay.
 */
export function prime() {
  if (primed) return;
  primed = true;
  try {
    const Ctor = window.AudioContext || window.webkitAudioContext;
    if (Ctor) context = new Ctor();
  } catch {
    // Trình duyệt không có WebAudio: rung là đường còn lại.
    context = null;
  }
}

/**
 * Báo một sự kiện. Trả `true` nếu **đã** báo được (tiếng hoặc rung).
 *
 * Trả `false` là thông tin có giá trị: nơi gọi hiện toast thay thế, thay vì để
 * người dùng tưởng chuông đã kêu mà không có gì.
 */
export function notify(kind) {
  const notes = TONES[kind] || TONES.start;
  const sounded = play(notes);
  if (sounded) return true;
  return vibrate(kind);
}

function play(notes) {
  if (!context) return false;
  if (context.state === 'suspended') {
    // `resume()` là async nhưng ta không chờ: nếu nó thành công ngay thì tiếng
    // kêu, nếu không thì `vibrate` là đường dự phòng. Chờ ở đây sẽ làm hàm gọi
    // thành async và làm chậm mọi đường báo — không đáng cho một tiếng "bíp".
    context.resume().catch(() => {});
  }
  try {
    const now = context.currentTime;
    notes.forEach((frequency, index) => {
      const oscillator = context.createOscillator();
      const gain = context.createGain();
      oscillator.type = 'sine';
      oscillator.frequency.value = frequency;
      const start = now + index * 0.14;
      const end = start + 0.12;
      // Bao âm lượng: lên nhanh rồi tắt dần. Không có bao thì tiếng "tạch" ở
      // hai đầu — vì loa không đổi biên độ tức thời được.
      gain.gain.setValueAtTime(0, start);
      gain.gain.linearRampToValueAtTime(0.18, start + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.001, end);
      oscillator.connect(gain).connect(context.destination);
      oscillator.start(start);
      oscillator.stop(end + 0.02);
    });
    return true;
  } catch {
    return false;
  }
}

function vibrate(kind) {
  // Mẫu rung khác nhau để phân biệt bằng tay mà không cần nhìn: bắt đầu = hai
  // nhịp ngắn, kết thúc = một nhịp dài.
  const pattern = kind === 'end' ? [220] : [60, 70, 60];
  try {
    if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function') {
      return navigator.vibrate(pattern);
    }
  } catch {
    // Một số trình duyệt ném khi rung bị tắt trong cài đặt hệ thống.
  }
  return false;
}
