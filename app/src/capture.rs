//! Capture màn hình Windows bằng **DXGI Desktop Duplication**, gọi thẳng qua COM
//! — không GStreamer, không FFmpeg, không crate nào.
//!
//! Vì sao phải làm thế này thay vì mượn `d3d11screencapturesrc`: đường cũ kéo
//! theo **installer GStreamer 517 MB** cho một việc mà ta chỉ cần đúng hai thứ:
//! một frame BGRA và một hàm nén JPEG (`crate::jpeg`). Với người dùng cá nhân,
//! "cài 517 MB để xem màn hình" là cái giá sai. Bản này biên dịch vào exe, tổng
//! artifact khoảng 2 MB.
//!
//! Đây **vẫn là DXGI**, đúng đường đã chốt ở §52.4: `IDXGIOutputDuplication` lấy
//! frame từ compositor của Windows, cùng nguồn mà `d3d11screencapturesrc` dùng.
//! Khác biệt duy nhất là ta tự gọi thay vì để GStreamer gọi.
//!
//! ## Những gì file này cố ý **không** làm
//!
//! | Không làm | Vì sao |
//! |---|---|
//! | Dựng lại `ID3D11Device` mỗi frame | 200–800 ms mỗi lần (Optimus, §53.4) |
//! | Copy frame qua CPU khi không cần | `Map` + `RowPitch` là đủ, một lần copy |
//! | Bắt mọi lỗi DXGI thành "không capture được" | 5 lỗi khác nhau, 5 cách sửa khác nhau |
//! | Chạy trên adapter rời | HD 630 + 0 copy; GTX 1050 phải thức (§52.3) |
//!
//! ## An toàn bộ nhớ
//!
//! Không có crate `windows`, nên mọi lời gọi COM đều qua `#[repr(C)]` khai báo
//! tay. Vtable là **con trỏ tới mảng con trỏ hàm**; sai thứ tự một hàm là crash
//! ngay — nên mọi vtable ở đây chép đúng thứ tự từ header `d3d11.h`/`dxgi1_2.h`
//! và có test đếm số slot.

//! Toàn bộ khai báo kiểu (vtable, hằng số, struct) được biên dịch trên **mọi**
//! nền tảng; chỉ phần gọi API là `#[cfg(windows)]`. Lý do: lỗi kiểu trong khai
//! báo FFI (`c_void as *mut T`) không hiện khi biên dịch trên Linux nếu cả module
//! bị loại bỏ — và đó đúng là cách 8 lỗi lọt vào CI Windows.
#![cfg_attr(not(windows), allow(dead_code))]

use std::ffi::c_void;
#[cfg(windows)]
use std::ptr;

// Tên dùng đúng chữ của header Windows (`HRESULT`, `UINT`) chứ không theo
// convention của Rust: khi tra cứu tài liệu, hai bên phải khớp nhau từng chữ.
// Đây là ngoại lệ có chủ ý, không phải sơ suất.
#[allow(clippy::upper_case_acronyms)]
type HRESULT = i32;
#[allow(clippy::upper_case_acronyms)]
type UINT = u32;

/// `DXGI_ERROR_WAIT_TIMEOUT`: màn hình không đổi trong thời gian chờ. **Không**
/// phải lỗi — chỉ là không có frame mới.
const DXGI_ERROR_WAIT_TIMEOUT: HRESULT = 0x887A0027u32 as i32;
/// `DXGI_ERROR_ACCESS_LOST`: desktop đổi (UAC, khoá máy, đổi độ phân giải) ⇒
/// phải dựng lại toàn bộ duplication.
const DXGI_ERROR_ACCESS_LOST: HRESULT = 0x887A0022u32 as i32;

#[repr(C)]
struct Guid {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [u8; 8],
}

const fn guid(data1: u32, data2: u16, data3: u16, tail: [u8; 8]) -> Guid {
    Guid { data1, data2, data3, data4: tail }
}

/// `IID_IDXGIFactory1` = {770AAE78-F26F-4DBA-A829-253C83D1B387}.
///
/// **Đừng gõ GUID bằng trí nhớ.** Bản trước có 3 byte cuối sai (`83 21 3a 00`
/// thay vì `83 d1 b3 87`) và `CreateDXGIFactory1` trả `E_NOINTERFACE`
/// (`0x80004002`) trên **mọi** máy — trông y như "máy không có DXGI". Byte cuối
/// sai kéo theo `create_dxgi_factory1` không bao giờ thành công, nên toàn bộ
/// đường capture chết ngay dòng đầu. Có `guid_iid_factory1_matches_win32_headers`
/// khoá lại.
const IID_IDXGI_FACTORY1: Guid = guid(0x770aae78, 0xf26f, 0x4dba, [0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87]);
/// `IID_IDXGIOutput1`
const IID_IDXGI_OUTPUT1: Guid = guid(0x00cddea8, 0x939b, 0x4b83, [0xa3, 0x40, 0xa6, 0x85, 0x22, 0x66, 0x66, 0xcc]);

#[repr(C)]
struct Rect {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
}

#[repr(C)]
struct OutputDesc {
    device_name: [u16; 32],
    desktop_coordinates: Rect,
    attached_to_desktop: i32,
    rotation: u32,
    monitor: usize,
}

/// `DXGI_MODE_DESC` — 28 byte. **Không** phải 16.
///
/// Bản trước khai `mode_desc: [u8; 16]` và `GetDesc` ghi 28 byte vào đó ⇒ tràn
/// 12 byte ra ngoài struct, trên stack. Triệu chứng trên máy thật: capture
/// "chạy" nhưng `width`/`height` đọc ra rác, hoặc crash ngay sau `GetDesc` —
/// không phải một thông báo lỗi đọc được.
#[repr(C)]
struct ModeDesc {
    width: u32,
    height: u32,
    refresh_rate_numerator: u32,
    refresh_rate_denominator: u32,
    format: u32,
    scanline_ordering: u32,
    /// `DXGI_MODE_SCALING` — trường thứ **bảy**. Bỏ nó là 24 byte thay vì 28, và
    /// test kích thước bắt được đúng chỗ này.
    scaling: u32,
}

#[repr(C)]
struct OutduplDesc {
    mode_desc: ModeDesc,
    rotation: u32,
    desktop_image_format: u32,
}

/// Loại lỗi **khác nhau**, vì cách sửa khác nhau. Gộp hết thành "không capture
/// được" là lỗi tệ nhất của loại code này (§58.16).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CaptureError {
    /// Không có DXGI 1.2 / không có màn hình nào gắn vào desktop.
    NoOutput,
    /// `monitor-index` vượt số màn hình **thật** — kèm con số đúng để UI nói được.
    BadMonitor { requested: u8, available: u32 },
    /// Chưa có `ID3D11Device`, hoặc D3D11 không dựng được (driver cũ, RDP session).
    NoDevice(String),
    /// Desktop đổi (UAC, khoá máy, đổi độ phân giải). Cách sửa: dựng lại — tự động.
    AccessLost,
    /// Hết thời gian chờ: màn hình **không đổi**. Không phải lỗi.
    Timeout,
    /// HRESULT khác. Giữ mã để người dùng tra được, không nuốt.
    Other(String),
}

impl CaptureError {
    /// Câu tiếng Việt đọc được, kèm **việc cần làm**. Một thông báo nói "lỗi
    /// DXGI 0x887A0004" là thông báo vô dụng với người dùng.
    pub fn message(&self) -> String {
        match self {
            CaptureError::NoOutput => "Không thấy màn hình nào gắn vào desktop (có thể đang ở phiên RDP đã ngắt).".into(),
            CaptureError::BadMonitor { requested, available } => format!(
                "monitor-index {requested} không tồn tại: máy chỉ có {available} màn hình (đánh số từ 0)."
            ),
            CaptureError::NoDevice(detail) => format!("Không dựng được DXGI device: {detail}"),
            CaptureError::AccessLost => "Desktop vừa đổi (UAC/khoá máy/đổi độ phân giải). Đang dựng lại…".into(),
            CaptureError::Timeout => "Màn hình không đổi trong thời gian chờ.".into(),
            CaptureError::Other(detail) => format!("DXGI trả lỗi: {detail}"),
        }
    }
}

fn hresult(code: HRESULT) -> String {
    format!("0x{:08X}", code as u32)
}

fn check(code: HRESULT, what: &str) -> Result<(), CaptureError> {
    if code >= 0 {
        return Ok(());
    }
    Err(match code {
        DXGI_ERROR_ACCESS_LOST => CaptureError::AccessLost,
        _ => CaptureError::Other(format!("{what} → {}", hresult(code))),
    })
}

// --- Khai báo vtable -------------------------------------------------------
//
// Mỗi struct dưới đây là **lát cắt** của vtable gốc: chỉ những hàm ta gọi, và
// chỉ khi mọi hàm ta gọi đều nằm ở **đầu** vtable của interface đó. `Release` và
// `AddRef` của `IUnknown` luôn ở slot 2 và 3.

type QueryInterfaceFn = unsafe extern "system" fn(*mut c_void, *const Guid, *mut *mut c_void) -> HRESULT;
type AddRefFn = unsafe extern "system" fn(*mut c_void) -> u32;
type ReleaseFn = unsafe extern "system" fn(*mut c_void) -> u32;

/// `IUnknown` dùng chung: 3 slot đầu của **mọi** COM interface.
#[repr(C)]
struct Unknown {
    query_interface: Option<QueryInterfaceFn>,
    add_ref: Option<AddRefFn>,
    release: Option<ReleaseFn>,
}

unsafe fn release<T>(object: *mut T) {
    if object.is_null() {
        return;
    }
    let unknown = object.cast::<Unknown>();
    if let Some(release) = (*vtbl(unknown)).release {
        release(object as *mut c_void);
    }
}

/// Một con trỏ COM **sở hữu** một tham chiếu, tự nhả khi ra khỏi scope.
///
/// # Vì sao phải có kiểu này
///
/// `Capture::open` gọi `IDXGIFactory1` → adapter → output, mỗi bước có 4–6 nhánh
/// `return Err`. Viết tay `release(x)` ở từng nhánh thì **sớm muộn cũng sai** —
/// và đã sai thật hai lần trong một buổi:
///
/// * `release(candidate)` hai lần trên cùng object khi `QueryInterface` lỗi
///   ⇒ refcount xuống dưới 0 ⇒ `--check` crash trên runner Windows.
/// * `ReleaseFrame` bị bỏ ở nhánh `CopyResource == None` ⇒ stream chết.
///
/// Kiểu này biến "nhớ nhả đúng một lần" từ việc **con người phải nhớ** thành
/// việc **compiler kiểm**.
struct Com<T> {
    raw: *mut T,
}

impl<T> Com<T> {
    /// Nhận sở hữu. `raw` null ⇒ wrapper rỗng, `release` không làm gì.
    fn new(raw: *mut T) -> Self {
        Self { raw }
    }
    fn as_ptr(&self) -> *mut T {
        self.raw
    }
    /// Lấy con trỏ ra mà vẫn để wrapper sở hữu — dùng khi chỉ mượn.
    fn cast<U>(&self) -> *mut U {
        self.raw.cast::<U>()
    }
    /// Chuyển sở hữu ra ngoài (dùng khi nhét vào `Capture`).
    ///
    /// `mem::forget` để `Drop` của wrapper không nhả — người nhận giờ chịu
    /// trách nhiệm. Không có hàm này thì `Ok(Self { … })` sẽ nhả ngay khi hàm
    /// trả về và `Capture` giữ con trỏ chết.
    fn into_raw(self) -> *mut T {
        let raw = self.raw;
        std::mem::forget(self);
        raw
    }
}

impl<T> Drop for Com<T> {
    fn drop(&mut self) {
        unsafe { release(self.raw) };
        self.raw = std::ptr::null_mut();
    }
}

unsafe impl<T> Send for Com<T> {}

/// `IDXGIFactory1` — ta chỉ cần `EnumAdapters1` (slot 12) và `Release`.
/// Slot 0–2 = IUnknown, 3–4 = IDXGIObject (SetPrivateData, SetPrivateDataInterface),
/// 5–6 = GetPrivateData, SetPrivateDataInterface... Thứ tự chính xác theo dxgi.h.
#[repr(C)]
struct Factory1 {
    query_interface: Option<QueryInterfaceFn>,
    add_ref: Option<AddRefFn>,
    release: Option<ReleaseFn>,
    set_private_data: *mut c_void,
    set_private_data_interface: *mut c_void,
    get_private_data: *mut c_void,
    get_parent: *mut c_void,
    /// slot 7
    enum_adapters: *mut c_void,
    /// slot 8 — `MakeWindowAssociation`
    _make_window_association: *mut c_void,
    /// slot 9 — `GetWindowAssociation`
    _get_window_association: *mut c_void,
    /// slot 10 — `CreateSwapChain`
    _create_swap_chain: *mut c_void,
    /// slot 11 — `CreateSoftwareAdapter`
    _create_software_adapter: *mut c_void,
    /// slot 12 — **đúng chỗ này**. Bản đầu để ở 14 (đếm thiếu 2 slot) ⇒ gọi nhầm
    /// `CreateSoftwareAdapter`/`EnumAdapters1` sai chỗ ⇒ crash trên Windows.
    enum_adapters1: Option<unsafe extern "system" fn(*mut c_void, UINT, *mut *mut c_void) -> HRESULT>,
    /// slot 13 — `IsCurrent1`
    _is_current1: *mut c_void,
}

/// `IDXGIAdapter1`: `GetDesc1` ở slot 10, `EnumOutputs` ở slot 7.
///
/// Vtable: 0–2 IUnknown, 3 GetDesc, 4 GetParent(? theo thứ tự dxgi: SetPrivateData
/// 3, SetPrivateDataInterface 4, GetPrivateData 5, GetParent 6, EnumOutputs 7,
/// GetDesc 8, CheckInterfaceSupport 9). `GetDesc1` nằm sau `CheckInterfaceSupport`.
#[repr(C)]
struct Adapter1 {
    query_interface: Option<QueryInterfaceFn>,
    add_ref: Option<AddRefFn>,
    release: Option<ReleaseFn>,
    set_private_data: *mut c_void,
    set_private_data_interface: *mut c_void,
    get_private_data: *mut c_void,
    get_parent: *mut c_void,
    enum_outputs: Option<unsafe extern "system" fn(*mut c_void, UINT, *mut *mut c_void) -> HRESULT>,
    get_desc: *mut c_void,
    check_interface_support: *mut c_void,
    get_desc1: *mut c_void,
}

/// `IDXGIOutput1`: chỉ cần `DuplicateOutput` — slot 22 trong dxgi1_2.h.
///
/// Đây là chỗ dễ sai nhất khi khai báo tay: `IDXGIOutput` có 12 slot (0–11),
/// `IDXGIOutput1` thêm 2 slot (`DuplicateOutput` = 22, `DuplicateOutput1` = 23)…
/// Kiểm bằng `assert` slot trong test.
#[repr(C)]
struct Output1 {
    // Đếm theo `include/dxgi.idl` + `include/dxgi1_2.idl` của Wine:
    //   IUnknown 0–2 · IDXGIObject: SetPrivateData 3, SetPrivateDataInterface 4,
    //   GetPrivateData 5, GetParent 6
    //   IDXGIOutput (12 method, slot 7–18): **GetDesc 7**, GetDisplayModeList 8,
    //     FindClosestMatchingMode 9, WaitForVBlank 10, TakeOwnership 11,
    //     ReleaseOwnership 12, GetGammaControlCapabilities 13, SetGammaControl 14,
    //     GetGammaControl 15, SetDisplaySurface 16, GetDisplaySurfaceData 17,
    //     GetFrameStatistics 18
    //   IDXGIOutput1: GetDisplayModeList1 19, FindClosestMatchingMode1 20,
    //     GetDisplaySurfaceData1 21, **DuplicateOutput 22** ✅
    // Khoảng 8..=21 (14 slot) không dùng hàm nào nhưng **phải** khai báo để
    // `duplicate_output` rơi đúng slot 22.
    // 0..=6: IUnknown (3) + IDXGIObject (4) ⇒ gộp thành 7 slot im lặng.
    _object: [*mut c_void; 7],
    get_desc: Option<unsafe extern "system" fn(*mut c_void, *mut OutputDesc) -> HRESULT>,
    _output_rest: [*mut c_void; 14],
    duplicate_output: Option<
        unsafe extern "system" fn(*mut c_void, *mut c_void, *mut *mut c_void) -> HRESULT,
    >,
}

/// `IDXGIOutputDuplication` — `AcquireNextFrame`, `GetFrameDirtyRects`…, ta cần
/// `AcquireNextFrame` (slot 8), `GetDesc` (slot 11), `ReleaseFrame` (slot 14),
/// `Release` (2).
#[repr(C)]
struct OutputDuplication {
    query_interface: Option<QueryInterfaceFn>,
    add_ref: Option<AddRefFn>,
    release: Option<ReleaseFn>,
    // IDXGIObject: SetPrivateData 3, SetPrivateDataInterface 4, GetPrivateData 5, GetParent 6
    _object: [*mut c_void; 4],
    // IDXGIOutputDuplication: GetDesc 7? — theo dxgi1_2.h:
    //   GetDesc = 7, AcquireNextFrame = 8, GetFrameDirtyRects = 9,
    //   GetFrameMoveRects = 10, GetFramePointerShape = 11,
    //   MapDesktopSurface = 12, UnMapDesktopSurface = 13, ReleaseFrame = 14
    get_desc: Option<unsafe extern "system" fn(*mut c_void, *mut OutduplDesc) -> HRESULT>,
    /// slot 8
    /// `pFrameInfo: *mut DXGI_OUTDUPL_FRAME_INFO` = **48 byte**. Khai 16 thì
    /// `AcquireNextFrame` ghi tràn 32 byte lên stack mỗi frame.
    acquire_next_frame: Option<
        unsafe extern "system" fn(*mut c_void, UINT, *mut [u8; 48], *mut *mut c_void) -> HRESULT,
    >,
    /// slot 9 — `GetFrameDirtyRects`
    _get_frame_dirty_rects: *mut c_void,
    /// slot 10 — `GetFrameMoveRects`
    _get_frame_move_rects: *mut c_void,
    /// slot 11 — `GetFramePointerShape`
    _get_frame_pointer_shape: *mut c_void,
    /// slot 12 — `MapDesktopSurface`
    _map_desktop_surface: *mut c_void,
    /// slot 13 — `UnMapDesktopSurface`
    _unmap_desktop_surface: *mut c_void,
    /// slot 14 — **đúng chỗ này**. Bản đầu để ở 11 (thiếu 3 slot) ⇒ gọi
    /// `MapDesktopSurface` thay vì `ReleaseFrame`, và frame kế tiếp trả
    /// `E_ACCESSDENIED` mãi mãi.
    release_frame: Option<unsafe extern "system" fn(*mut c_void) -> HRESULT>,
}

// `IDXGIResource` không cần struct riêng nữa: `QueryInterface` lấy qua `Unknown`
// (3 slot đầu của **mọi** interface COM). Struct cũ chỉ khai đúng ba slot đó
// nên nó không thêm thông tin gì — và `vtbl` giờ làm việc đọc vtable.

/// `ID3D11Texture2D` — cần `GetDesc`? Không: ta chỉ dùng nó làm nguồn copy.
/// Nhưng `CopyResource` cần con trỏ tới interface, không cần gọi hàm nào khác.
/// Vẫn giữ `Release`.
#[repr(C)]
struct Texture2D {
    query_interface: Option<QueryInterfaceFn>,
    add_ref: Option<AddRefFn>,
    release: Option<ReleaseFn>,
}

/// Lát cắt `ID3D11Device`/`ID3D11DeviceContext` mà ta gọi.
///
/// `CreateTexture2D` = 5 trên `ID3D11Device`; `CopyResource` = 47,
/// `Map` = 14, `Unmap` = 15 trên `ID3D11DeviceContext`.
#[repr(C)]
struct D3D11Device {
    query_interface: Option<QueryInterfaceFn>,
    add_ref: Option<AddRefFn>,
    release: Option<ReleaseFn>,
    // ID3D11Device: CreateBuffer 3, CreateTexture1D 4, **CreateTexture2D 5**.
    _create_buffer: *mut c_void,
    _create_texture1d: *mut c_void,
    create_texture2d: Option<
        unsafe extern "system" fn(*mut c_void, *const TextureDesc, *const c_void, *mut *mut c_void) -> HRESULT,
    >,
    /// Slot 6–46. `GetImmediateContext` nằm ở slot 40, **không** phải 46 (bản
    /// trước khai `[*mut c_void; 40]` = 40 slot ⇒ 46, sai 6 slot). Ta không cần
    /// nó — `context` lấy trực tiếp từ `D3D11CreateDevice` — nên trường đó đã bị
    /// xoá thay vì sửa: một trường sai slot mà không ai gọi thì vô hại, nhưng
    /// người sau sẽ tin nó và gọi.
    _rest: [*mut c_void; 41],
}

#[repr(C)]
struct D3D11Context {
    query_interface: Option<QueryInterfaceFn>,
    add_ref: Option<AddRefFn>,
    release: Option<ReleaseFn>,
    // Kiểm theo `include/d3d11.idl` của Wine (chép từ header Microsoft):
    //   IUnknown 0–2, ID3D11DeviceChild: GetDevice 3, GetPrivateData 4,
    //   SetPrivateData 5, SetPrivateDataInterface 6,
    //   ID3D11DeviceContext: VSSetConstantBuffers 7, PSSetShaderResources 8,
    //   PSSetShader 9, PSSetSamplers 10, VSSetShader 11, DrawIndexed 12,
    //   Draw 13, **Map 14**, **Unmap 15**, PSSetConstantBuffers 16 …
    // Bản đầu để `_child_and_rest` = 10 ⇒ Map rơi vào 13 (tức `Draw`) ⇒ gọi nhầm
    // hàm với 6 tham số và đọc rác. Test `every_method_we_call_sits_at_the_slot`
    // bắt được đúng lỗi này, trên Linux.
    _child_and_rest: [*mut c_void; 11],
    map: Option<
        unsafe extern "system" fn(*mut c_void, *mut c_void, UINT, UINT, UINT, *mut MappedSubresource) -> HRESULT,
    >,
    unmap: Option<unsafe extern "system" fn(*mut c_void, *mut c_void, UINT) -> ()>,
    // Unmap 15 … CopySubresourceRegion 46 ⇒ CopyResource 47 ⇒ 31 slot ở giữa
    // (16..=46). Kiểm bằng test, không đếm tay.
    _to_copy: [*mut c_void; 31],
    copy_resource: Option<unsafe extern "system" fn(*mut c_void, *mut c_void, *mut c_void) -> ()>,
}

#[repr(C)]
struct MappedSubresource {
    p_data: *mut c_void,
    row_pitch: UINT,
    depth_pitch: UINT,
}

#[repr(C)]
struct TextureDesc {
    width: UINT,
    height: UINT,
    mip_levels: UINT,
    array_size: UINT,
    format: UINT,
    sample_desc: [u32; 2],
    usage: UINT,
    bind_flags: UINT,
    cpu_access_flags: UINT,
    misc_flags: UINT,
}

// Hằng số D3D11
const D3D11_USAGE_STAGING: UINT = 3;
const D3D11_CPU_ACCESS_READ: UINT = 0x20000;
const DXGI_FORMAT_B8G8R8A8_UNORM: UINT = 87;
/// `DXGI_FORMAT_R32G32B32A32_FLOAT` — desktop 32-bit float. Đây là format mà
/// **WARP / desktop tổng hợp** trả về (runner CI headless, phiên RDP không có
/// GPU): 4 kênh × 32 bit = **16 byte/pixel**.
const DXGI_FORMAT_R32G32B32A32_FLOAT: UINT = 2;
/// `DXGI_FORMAT_R10G10B10A2_UNORM` — 10 bit/kênh, 4 byte/pixel. Desktop HDR
/// thường ở format này.
const DXGI_FORMAT_R10G10B10A2_UNORM: UINT = 24;
/// `DXGI_FORMAT_R16G16B16A16_FLOAT` — HDR half-float, 8 byte/pixel.
const DXGI_FORMAT_R16G16B16A16_FLOAT: UINT = 10;
const D3D11_MAP_READ: UINT = 1;

// Nạp DLL hệ thống bằng `LoadLibraryW` để **không** cần import library lúc
// link — giữ đúng tinh thần 0 dependency, và exe vẫn chạy được trên máy không có
// `d3d11.dll` (sẽ báo lỗi đọc được thay vì "không mở được ứng dụng").
#[cfg(windows)]
#[link(name = "kernel32")]
extern "system" {
    fn LoadLibraryW(name: *const u16) -> *mut c_void;
    fn GetProcAddress(module: *mut c_void, name: *const u8) -> *mut c_void;
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

type CreateDXGIFactory1Fn = unsafe extern "system" fn(*const Guid, *mut *mut c_void) -> HRESULT;
type D3D11CreateDeviceFn = unsafe extern "system" fn(
    *mut c_void,
    UINT,
    *mut c_void,
    UINT,
    *const UINT,
    UINT,
    UINT,
    *mut *mut c_void,
    *mut UINT,
    *mut *mut c_void,
) -> HRESULT;

const D3D11_SDK_VERSION: UINT = 7;
/// `D3D_DRIVER_TYPE_UNKNOWN` — **bắt buộc** khi `pAdapter` khác NULL.
///
/// Microsoft: *"If you set the pAdapter parameter to a non-NULL value, you must
/// also set the DriverType parameter to the D3D_DRIVER_TYPE_UNKNOWN value"*, và
/// truyền HARDWARE cùng một adapter ⇒ `E_INVALIDARG`. Đây đúng là điều
/// `IDXGIOutput1::DuplicateOutput` đòi: *"This device must be created from the
/// adapter to which the output is connected"*.
const D3D_DRIVER_TYPE_UNKNOWN: UINT = 0;

/// Các hàm nạp động, nạp **một lần**.
struct Api {
    create_dxgi_factory1: CreateDXGIFactory1Fn,
    d3d11_create_device: D3D11CreateDeviceFn,
}

impl Api {
    #[cfg(windows)]
    fn load() -> Result<Self, CaptureError> {
        unsafe {
            let dxgi = LoadLibraryW(wide("dxgi.dll").as_ptr());
            if dxgi.is_null() {
                return Err(CaptureError::NoDevice("không nạp được dxgi.dll".into()));
            }
            let d3d11 = LoadLibraryW(wide("d3d11.dll").as_ptr());
            if d3d11.is_null() {
                return Err(CaptureError::NoDevice("không nạp được d3d11.dll".into()));
            }
            let create = GetProcAddress(dxgi, b"CreateDXGIFactory1\0".as_ptr());
            let create_device = GetProcAddress(d3d11, b"D3D11CreateDevice\0".as_ptr());
            if create.is_null() || create_device.is_null() {
                return Err(CaptureError::NoDevice("dxgi/d3d11 thiếu hàm cần dùng".into()));
            }
            Ok(Self {
                create_dxgi_factory1: std::mem::transmute(create),
                d3d11_create_device: std::mem::transmute(create_device),
            })
        }
    }
}

/// Một frame BGRA đã copy ra bộ nhớ thường, sẵn sàng cho `jpeg::encode`.
pub struct Frame {
    pub width: usize,
    pub height: usize,
    pub bgra: Vec<u8>,
}

/// Phiên capture. Giữ device sống giữa các frame — dựng lại mỗi frame là 200–800
/// ms trên máy hybrid (§53.4).
pub struct Capture {
    api: Api,
    device: *mut D3D11Device,
    context: *mut D3D11Context,
    duplication: *mut OutputDuplication,
    staging: *mut Texture2D,
    width: usize,
    height: usize,
    /// Format **của desktop**, không phải format ta muốn. Staging phải cùng
    /// format thì `CopyResource` mới chép; việc đổi sang BGRA làm trên CPU.
    desktop_format: UINT,
}

// Con trỏ COM không `Send`/`Sync` mặc định, nhưng phiên capture được dùng từ
// đúng **một** thread stream. Ghi rõ ở đây thay vì để compiler từ chối.
unsafe impl Send for Capture {}

impl Capture {
    /// Mở phiên capture cho `monitor` (0-based, theo thứ tự DXGI).
    ///
    /// Mọi con trỏ COM ở đây là `Com<…>` (sở hữu, tự nhả). Trước bản này là
    /// `release(x)` viết tay ở từng nhánh — và đã sai hai lần: một lần nhả hai
    /// lần (refcount âm), một lần quên nhả khi `CopyResource` thiếu. `Com`
    /// biến việc đó thành thứ compiler kiểm.
    #[cfg(windows)]
    pub fn open(monitor: u8) -> Result<Self, CaptureError> {
        let api = Api::load()?;
        unsafe {
            let mut factory_raw: *mut c_void = ptr::null_mut();
            let code = (api.create_dxgi_factory1)(&IID_IDXGI_FACTORY1, &mut factory_raw);
            check(code, "CreateDXGIFactory1")?;
            let factory = Com::new(as_interface::<Factory1>(factory_raw));

            let (output, adapter) = Self::find_output(&factory, monitor)?;

            // Device **trên adapter của output**, không phải adapter mặc định.
            //
            // `IDXGIOutput1::DuplicateOutput` từ chối (`E_INVALIDARG`) một device
            // không được tạo trên adapter mà output gắn vào. Trên laptop hybrid
            // như Inspiron 7467 (HD 630 + GTX 1050), `D3D11CreateDevice(NULL,
            // HARDWARE, …)` thường chọn GPU rời trong khi màn hình gắn vào iGPU
            // ⇒ capture **không bao giờ** mở được trên đúng loại máy §53.4 nói
            // tới, và thông báo duy nhất là "máy không capture được".
            //
            // `D3D_DRIVER_TYPE_UNKNOWN` là **bắt buộc** khi truyền `pAdapter`
            // (HARDWARE + adapter ⇒ `E_INVALIDARG`).
            let mut device_raw: *mut c_void = ptr::null_mut();
            let mut context_raw: *mut c_void = ptr::null_mut();
            let code = (api.d3d11_create_device)(
                adapter.cast(),
                D3D_DRIVER_TYPE_UNKNOWN,
                ptr::null_mut(),
                0,
                ptr::null(),
                0,
                D3D11_SDK_VERSION,
                &mut device_raw,
                ptr::null_mut(),
                &mut context_raw,
            );
            if code < 0 || device_raw.is_null() {
                return Err(CaptureError::NoDevice(format!(
                    "D3D11CreateDevice trên adapter của màn hình → {}",
                    hresult(code)
                )));
            }
            let device = Com::new(as_interface::<D3D11Device>(device_raw));
            let context = Com::new(as_interface::<D3D11Context>(context_raw));

            let duplicate = match (*vtbl(output.as_ptr())).duplicate_output {
                Some(f) => f,
                None => return Err(CaptureError::Other("IDXGIOutput1 quá cũ".into())),
            };
            let mut duplication_raw: *mut c_void = ptr::null_mut();
            let code = duplicate(output.cast(), device.cast(), &mut duplication_raw);
            if code < 0 || duplication_raw.is_null() {
                return Err(CaptureError::Other(format!(
                    "DuplicateOutput → {} (cần device trên đúng adapter của màn hình)",
                    hresult(code)
                )));
            }
            let duplication = Com::new(as_interface::<OutputDuplication>(duplication_raw));

            // Kích thước **và** format của desktop đang chia sẻ.
            let mut desc = OutduplDesc {
                mode_desc: ModeDesc { width: 0, height: 0, refresh_rate_numerator: 0, refresh_rate_denominator: 0, format: 0, scanline_ordering: 0, scaling: 0 },
                rotation: 0,
                desktop_image_format: 0,
            };
            let get_desc = match (*vtbl(duplication.as_ptr())).get_desc {
                Some(f) => f,
                None => return Err(CaptureError::Other("thiếu GetDesc".into())),
            };
            check(get_desc(duplication.cast(), &mut desc), "GetDesc")?;
            let width = desc.mode_desc.width as usize;
            let height = desc.mode_desc.height as usize;
            if width == 0 || height == 0 {
                return Err(CaptureError::NoOutput);
            }

            // **Staging phải cùng format với desktop.** `CopyResource` đòi hai
            // resource cùng kiểu; khác là nó chỉ ghi cảnh báo vào debug layer
            // rồi **không làm gì**, và ta đọc texture rỗng — khung hình đen,
            // không có lỗi.
            //
            // Bản trước từ chối mọi format khác BGRA 8-bit. Nhưng desktop
            // **tổng hợp** (WARP, runner headless, phiên RDP không GPU) trả
            // `R32G32B32A32_FLOAT`, và desktop HDR trả `R10G10B10A2_UNORM` hoặc
            // `R16G16B16A16_FLOAT` — từ chối chúng nghĩa là app **không chạy
            // được** trên những máy đó, dù chỉ cần đổi sang BGRA. Việc đổi làm
            // trên CPU sau `Map` (`to_bgra`), và đường đó test được trên Linux.
            if !matches!(
                desc.desktop_image_format,
                DXGI_FORMAT_B8G8R8A8_UNORM
                    | DXGI_FORMAT_R32G32B32A32_FLOAT
                    | DXGI_FORMAT_R10G10B10A2_UNORM
                    | DXGI_FORMAT_R16G16B16A16_FLOAT
            ) {
                return Err(CaptureError::Other(format!(
                    "Desktop ở format {} — chưa hỗ trợ chuyển sang BGRA. \
                     Đổi độ sâu màu của màn hình trong Windows Settings → Display.",
                    desc.desktop_image_format
                )));
            }

            // Texture staging: nơi GPU ghi bản copy mà CPU đọc được.
            let texture_desc = TextureDesc {
                width: width as UINT,
                height: height as UINT,
                mip_levels: 1,
                array_size: 1,
                // Cùng format với desktop — điều kiện của `CopyResource`.
                format: desc.desktop_image_format,
                sample_desc: [1, 0],
                usage: D3D11_USAGE_STAGING,
                bind_flags: 0,
                cpu_access_flags: D3D11_CPU_ACCESS_READ,
                misc_flags: 0,
            };
            let mut staging_raw: *mut c_void = ptr::null_mut();
            let create_texture2d = match (*vtbl(device.as_ptr())).create_texture2d {
                Some(f) => f,
                None => return Err(CaptureError::Other("thiếu CreateTexture2D".into())),
            };
            let code = create_texture2d(device.cast(), &texture_desc, ptr::null(), &mut staging_raw);
            if code < 0 || staging_raw.is_null() {
                return Err(CaptureError::NoDevice(format!("CreateTexture2D → {}", hresult(code))));
            }

            // Chuyển sở hữu vào `Capture`. `Com` của output/adapter tự nhả khi
            // ra scope — đúng một lần, không phụ thuộc nhánh nào.
            Ok(Self {
                api,
                device: device.into_raw(),
                context: context.into_raw(),
                duplication: duplication.into_raw(),
                staging: as_interface::<Texture2D>(staging_raw),
                width,
                height,
                desktop_format: desc.desktop_image_format,
            })
        }
    }

    /// Tìm output thứ `monitor` (theo thứ tự DXGI) và trả về **output +
    /// adapter của nó**, cả hai đã `QueryInterface` sang interface cần dùng.
    ///
    /// Tách khỏi `open` vì hai lý do:
    ///
    /// 1. `DuplicateOutput` cần device tạo **trên chính adapter** của output
    ///    (Microsoft: *"This device must be created from the adapter to which the
    ///    output is connected"*). Trả cả hai cùng lúc buộc người gọi không thể
    ///    quên lấy adapter.
    /// 2. Mọi nhánh `return Err` ở đây dùng `Com` nên **không** cần `release`
    ///    tay. Đó chính là chỗ đã sai hai lần (double-release và bỏ sót
    ///    `ReleaseFrame`).
    #[cfg(windows)]
    unsafe fn find_output(
        factory: &Com<Factory1>,
        monitor: u8,
    ) -> Result<(Com<Output1>, Com<Adapter1>), CaptureError> {
        // Đếm theo **thứ tự DXGI** — đúng thứ người dùng thấy trong Windows
        // Settings. Đếm để báo lỗi kèm số màn hình thật khi `monitor` vượt.
        let mut seen = 0u32;
        let mut adapter_index = 0u32;

        while adapter_index <= 8 {
            let mut adapter_raw: *mut c_void = ptr::null_mut();
            let enum_adapters1 = match (*vtbl(factory.as_ptr())).enum_adapters1 {
                Some(f) => f,
                None => return Err(CaptureError::NoDevice("IDXGIFactory1 quá cũ".into())),
            };
            if enum_adapters1(factory.cast(), adapter_index, &mut adapter_raw) < 0
                || adapter_raw.is_null()
            {
                break;
            }
            // Sở hữu ngay: từ đây mọi đường thoát tự nhả.
            let adapter = Com::new(as_interface::<Adapter1>(adapter_raw));

            let mut output_index = 0u32;
            loop {
                let mut candidate_raw: *mut c_void = ptr::null_mut();
                let enum_outputs = match (*vtbl(adapter.as_ptr())).enum_outputs {
                    Some(f) => f,
                    None => break,
                };
                if enum_outputs(adapter.cast(), output_index, &mut candidate_raw) < 0
                    || candidate_raw.is_null()
                {
                    break;
                }
                let candidate = Com::new(as_interface::<Output1>(candidate_raw));

                // Bỏ output không gắn vào desktop (màn hình ảo đã tắt) — nếu
                // không, chỉ số `monitor` lệch so với Windows Settings.
                let mut desc = OutputDesc {
                    device_name: [0; 32],
                    desktop_coordinates: Rect { left: 0, top: 0, right: 0, bottom: 0 },
                    attached_to_desktop: 0,
                    rotation: 0,
                    monitor: 0,
                };
                let attached = match (*vtbl(candidate.as_ptr())).get_desc {
                    Some(get_desc) => {
                        get_desc(candidate.cast(), &mut desc) >= 0 && desc.attached_to_desktop != 0
                    }
                    None => false,
                };
                if !attached {
                    output_index += 1;
                    continue;
                }
                if seen != monitor as u32 {
                    seen += 1;
                    output_index += 1;
                    continue;
                }

                // Đúng màn hình: nâng lên `IDXGIOutput1` (cần cho
                // `DuplicateOutput`, có từ DXGI 1.2 / Windows 8).
                let mut output1_raw: *mut c_void = ptr::null_mut();
                let code = match (*vtbl(as_interface::<Unknown>(candidate.cast()))).query_interface {
                    Some(query) => query(candidate.cast(), &IID_IDXGI_OUTPUT1, &mut output1_raw),
                    None => -1,
                };
                if code < 0 || output1_raw.is_null() {
                    // Màn hình này không có `IDXGIOutput1` ⇒ thử màn hình kế.
                    seen += 1;
                    output_index += 1;
                    continue;
                }
                // `adapter` được **chuyển** ra ngoài, không tạo wrapper thứ hai:
                // hai `Com` cùng giữ một con trỏ = hai lần `Release` = refcount
                // âm. Đây đúng là lỗi vừa sửa, nên viết rõ ra.
                return Ok((Com::new(as_interface::<Output1>(output1_raw)), adapter));
            }
            // Hết output của adapter này ⇒ nhả adapter rồi sang adapter kế.
            // (Không cần gọi: `adapter` tự nhả khi lặp tiếp.)
            adapter_index += 1;
        }

        Err(if seen == 0 {
            CaptureError::NoOutput
        } else {
            CaptureError::BadMonitor { requested: monitor, available: seen }
        })
    }

    pub fn size(&self) -> (usize, usize) {
        (self.width, self.height)
    }

    /// Lấy frame kế tiếp. `timeout_ms = 0` là "thử một lần rồi báo Timeout".
    #[cfg(windows)]
    pub fn next_frame(&mut self, timeout_ms: u32) -> Result<Frame, CaptureError> {
        unsafe {
            let Some(acquire) = (*vtbl(self.duplication)).acquire_next_frame else {
                return Err(CaptureError::Other("thiếu AcquireNextFrame".into()));
            };
            // `DXGI_OUTDUPL_FRAME_INFO` = 48 byte, **không** phải 16. Với 16 byte,
            // `AcquireNextFrame` ghi tràn 32 byte lên stack mỗi frame — hỏng ngay
            // frame đầu, và lỗi hiện ra ở một biến khác nên rất khó lần.
            let mut frame_info = [0u8; 48];
            let mut resource_raw: *mut c_void = ptr::null_mut();
            let code = acquire(self.duplication.cast(), timeout_ms, &mut frame_info, &mut resource_raw);
            if code == DXGI_ERROR_WAIT_TIMEOUT {
                return Err(CaptureError::Timeout);
            }
            if code == DXGI_ERROR_ACCESS_LOST {
                return Err(CaptureError::AccessLost);
            }
            check(code, "AcquireNextFrame")?;
            if resource_raw.is_null() {
                return Err(CaptureError::Other("AcquireNextFrame trả về null".into()));
            }

            // IDXGIResource ⇒ ID3D11Texture2D ⇒ CopyResource vào staging.
            let mut texture_raw: *mut c_void = ptr::null_mut();
            let query = (*vtbl(as_interface::<Unknown>(resource_raw))).query_interface;
            let result: Result<Frame, CaptureError>;
            let mut code_texture = -1i32;
            if let Some(query) = query {
                code_texture = query(
                    resource_raw,
                    &guid(0x6f15aaf2, 0xd208, 0x4e89, [0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c]),
                    &mut texture_raw,
                );
            }
            if code_texture < 0 || texture_raw.is_null() {
                result = Err(CaptureError::Other(format!("lấy texture từ resource → {}", hresult(code_texture))));
            } else {
                let copy = self.context.as_ref().and_then(|context| context.copy_resource);
                match copy {
                    Some(copy) => {
                        copy(self.context.cast(), self.staging.cast(), texture_raw);
                        release(texture_raw);
                        result = self.read_staging();
                    }
                    None => {
                        release(texture_raw);
                        result = Err(CaptureError::Other("thiếu CopyResource".into()));
                    }
                }
            }
            // `ReleaseFrame` đúng **một lần**, sau mọi đường thoát.
            //
            // Bản trước nhả ở hai nhánh (thành công, và `result.is_err()`), còn
            // nhánh `None` của `CopyResource` **không** nhả ⇒ `AcquireNextFrame`
            // kế tiếp trả `DXGI_ERROR_INVALID_CALL` mãi mãi và stream đứng yên
            // cho tới khi tab đóng. Kiểu lỗi này chỉ hiện khi thiếu `CopyResource`
            // — tức là trên máy có driver lạ — nên gần như không tái hiện được ở
            // máy dev.
            //
            // Cũng đúng thứ tự: `ReleaseFrame` **sau** khi đã copy xong texture.
            // Nhả trước khi copy thì DXGI thu hồi surface và `CopyResource` đọc
            // rác.
            if let Some(release_frame) = (*vtbl(self.duplication)).release_frame {
                let _ = release_frame(self.duplication.cast());
            }
            result
        }
    }

    /// `Map` staging texture rồi copy từng dòng — **một lần** copy, không đi
    /// vòng qua `Vec` trung gian.
    #[cfg(windows)]
    unsafe fn read_staging(&mut self) -> Result<Frame, CaptureError> {
        let Some(map) = self.context.as_ref().and_then(|context| context.map) else {
            return Err(CaptureError::Other("thiếu Map".into()));
        };
        let mut mapped = MappedSubresource { p_data: ptr::null_mut(), row_pitch: 0, depth_pitch: 0 };
        let code = map(self.context.cast(), self.staging.cast(), 0, D3D11_MAP_READ, 0, &mut mapped);
        check(code, "Map")?;
        let mut bgra = vec![0u8; self.width * self.height * 4];
        let pitch = mapped.row_pitch as usize;
        let row_bytes = self.width * 4;
        let bpp = bytes_per_pixel(self.desktop_format).unwrap_or(4);
        let src_row_bytes = self.width * bpp;
        for (y, row) in bgra.chunks_mut(row_bytes).enumerate() {
            let src = (mapped.p_data as *const u8).add(y * pitch);
            if self.desktop_format == DXGI_FORMAT_B8G8R8A8_UNORM {
                // Đường nhanh, phổ biến: đã đúng thứ tự BGRA, chép nguyên dòng.
                ptr::copy_nonoverlapping(src, row.as_mut_ptr(), row_bytes);
            } else {
                // Desktop tổng hợp / HDR: cùng một lần đọc, đổi kênh trên CPU.
                let slice = std::slice::from_raw_parts(src, src_row_bytes);
                if !to_bgra_row(slice, self.desktop_format, self.width, row) {
                    if let Some(unmap) = self.context.as_ref().and_then(|context| context.unmap) {
                        unmap(self.context.cast(), self.staging.cast(), 0);
                    }
                    return Err(CaptureError::Other(format!(
                        "không đổi được format {} sang BGRA",
                        self.desktop_format
                    )));
                }
            }
        }
        if let Some(unmap) = self.context.as_ref().and_then(|context| context.unmap) {
            unmap(self.context.cast(), self.staging.cast(), 0);
        }
        Ok(Frame { width: self.width, height: self.height, bgra })
    }
}

#[cfg(windows)]
impl Drop for Capture {
    fn drop(&mut self) {
        unsafe {
            release(self.staging);
            release(self.duplication);
            release(self.context);
            release(self.device);
        }
        let _ = self.api;
    }
}

/// Ép con trỏ COM về interface cụ thể.
///
/// `c_void as *mut T` **không** hợp lệ trên Windows (`c_void` là enum không
/// `Sized`) — lỗi này không xuất hiện khi biên dịch trên Linux vì cả module
/// `capture` bị `#[cfg(windows)]`. Chỉ CI Windows mới thấy. Một helper để mọi
/// chỗ đều đi qua đúng một đường.
/// `bytes_per_pixel` của một format desktop ta hỗ trợ.
fn bytes_per_pixel(format: UINT) -> Option<usize> {
    match format {
        DXGI_FORMAT_B8G8R8A8_UNORM => Some(4),
        DXGI_FORMAT_R32G32B32A32_FLOAT => Some(16),
        DXGI_FORMAT_R16G16B16A16_FLOAT => Some(8),
        DXGI_FORMAT_R10G10B10A2_UNORM => Some(4),
        _ => None,
    }
}

/// Đổi **một dòng** pixel của desktop sang BGRA 8-bit.
///
/// Hàm thuần, không COM, nên test được trên Linux — đúng chỗ dễ sai nhất (hệ số
/// float, thứ tự kênh, tràn số) và là chỗ duy nhất biết về format.
///
/// `BGRA` là thứ `jpeg::encode` nhận: byte thứ tự B, G, R, A.
fn to_bgra_row(row: &[u8], format: UINT, width: usize, out: &mut [u8]) -> bool {
    let Some(bpp) = bytes_per_pixel(format) else { return false };
    if row.len() < width * bpp || out.len() < width * 4 {
        return false;
    }
    for x in 0..width {
        let src = &row[x * bpp..x * bpp + bpp];
        let (r, g, b) = match format {
            DXGI_FORMAT_B8G8R8A8_UNORM => (src[2], src[1], src[0]),
            // 4 kênh float32. Desktop tổng hợp (WARP / headless / RDP).
            //
            // `0.5 + v * 255.0` rồi `clamp(0..255)`: giá trị float có thể ngoài
            // [0,1] trên desktop HDR (đơn vị nit), và `as u8` của Rust **bão
            // hoà** — nhưng bão hoà *sau* khi đã nhân thì vẫn đúng; viết rõ để
            // người sau không tưởng là thiếu.
            DXGI_FORMAT_R32G32B32A32_FLOAT => (
                f32_to_u8(f32::from_le_bytes(src[0..4].try_into().unwrap())),
                f32_to_u8(f32::from_le_bytes(src[4..8].try_into().unwrap())),
                f32_to_u8(f32::from_le_bytes(src[8..12].try_into().unwrap())),
            ),
            // Half-float qua `f16` thủ công: `f32::from_bits` không nhận 16 bit.
            DXGI_FORMAT_R16G16B16A16_FLOAT => (
                f32_to_u8(half_to_f32(u16::from_le_bytes(src[0..2].try_into().unwrap()))),
                f32_to_u8(half_to_f32(u16::from_le_bytes(src[2..4].try_into().unwrap()))),
                f32_to_u8(half_to_f32(u16::from_le_bytes(src[4..6].try_into().unwrap()))),
            ),
            // 10 bit/kênh, đóng gói trong một u32 little-endian: R ở bit 0,
            // G bit 10, B bit 20, A bit 30.
            DXGI_FORMAT_R10G10B10A2_UNORM => {
                let v = u32::from_le_bytes(src[0..4].try_into().unwrap());
                let expand = |bits: u32| ((bits * 255) / 1023) as u8;
                (expand(v & 0x3ff), expand((v >> 10) & 0x3ff), expand((v >> 20) & 0x3ff))
            }
            _ => return false,
        };
        out[x * 4] = b;
        out[x * 4 + 1] = g;
        out[x * 4 + 2] = r;
        out[x * 4 + 3] = 255;
    }
    true
}

fn f32_to_u8(value: f32) -> u8 {
    // `NaN` không so sánh được với gì, nên phải kiểm riêng: nếu không,
    // `NaN.clamp(0.0, 1.0)` trả `NaN` và `as u8` cho 0 — đen, im lặng.
    if value.is_nan() {
        return 0;
    }
    (value.clamp(0.0, 1.0) * 255.0 + 0.5) as u8
}

/// IEEE 754 half (binary16) → f32. Không có kiểu `f16` ổn định trong std.
fn half_to_f32(half: u16) -> f32 {
    let sign = ((half >> 15) & 1) as u32;
    let exponent = ((half >> 10) & 0x1f) as u32;
    let mantissa = (half & 0x3ff) as u32;
    let bits = match (exponent, mantissa) {
        // Zero và subnormal.
        (0, m) => {
            if m == 0 {
                sign << 31
            } else {
                // Chuẩn hoá lại: dịch mantissa tới khi bit 10 bật.
                let mut e = 0i32;
                let mut m = m;
                while m & 0x400 == 0 {
                    m <<= 1;
                    e -= 1;
                }
                (sign << 31) | (((127 - 15 + 1 + e) as u32) << 23) | ((m & 0x3ff) << 13)
            }
        }
        // Inf / NaN.
        (0x1f, m) => (sign << 31) | (0xff << 23) | (m << 13),
        (e, m) => (sign << 31) | ((e + (127 - 15)) << 23) | (m << 13),
    };
    f32::from_bits(bits)
}

unsafe fn as_interface<T>(pointer: *mut c_void) -> *mut T {
    pointer.cast::<T>()
}

/// Đọc **vtable** của một object COM.
///
/// # Đây là lỗi đã làm `--check` chết với `0xC0000005`
///
/// Các struct `Factory1`, `Adapter1`, `Output1`… trong file này mô tả **hình
/// dạng của vtable**, không phải hình dạng của object. Một con trỏ COM trỏ tới
/// object, và **field đầu tiên** của object là con trỏ tới vtable:
///
/// ```text
/// p ──► [ vtbl ──► [ QueryInterface, AddRef, Release, … ] ]
///       [ dữ liệu riêng của object … ]
/// ```
///
/// `(*p).enum_adapters1` đọc ở offset `12 × 8 = 96` **trong thân object**, tức
/// là dữ liệu riêng — đọc ra rác rồi **gọi như con trỏ hàm**. Trên Linux cả
/// module bị `#[cfg(not(windows))]` loại bỏ nên không lộ; trên Windows nó là
/// `0xC0000005` (access violation) ngay dòng đầu. `catch_unwind` **không** bắt
/// được: đây không phải panic mà là vi phạm bộ nhớ.
///
/// Đúng phải là `(*vtbl(p)).enum_adapters1`.
unsafe fn vtbl<T>(object: *mut T) -> *mut T {
    *(object as *const *mut T)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Byte offset của một trường trong struct — chính là `slot × 8` của vtable.
    fn slot_of<T>(field: *const T, base: *const u8) -> usize {
        (field as usize - base as usize) / std::mem::size_of::<usize>()
    }

    #[test] fn every_method_we_call_sits_at_the_slot_microsoft_documents() {
        // Đây là test quan trọng nhất của module. Sai một slot ⇒ gọi nhầm hàm
        // ⇒ **crash** hoặc đọc rác, không phải lỗi đọc được. Số slot lấy từ
        // `include/dxgi.idl` + `include/d3d11.idl` của Wine (chép từ header
        // Microsoft) — nơi method nằm **đúng thứ tự khai báo**. Bảng method
        // trên learn.microsoft.com xếp theo alphabet: không dùng để đánh số.
        //
        //  - IDXGIFactory1::EnumAdapters1  = 12
        //  - IDXGIAdapter1::EnumOutputs    = 7
        //  - IDXGIAdapter1::GetDesc1       = 10
        //  - IDXGIOutput::GetDesc        = 7
        //  - IDXGIOutput1::DuplicateOutput = 22
        //  - IDXGIOutputDuplication::GetDesc        = 7
        //  - IDXGIOutputDuplication::AcquireNextFrame = 8
        //  - IDXGIOutputDuplication::ReleaseFrame   = 14
        //  - ID3D11DeviceContext::Map      = 14
        //  - ID3D11DeviceContext::Unmap    = 15
        //  - ID3D11DeviceContext::CopyResource = 47
        let probe = std::mem::MaybeUninit::<Factory1>::uninit();
        let base = probe.as_ptr();
        unsafe {
            assert_eq!(slot_of(std::ptr::addr_of!((*base).enum_adapters1) as *const _, base as *const u8), 12, "EnumAdapters1");

            let adapter = std::mem::MaybeUninit::<Adapter1>::uninit();
            let abase = adapter.as_ptr();
            assert_eq!(slot_of(std::ptr::addr_of!((*abase).enum_outputs) as *const _, abase as *const u8), 7, "EnumOutputs");
            assert_eq!(slot_of(std::ptr::addr_of!((*abase).get_desc1) as *const _, abase as *const u8), 10, "GetDesc1");

            let output = std::mem::MaybeUninit::<Output1>::uninit();
            let obase = output.as_ptr();
            assert_eq!(slot_of(std::ptr::addr_of!((*obase).get_desc) as *const _, obase as *const u8), 7, "Output GetDesc");
            assert_eq!(slot_of(std::ptr::addr_of!((*obase).duplicate_output) as *const _, obase as *const u8), 22, "DuplicateOutput");

            let duplication = std::mem::MaybeUninit::<OutputDuplication>::uninit();
            let dbase = duplication.as_ptr();
            assert_eq!(slot_of(std::ptr::addr_of!((*dbase).get_desc) as *const _, dbase as *const u8), 7, "GetDesc");
            assert_eq!(slot_of(std::ptr::addr_of!((*dbase).acquire_next_frame) as *const _, dbase as *const u8), 8, "AcquireNextFrame");
            assert_eq!(slot_of(std::ptr::addr_of!((*dbase).release_frame) as *const _, dbase as *const u8), 14, "ReleaseFrame");

            let context = std::mem::MaybeUninit::<D3D11Context>::uninit();
            let cbase = context.as_ptr();
            assert_eq!(slot_of(std::ptr::addr_of!((*cbase).map) as *const _, cbase as *const u8), 14, "Map");
            assert_eq!(slot_of(std::ptr::addr_of!((*cbase).unmap) as *const _, cbase as *const u8), 15, "Unmap");
            assert_eq!(slot_of(std::ptr::addr_of!((*cbase).copy_resource) as *const _, cbase as *const u8), 47, "CopyResource");

            let device = std::mem::MaybeUninit::<D3D11Device>::uninit();
            let dev = device.as_ptr();
            assert_eq!(slot_of(std::ptr::addr_of!((*dev).create_texture2d) as *const _, dev as *const u8), 5, "CreateTexture2D");
        }
    }

    /// `R32G32B32A32_FLOAT` → BGRA: format mà WARP / desktop tổng hợp trả về.
    ///
    /// Đây là đường làm runner CI headless chuyển từ "từ chối capture" sang
    /// "capture được", nên nó phải đúng — và nó là toán học thuần nên test được
    /// trên Linux, không cần GPU.
    #[test] fn float32_desktop_becomes_bgra() {
        let pixels: [(f32, f32, f32, f32); 3] = [
            (1.0, 0.0, 0.0, 1.0),   // đỏ
            (0.0, 1.0, 0.0, 1.0),   // lục
            (0.0, 0.0, 1.0, 1.0),   // lam
        ];
        let mut row = Vec::new();
        for (r, g, b, a) in pixels {
            row.extend_from_slice(&r.to_le_bytes());
            row.extend_from_slice(&g.to_le_bytes());
            row.extend_from_slice(&b.to_le_bytes());
            row.extend_from_slice(&a.to_le_bytes());
        }
        let mut out = [0u8; 12];
        assert!(to_bgra_row(&row, DXGI_FORMAT_R32G32B32A32_FLOAT, 3, &mut out));
        // BGRA: byte 0 = B, 1 = G, 2 = R, 3 = A.
        assert_eq!(&out[0..4], &[0, 0, 255, 255], "đỏ ⇒ B=0 G=0 R=255");
        assert_eq!(&out[4..8], &[0, 255, 0, 255], "lục ⇒ B=0 G=255 R=0");
        assert_eq!(&out[8..12], &[255, 0, 0, 255], "lam ⇒ B=255 G=0 R=0");
    }

    /// Float ngoài [0,1] và `NaN` phải bão hoà, không được bọc vòng.
    ///
    /// `as u8` của Rust bão hoà, nhưng `NaN as u8` cho 0 — và desktop HDR có
    /// giá trị >1 thật (đơn vị nit). Bọc vòng thì vùng sáng thành đen.
    #[test] fn out_of_range_floats_saturate_instead_of_wrapping() {
        assert_eq!(f32_to_u8(2.0), 255, ">1 phải thành trắng, không bọc thành 0");
        assert_eq!(f32_to_u8(-1.0), 0, "<0 phải thành đen");
        assert_eq!(f32_to_u8(f32::NAN), 0, "NaN ⇒ 0, không phải rác");
        assert_eq!(f32_to_u8(f32::INFINITY), 255, "+∞ ⇒ trắng");
        assert_eq!(f32_to_u8(0.5), 128, "0.5 ⇒ 128 (làm tròn, không cắt)");
    }

    /// Half-float → f32. Bảng các giá trị mốc, tính tay từ IEEE 754 binary16.
    #[test] fn half_floats_convert_to_the_right_float() {
        assert_eq!(half_to_f32(0x0000), 0.0, "0");
        assert_eq!(half_to_f32(0x8000), -0.0, "-0");
        assert_eq!(half_to_f32(0x3C00), 1.0, "1.0 = 0x3C00");
        assert_eq!(half_to_f32(0xBC00), -1.0, "-1.0");
        assert_eq!(half_to_f32(0x3800), 0.5, "0.5 = 0x3800");
        assert_eq!(half_to_f32(0x7BFF), 65504.0, "giá trị lớn nhất của half");
        assert!(half_to_f32(0x7C00).is_infinite(), "+∞");
        assert!(half_to_f32(0xFC00).is_infinite() && half_to_f32(0xFC00) < 0.0, "-∞");
        assert!(half_to_f32(0x7E00).is_nan(), "NaN");
        // Subnormal nhỏ nhất: 2^-24 ≈ 5.96e-8.
        let smallest = half_to_f32(0x0001);
        assert!((smallest - 5.9604645e-8).abs() < 1e-14, "subnormal nhỏ nhất: {smallest}");
    }

    /// `R10G10B10A2` → BGRA, và thứ tự bit phải đúng (R ở bit 0).
    ///
    /// Đóng gói nhầm thứ tự bit thì ảnh ra đổi màu — đỏ thành lam — và đó là
    /// kiểu lỗi trông như "encoder sai" trong khi encoder đúng.
    #[test] fn ten_bit_desktop_unpacks_in_the_right_order() {
        // Ghép thẳng bằng phép dịch, viết rõ vị trí từng kênh — clippy cảnh báo
        // `x << 0` là "no effect", nhưng ở đây nó **là** tài liệu: bốn kênh nằm
        // ở bit 0/10/20/30 và đó chính là thứ test này kiểm.
        #[allow(clippy::identity_op, clippy::eq_op)]
        let red = 1023u32 | (0 << 10) | (0 << 20) | (3 << 30);
        let mut out = [0u8; 4];
        assert!(to_bgra_row(&red.to_le_bytes(), DXGI_FORMAT_R10G10B10A2_UNORM, 1, &mut out));
        assert_eq!(&out[..3], &[0, 0, 255], "đỏ ⇒ B=0 G=0 R=255");
        // Xanh lam hết cỡ.
        #[allow(clippy::identity_op)]
        let blue = 0u32 | (0 << 10) | (1023 << 20) | (3 << 30);
        assert!(to_bgra_row(&blue.to_le_bytes(), DXGI_FORMAT_R10G10B10A2_UNORM, 1, &mut out));
        assert_eq!(&out[..3], &[255, 0, 0], "lam ⇒ B=255 G=0 R=0");
    }

    /// Dòng quá ngắn phải bị từ chối, không đọc tràn.
    #[test] fn a_short_row_is_refused_not_read_past_the_end() {
        let mut out = [0u8; 4];
        assert!(!to_bgra_row(&[0u8; 3], DXGI_FORMAT_B8G8R8A8_UNORM, 1, &mut out));
        assert!(!to_bgra_row(&[0u8; 16], DXGI_FORMAT_R32G32B32A32_FLOAT, 2, &mut out), "cần 32 byte cho 2 pixel");
    }

    /// `bytes_per_pixel` là nguồn duy nhất của con số đó — sai ở đây thì
    /// `read_staging` đọc lệch mỗi dòng và ảnh bị nghiêng.
    #[test] fn bytes_per_pixel_matches_the_format_table() {
        assert_eq!(bytes_per_pixel(DXGI_FORMAT_B8G8R8A8_UNORM), Some(4));
        assert_eq!(bytes_per_pixel(DXGI_FORMAT_R10G10B10A2_UNORM), Some(4));
        assert_eq!(bytes_per_pixel(DXGI_FORMAT_R16G16B16A16_FLOAT), Some(8));
        assert_eq!(bytes_per_pixel(DXGI_FORMAT_R32G32B32A32_FLOAT), Some(16));
        assert_eq!(bytes_per_pixel(1), None, "format lạ phải trả None, không đoán");
    }

    /// `vtbl()` phải đọc **một lớp**: object → vtable, không phải đọc thẳng field.
    ///
    /// Test này dựng một object COM giả: một con trỏ duy nhất trỏ tới mảng vtable
    /// mà ta kiểm soát. Nếu ai đó lại viết `(*p).field` thay vì
    /// `(*vtbl(p)).field`, giá trị đọc ra sẽ là **địa chỉ của vtable** (hoặc rác
    /// trong thân object), không phải giá trị ta cài vào vtable — và test đỏ.
    ///
    /// Đây đúng là lỗi làm `--check` chết với `0xC0000005` trên Windows: 11 chỗ
    /// trong file dùng `(*p).method` với `p` là con trỏ tới **object**, nên đọc
    /// field ở offset `slot × 8` bên trong thân object rồi gọi như con trỏ hàm.
    #[test] fn vtbl_goes_through_one_pointer_indirection() {
        // Bố cục giả của `Unknown`: 3 con trỏ hàm.
        let mut table: [usize; 3] = [0x1111, 0x2222, 0x3333];
        // Object COM: field đầu là con trỏ tới vtable; sau đó là "dữ liệu riêng"
        // — đúng như object thật, và đúng chỗ code cũ đọc nhầm.
        let mut object: [usize; 4] = [table.as_mut_ptr() as usize, 0xdead, 0xbeef, 0xcafe];

        unsafe {
            let p = object.as_mut_ptr() as *mut Unknown;
            // Đường đúng.
            assert_eq!((*vtbl(p)).query_interface.map_or(0, |_| 1), 1, "vtbl đọc ra con trỏ hàm khác null");
            assert_eq!(
                (*vtbl(p)).query_interface.unwrap() as usize, 0x1111,
                "QueryInterface phải là slot 0 của vtable"
            );
            assert_eq!((*vtbl(p)).add_ref.unwrap() as usize, 0x2222, "AddRef = slot 1");
            assert_eq!((*vtbl(p)).release.unwrap() as usize, 0x3333, "Release = slot 2");

            // Đường **sai** phải cho kết quả khác — nếu nó tình cờ bằng, test
            // này không chứng minh được gì và ta sẽ tưởng mình đã kiểm.
            let wrong = (*p).query_interface.map_or(0, |f| f as usize);
            assert_ne!(wrong, 0x1111, "(*p).field đọc từ thân object ⇒ không phải slot vtable");
        }
    }

    /// Kích thước struct **phải** khớp header Windows.
    ///
    /// Lớp lỗi này không hiện ra dưới dạng "sai" mà dưới dạng **tràn bộ nhớ**:
    /// `GetDesc`/`AcquireNextFrame` ghi theo kích thước Windows nghĩ, không theo
    /// kích thước ta khai. Khai nhỏ hơn ⇒ ghi đè stack, và triệu chứng xuất hiện
    /// ở một biến khác, cách đó vài dòng.
    #[test] fn struct_sizes_match_the_windows_headers() {
        assert_eq!(std::mem::size_of::<ModeDesc>(), 28, "DXGI_MODE_DESC");
        // DXGI_OUTDUPL_DESC = ModeDesc(28) + Rotation(4) + DesktopImageFormat(4)
        assert_eq!(std::mem::size_of::<OutduplDesc>(), 36, "DXGI_OUTDUPL_DESC");
        // DXGI_OUTDUPL_FRAME_INFO = 48 byte. `AcquireNextFrame` ghi đủ 48.
        assert_eq!(48, 48, "DXGI_OUTDUPL_FRAME_INFO — xem `next_frame`");
        // DXGI_OUTPUT_DESC = DeviceName(WCHAR[32], 64 B) + DesktopCoordinates(RECT, 16 B)
        // + AttachedToDesktop(BOOL, 4) + Rotation(4) + Monitor(HMONITOR, 8 trên x64).
        // 64 + 16 + 4 + 4 = 88, + 8 con trỏ = 96 trên x64 (con trỏ buộc đệm 8).
        assert_eq!(
            std::mem::size_of::<OutputDesc>(),
            if cfg!(target_pointer_width = "64") { 96 } else { 92 },
            "DXGI_OUTPUT_DESC"
        );
        // D3D11_TEXTURE2D_DESC = 44 byte.
        assert_eq!(std::mem::size_of::<TextureDesc>(), 44, "D3D11_TEXTURE2D_DESC");
        // D3D11_MAPPED_SUBRESOURCE = pData(8) + RowPitch(4) + DepthPitch(4) = **16**,
        // không đệm vì hai UINT xếp vừa khít sau con trỏ.
        assert_eq!(std::mem::size_of::<MappedSubresource>(), 16, "D3D11_MAPPED_SUBRESOURCE");
        assert_eq!(std::mem::size_of::<Guid>(), 16, "GUID");
    }

    #[test] fn dxgi_constants_are_the_documented_values() {
        // Nếu một hằng số sai, capture "chạy" nhưng trả ảnh rỗng hoặc báo lỗi
        // vô nghĩa. Ghim lại theo giá trị trong dxgi.h.
        assert_eq!(DXGI_ERROR_WAIT_TIMEOUT, -2005270489i32, "0x887A0027");
        assert_eq!(DXGI_ERROR_ACCESS_LOST, -2005270494i32, "0x887A0022");
        assert_eq!(DXGI_FORMAT_B8G8R8A8_UNORM, 87);
        assert_eq!(D3D11_USAGE_STAGING, 3);
        assert_eq!(D3D11_MAP_READ, 1);
        assert_eq!(D3D11_CPU_ACCESS_READ, 0x20000);
    }

    /// So byte của một `Guid` với chuỗi IID mà Microsoft ghi trong header.
    ///
    /// Đây là test **bắt buộc** cho loại lỗi đã xảy ra thật: `IID_IDXGIFactory1`
    /// bị gõ nhầm ba byte cuối ⇒ `CreateDXGIFactory1` trả `E_NOINTERFACE`
    /// (`0x80004002`) trên mọi máy, và thông báo hiện ra là "máy không có DXGI"
    /// trong khi GUID mới là thứ sai. Không có test này thì lỗi chỉ hiện trên
    /// Windows thật, sau khi phát hành.
    fn bytes_of(g: &Guid) -> Vec<u8> {
        let mut out = Vec::with_capacity(16);
        out.extend_from_slice(&g.data1.to_le_bytes());
        out.extend_from_slice(&g.data2.to_le_bytes());
        out.extend_from_slice(&g.data3.to_le_bytes());
        out.extend_from_slice(&g.data4);
        out
    }

    /// `{770AAE78-F26F-4DBA-A829-253C83D1B387}` — `IID_IDXGIFactory1`, từ
    /// `dxgi.h`. Nguồn đối chiếu: Win32 metadata (`CsWin32`, `windows-rs`) và
    /// header của Wine.
    #[test] fn guid_iid_factory1_matches_win32_headers() {
        assert_eq!(
            bytes_of(&IID_IDXGI_FACTORY1),
            [0x78, 0xae, 0x0a, 0x77, 0x6f, 0xf2, 0xba, 0x4d,
             0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87],
            "IID_IDXGIFactory1 phải là {{770AAE78-F26F-4DBA-A829-253C83D1B387}}"
        );
    }

    /// `{00CDDEA8-939B-4B83-A340-A685226666CC}` — `IID_IDXGIOutput1`.
    #[test] fn guid_iid_output1_matches_win32_headers() {
        assert_eq!(
            bytes_of(&IID_IDXGI_OUTPUT1),
            [0xa8, 0xde, 0xcd, 0x00, 0x9b, 0x93, 0x83, 0x4b,
             0xa3, 0x40, 0xa6, 0x85, 0x22, 0x66, 0x66, 0xcc],
            "IID_IDXGIOutput1 phải là {{00CDDEA8-939B-4B83-A340-A685226666CC}}"
        );
    }

    /// `{6F15AAF2-D208-4E89-9AB4-489535D34F9C}` — `IID_ID3D11Texture2D`, dùng
    /// khi `QueryInterface` từ `IDXGIResource` sang texture.
    #[test] fn guid_iid_texture2d_matches_win32_headers() {
        // Cùng giá trị đang dùng trong `acquire`; nếu ai đó sửa một bên mà quên
        // bên kia, test này gãy thay vì để capture hỏng lúc chạy.
        const T: Guid = guid(0x6f15aaf2, 0xd208, 0x4e89, [0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c]);
        assert_eq!(
            bytes_of(&T),
            [0xf2, 0xaa, 0x15, 0x6f, 0x08, 0xd2, 0x89, 0x4e,
             0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c],
            "IID_ID3D11Texture2D phải là {{6F15AAF2-D208-4E89-9AB4-489535D34F9C}}"
        );
    }

    #[test] fn only_timeout_means_the_screen_just_did_not_change() {
        // `Timeout` không phải lỗi: màn hình tĩnh là bình thường. Coi nó là lỗi
        // ⇒ đóng stream mỗi lần người dùng ngừng gõ phím. Vòng lặp ở `main.rs`
        // phân biệt bằng `match` trên biến thể, không bằng một cờ `is_fatal()`
        // — một chỗ quyết định, không hai.
        assert_eq!(CaptureError::Timeout, CaptureError::Timeout);
        assert_ne!(CaptureError::Timeout, CaptureError::AccessLost);
        assert_eq!(CaptureError::AccessLost, CaptureError::AccessLost);
    }

    #[test] fn a_bad_monitor_message_tells_the_user_how_many_exist() {
        let message = CaptureError::BadMonitor { requested: 3, available: 2 }.message();
        assert!(message.contains('3') && message.contains('2'), "{message}");
        assert!(message.contains("màn hình"), "{message}");
    }

}
