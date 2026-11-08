# Thu gọn bộ GStreamer xuống đúng những gì cần chạy.
#
# Vì sao: gói MSVC 64-bit của GStreamer là **installer 517 MB**. Chép cả gói
# vào artifact GitHub là không thực tế (giới hạn artifact, thời gian tải), mà
# 95% trong đó là plugin cho video call, camera, RTSP, mux/demux mà app này
# không bao giờ chạm tới.
#
# Đường MJPEG của §58 chỉ cần **6 element**:
#   d3d11screencapturesrc · d3d11download · videoconvert · jpegenc ·
#   multipartmux · fdsink
# ⇒ đúng 4 thư viện: d3d11, videoconvertscale, jpeg, multipartmux.
#
# Script này **không đoán**: nó chạy `gst-inspect-1.0` trên từng file plugin để
# hỏi "file này chứa element nào", rồi chỉ giữ file thật sự có ích. Nhờ vậy khi
# GStreamer đổi cách chia plugin ở phiên bản sau, script vẫn đúng — và nếu một
# element biến mất thì nó **báo lỗi**, không lặng lẽ tạo gói thiếu.
#
#   pwsh -File scripts/trim-gstreamer.ps1 -Root <thư mục cài GStreamer>
#
# Kết quả in ra: số file giữ lại, số MB, và kiểm tra lần cuối trên bộ đã thu gọn
# (chạy trong thư mục đó với GST_PLUGIN_SYSTEM_PATH_1_0 trỏ vào nó).

param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Out = ''
)
$ErrorActionPreference = 'Stop'

function Fail($message) {
    # Log job không tải được từ sandbox (§56.10), và GitHub chỉ giữ **một**
    # annotation lỗi mỗi step. Step summary thì đọc được đầy đủ qua API
    # (`/check-runs/<id>` → `output.summary`), nên chẩn đoán đi đường đó.
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "## Thu gọn GStreamer thất bại`n`n$message"
    }
    Write-Output "::error::$($message -split "`n" | Select-Object -First 1)"
    exit 1
}

try {
$Root = (Resolve-Path $Root).Path
$bin = Join-Path $Root 'bin'
$plugins = Join-Path $Root 'lib/gstreamer-1.0'
if (-not (Test-Path (Join-Path $bin 'gst-inspect-1.0.exe'))) { Fail "Không thấy gst-inspect-1.0.exe trong $bin" }
if (-not (Test-Path $plugins)) { Fail "Không thấy thư mục plugin: $plugins" }

# Element bắt buộc, kèm plugin **được phép** chứa nó. Ghi cả hai để nếu plugin
# chuyển nhà ở phiên bản sau thì lỗi nói rõ chuyện gì, không chỉ "không thấy".
$required = [ordered]@{
    'd3d11screencapturesrc' = @('d3d11')
    'd3d11download'         = @('d3d11')
    'videoconvert'          = @('videoconvertscale', 'videoconvert')
    'jpegenc'               = @('jpeg')
    'multipartmux'          = @('multipartmux', 'multipart')
    'fdsink'                = @('coreelements')
}

Write-Output "== kiểm tra element trên gói đầy đủ"
$env:GST_PLUGIN_SYSTEM_PATH_1_0 = $plugins
$env:GST_PLUGIN_PATH_1_0 = ''

# Với từng element, hỏi `gst-inspect <element>` xem nó **nằm trong file plugin
# nào** — đọc dòng "Filename" trong mục Plugin Details. Cách này không phụ thuộc
# quy ước đặt tên file (`gstjpeg.dll` chứ không phải `libgstjpeg.dll` trên Windows)
# và không phụ thuộc định dạng mục lục của `gst-inspect <file>`.
$inspectExe = Join-Path $bin 'gst-inspect-1.0.exe'
$keep = New-Object System.Collections.Generic.HashSet[string]
foreach ($element in $required.Keys) {
    $found = $false
    $text = (& $inspectExe $element 2>&1 | Out-String)
    # `gst-inspect <element>` trả mã khác 0 trên Windows dù in đủ thông tin —
    # đừng dựa vào exit code, dựa vào nội dung.
    $match = [regex]::Match($text, '(?m)^\s*Filename\s+(.+?)\s*$')
    if ($match.Success) {
        $file = $match.Groups[1].Value.Trim()
        if (Test-Path $file) {
            [void]$keep.Add($file)
            Write-Output "   $element  ->  $(Split-Path $file -Leaf)"
            $found = $true
        }
    }
    if (-not $found) {
        $count = (Get-ChildItem $plugins -Filter '*.dll').Count
        $head = ($text -split "`n" | Select-Object -First 10) -join ' / '
        Fail "Gói GStreamer này thiếu element '$element' (mong ở plugin: $($required[$element] -join ', '))`nCó $count file .dll trong $plugins`nOutput của gst-inspect $element: $head"
    }
}

# `gst-launch-1.0` cần thêm hai thứ luôn đi cùng bộ core.
foreach ($name in @('gst-launch-1.0.exe', 'gst-inspect-1.0.exe', 'gst-plugin-scanner.exe')) {
    $path = Join-Path $bin $name
    if (-not (Test-Path $path)) { Fail "Thiếu $name trong bin" }
}

$outRoot = if ($Out) { $Out } else { Join-Path $Root 'trimmed' }
if (Test-Path $outRoot) { Remove-Item -Recurse -Force $outRoot }
$outBin = Join-Path $outRoot 'bin'
$outPlugins = Join-Path $outRoot 'lib/gstreamer-1.0'
New-Item -ItemType Directory -Force -Path $outBin, $outPlugins | Out-Null

# 1) DLL của chính GStreamer + mọi thứ trong bin ngoại trừ plugin ta sẽ chọn tay.
#    `bin` chứa DLL phụ thuộc (glib, intl, orc, ...) mà gst-launch cần; chép hết
#    rồi loại plugin thừa là cách an toàn hơn chép từng cái tên.
Get-ChildItem $bin -File | Where-Object { $_.Extension -ne '.dll' -or $_.Name -notmatch '^gst' } | ForEach-Object {
    Copy-Item $_.FullName -Destination $outBin
}
# Toàn bộ DLL không phải plugin (glib-2.0-0.dll, gstreamer-1.0-0.dll, ...).
Get-ChildItem $bin -Filter '*.dll' | Where-Object { $keep -notcontains $_.FullName } | ForEach-Object {
    Copy-Item $_.FullName -Destination $outBin -ErrorAction SilentlyContinue
}

# 2) Chỉ những file plugin thật sự cần.
foreach ($file in $keep) { Copy-Item $file -Destination $outPlugins }
# 3) Các subfolder mà d3d11 cần để tìm shader/hlsl của nó, nếu có.
foreach ($sub in @('lib/gstreamer-1.0/include')) {
    $path = Join-Path $Root $sub
    if (Test-Path $path) { Copy-Item $path -Destination $outPlugins -Recurse -Force -ErrorAction SilentlyContinue }
}

# 4) Kiểm tra **trên bộ đã thu gọn** — đây là bước quan trọng nhất: một gói thiếu
#    file vẫn "trông ổn" cho tới khi người dùng bấm nút.
Write-Output "== kiểm tra trên bộ đã thu gọn"
$env:PATH = "$outBin;$env:PATH"
$env:GST_PLUGIN_SYSTEM_PATH_1_0 = $outPlugins
foreach ($element in $required.Keys) {
    # Không dùng exit code: `gst-inspect` trên Windows trả mã khác 0 dù in đủ
    # thông tin (đã kiểm trong CI). Kiểm **nội dung**: phải có "Factory Details".
    $check = (& (Join-Path $outBin 'gst-inspect-1.0.exe') $element 2>&1 | Out-String)
    if ($check -notmatch 'Factory Details') { Fail "Bộ thu gọn thiếu '$element' — đừng giao gói này`n$($check.Substring(0, [Math]::Min(400, $check.Length)))" }
    Write-Output "   ok: $element"
}

$size = [math]::Round((Get-ChildItem $outRoot -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
$count = (Get-ChildItem $outRoot -Recurse -File).Count
Write-Output "== xong: $count file, $size MB (bản đầy đủ: $([math]::Round((Get-ChildItem $Root -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB, 1)) MB)"
Write-Output "== ở $outRoot"
} catch {
    Fail "Lỗi không mong đợi khi thu gọn GStreamer: $($_.Exception.Message)`nTại: $($_.InvocationInfo.PositionMessage)"
}
