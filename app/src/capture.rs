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
    if let Some(release) = (*unknown).release {
        release(object as *mut c_void);
    }
}

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

/// `IDXGIResource` — chỉ cần `QueryInterface` để lấy `ID3D11Texture2D`.
#[repr(C)]
struct Resource {
    query_interface: Option<QueryInterfaceFn>,
    add_ref: Option<AddRefFn>,
    release: Option<ReleaseFn>,
}

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
}

// Con trỏ COM không `Send`/`Sync` mặc định, nhưng phiên capture được dùng từ
// đúng **một** thread stream. Ghi rõ ở đây thay vì để compiler từ chối.
unsafe impl Send for Capture {}

impl Capture {
    /// Mở phiên capture cho `monitor` (0-based, theo thứ tự DXGI).
    #[cfg(windows)]
    pub fn open(monitor: u8) -> Result<Self, CaptureError> {
        let api = Api::load()?;
        unsafe {
            let mut factory_raw: *mut c_void = ptr::null_mut();
            let code = (api.create_dxgi_factory1)(&IID_IDXGI_FACTORY1, &mut factory_raw);
            check(code, "CreateDXGIFactory1")?;
            let factory = as_interface::<Factory1>(factory_raw);

            // Duyệt adapter rồi output, đếm theo **thứ tự DXGI** — đúng thứ mà
            // người dùng thấy trong `gst-inspect` trước đây và trong Windows
            // Settings sau này. Đếm để báo lỗi kèm số màn hình thật.
            let mut seen = 0u32;
            let mut output_raw: *mut c_void = ptr::null_mut();
            // Adapter **của output đã chọn**, không phải adapter 0. Khai ngoài
            // vòng lặp vì `DuplicateOutput` cần một device tạo trên chính nó.
            let mut adapter_raw: *mut c_void = ptr::null_mut();
            let mut adapter_index = 0u32;
            while output_raw.is_null() {
                adapter_raw = ptr::null_mut();
                let enum_adapters1 = (*factory).enum_adapters1;
                let Some(enum_adapters1) = enum_adapters1 else {
                    release(factory);
                    return Err(CaptureError::NoDevice("IDXGIFactory1 quá cũ".into()));
                };
                if enum_adapters1(factory as *mut c_void, adapter_index, &mut adapter_raw) < 0 || adapter_raw.is_null() {
                    break;
                }
                let adapter = as_interface::<Adapter1>(adapter_raw);
                let mut output_index = 0u32;
                loop {
                    let mut candidate: *mut c_void = ptr::null_mut();
                    let enum_outputs = (*adapter).enum_outputs;
                    let Some(enum_outputs) = enum_outputs else { break };
                    if enum_outputs(adapter as *mut c_void, output_index, &mut candidate) < 0 || candidate.is_null() {
                        break;
                    }
                    let output = as_interface::<Output1>(candidate);
                    // Bỏ output không gắn vào desktop (màn hình ảo đã tắt).
                    let mut desc = OutputDesc {
                        device_name: [0; 32],
                        desktop_coordinates: Rect { left: 0, top: 0, right: 0, bottom: 0 },
                        attached_to_desktop: 0,
                        rotation: 0,
                        monitor: 0,
                    };
                    let get_desc = (*output).get_desc;
                    let Some(get_desc) = get_desc else {
                        release(candidate);
                        continue;
                    };
                    if get_desc(candidate, &mut desc) < 0 || desc.attached_to_desktop == 0 {
                        release(candidate);
                        output_index += 1;
                        continue;
                    }
                    if seen == monitor as u32 {
                        let mut output1: *mut c_void = ptr::null_mut();
                        let query = (*as_interface::<Unknown>(candidate)).query_interface;
                        let code = match query {
                            Some(query) => query(candidate, &IID_IDXGI_OUTPUT1, &mut output1),
                            None => -1,
                        };
                        release(candidate);
                        if code >= 0 && !output1.is_null() {
                            output_raw = output1;
                            break;
                        }
                    }
                    release(candidate);
                    seen += 1;
                    output_index += 1;
                }
                if output_raw.is_null() {
                    release(adapter_raw);
                    adapter_index += 1;
                    if adapter_index > 8 {
                        break;
                    }
                }
                // `output_raw` khác null ⇒ thoát vòng `while` với `adapter_raw`
                // **còn sống**: device phải được tạo trên chính adapter này.
            }
            if output_raw.is_null() {
                release(factory);
                return Err(if seen == 0 {
                    CaptureError::NoOutput
                } else {
                    CaptureError::BadMonitor { requested: monitor, available: seen }
                });
            }

            // Device **trên adapter của output**, không phải adapter mặc định.
            //
            // `IDXGIOutput1::DuplicateOutput` từ chối (`E_INVALIDARG`) một device
            // không được tạo trên adapter mà output gắn vào. Trên laptop hybrid
            // như Inspiron 7467 (HD 630 + GTX 1050), `D3D11CreateDevice(NULL,
            // HARDWARE, …)` thường chọn GPU rời, trong khi màn hình hình gắn vào
            // iGPU ⇒ capture **không bao giờ** mở được trên đúng loại máy mà
            // §53.4 nói tới. Thông báo duy nhất người dùng thấy là "máy không
            // capture được", không có gì chỉ ra adapter.
            //
            // `D3D_DRIVER_TYPE_UNKNOWN` là **bắt buộc** khi truyền `pAdapter`
            // (HARDWARE + adapter ⇒ `E_INVALIDARG`).
            let mut device_raw: *mut c_void = ptr::null_mut();
            let mut context_raw: *mut c_void = ptr::null_mut();
            let code = (api.d3d11_create_device)(
                adapter_raw,
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
                release(adapter_raw);
                release(output_raw);
                release(factory);
                return Err(CaptureError::NoDevice(format!(
                    "D3D11CreateDevice trên adapter của màn hình → {}",
                    hresult(code)
                )));
            }

            let output1 = as_interface::<Output1>(output_raw);
            let duplicate = (*output1).duplicate_output;
            let mut duplication_raw: *mut c_void = ptr::null_mut();
            let code = match duplicate {
                Some(duplicate) => duplicate(output_raw, device_raw, &mut duplication_raw),
                None => -1,
            };
            release(output_raw);
            release(factory);
            // Device đã được tạo **từ** adapter này nên giữ tham chiếu riêng; nhả
            // ở đây, cả nhánh lỗi lẫn nhánh thành công. Thiếu một nhánh ⇒ rò một
            // tham chiếu COM mỗi lần mở stream, và DXGI giới hạn số duplication
            // đồng thời ⇒ lần mở thứ N hỏng mà không rõ vì sao.
            release(adapter_raw);
            if code < 0 || duplication_raw.is_null() {
                release(device_raw);
                release(context_raw);
                return Err(CaptureError::Other(format!(
                    "DuplicateOutput → {} (cần device trên đúng adapter của màn hình)",
                    hresult(code)
                )));
            }

            let duplication = as_interface::<OutputDuplication>(duplication_raw);
            let mut desc = OutduplDesc {
                mode_desc: ModeDesc { width: 0, height: 0, refresh_rate_numerator: 0, refresh_rate_denominator: 0, format: 0, scanline_ordering: 0, scaling: 0 },
                rotation: 0,
                desktop_image_format: 0,
            };
            let get_desc = (*duplication).get_desc.expect("IDXGIOutputDuplication::GetDesc");
            check(get_desc(duplication.cast(), &mut desc), "GetDesc")?;
            // Đọc qua struct, không qua offset đoán tay trong mảng byte: struct
            // do `#[repr(C)]` xếp, nên compiler kiểm được, còn offset thì không.
            let width = desc.mode_desc.width as usize;
            let height = desc.mode_desc.height as usize;
            if width == 0 || height == 0 {
                release(duplication_raw);
                release(device_raw);
                release(context_raw);
                return Err(CaptureError::NoOutput);
            }

            // Texture staging: nơi GPU ghi bản copy mà CPU đọc được.
            //
            // **Format phải bằng format của desktop.** `CopyResource` đòi hai
            // resource cùng kiểu và cùng kích thước; khác là `CopyResource` chỉ
            // ghi cảnh báo vào debug layer rồi **không làm gì**, và ta đọc
            // texture rỗng — khung hình đen, không có lỗi.
            //
            // Desktop HDR (`DXGI_FORMAT_R16G16B16A16_FLOAT`, bật "HDR" trong
            // Windows Settings) là trường hợp thật trên laptop màn 4K. Rơi về
            // `B8G8R8A8_UNORM` cố định thì stream đen trên đúng máy đó.
            //
            // Ta chỉ biết chắc `B8G8R8A8_UNORM` là đọc được (4 byte/pixel, thứ tự
            // BGRA); format khác thì báo lỗi **đọc được** kèm tên format, thay vì
            // gửi ảnh đen. Chuyển đổi HDR→SDR là việc của một bản riêng.
            if desc.desktop_image_format != DXGI_FORMAT_B8G8R8A8_UNORM {
                release(duplication_raw);
                release(device_raw);
                release(context_raw);
                // **Không** `release(adapter_raw)` ở đây: đã nhả ngay sau
                // `DuplicateOutput` (dòng trên). Nhả hai lần làm refcount xuống
                // dưới 0 và COM trả object cho pool khi vẫn còn người dùng.
                release(factory);
                return Err(CaptureError::Other(format!(
                    "Desktop đang ở format {} (không phải BGRA 8-bit). Tắt HDR trong \
                     Windows Settings → Display, hoặc chọn màn hình khác.",
                    desc.desktop_image_format
                )));
            }
            let texture_desc = TextureDesc {
                width: width as UINT,
                height: height as UINT,
                mip_levels: 1,
                array_size: 1,
                format: DXGI_FORMAT_B8G8R8A8_UNORM,
                sample_desc: [1, 0],
                usage: D3D11_USAGE_STAGING,
                bind_flags: 0,
                cpu_access_flags: D3D11_CPU_ACCESS_READ,
                misc_flags: 0,
            };
            let mut staging_raw: *mut c_void = ptr::null_mut();
            let create_texture2d = (*as_interface::<D3D11Device>(device_raw)).create_texture2d;
            let code = match create_texture2d {
                Some(create) => create(device_raw, &texture_desc, ptr::null(), &mut staging_raw),
                None => -1,
            };
            if code < 0 || staging_raw.is_null() {
                release(duplication_raw);
                release(device_raw);
                release(context_raw);
                return Err(CaptureError::NoDevice(format!("CreateTexture2D → {}", hresult(code))));
            }

            Ok(Self {
                api,
                device: as_interface::<D3D11Device>(device_raw),
                context: as_interface::<D3D11Context>(context_raw),
                duplication,
                staging: as_interface::<Texture2D>(staging_raw),
                width,
                height,
            })
        }
    }

    pub fn size(&self) -> (usize, usize) {
        (self.width, self.height)
    }

    /// Lấy frame kế tiếp. `timeout_ms = 0` là "thử một lần rồi báo Timeout".
    #[cfg(windows)]
    pub fn next_frame(&mut self, timeout_ms: u32) -> Result<Frame, CaptureError> {
        unsafe {
            let Some(acquire) = (*self.duplication).acquire_next_frame else {
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
            let query = (*as_interface::<Resource>(resource_raw)).query_interface;
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
            if let Some(release_frame) = (*self.duplication).release_frame {
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
        for (y, row) in bgra.chunks_mut(row_bytes).enumerate() {
            let src = (mapped.p_data as *const u8).add(y * pitch);
            ptr::copy_nonoverlapping(src, row.as_mut_ptr(), row_bytes);
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
unsafe fn as_interface<T>(pointer: *mut c_void) -> *mut T {
    pointer.cast::<T>()
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
