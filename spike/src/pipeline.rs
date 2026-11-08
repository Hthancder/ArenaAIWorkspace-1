//! GStreamer pipeline strings. Pure string building: buildable and testable on
//! any OS, in any CI, with no GPU and no GStreamer installed.
//!
//! Latency rules encoded here come from spec §37: no multipass, no lookahead,
//! CBR with a short VBV, zerolatency. Getting any of these wrong costs 30-130 ms.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Encoder {
    Qsv,
    Nvenc,
    MediaFoundation,
}

impl Encoder {
    pub fn element(self) -> &'static str {
        match self {
            Encoder::Qsv => "qsvh264enc",
            Encoder::Nvenc => "nvh264enc",
            Encoder::MediaFoundation => "mfh264enc",
        }
    }

    /// Low-latency parameters. Every one of these is load-bearing.
    fn options(self, bitrate_kbps: u32) -> String {
        match self {
            Encoder::Qsv => format!(
                "{} target-usage=7 bitrate={} rate-control=cbr gop-size=120 \
                 b-frames=0 low-latency=true",
                self.element(),
                bitrate_kbps
            ),
            Encoder::Nvenc => format!(
                "{} rc-mode=cbr bitrate={} gop-size=120 zerolatency=true \
                 preset=low-latency-hq bframes=0",
                self.element(),
                bitrate_kbps
            ),
            Encoder::MediaFoundation => format!(
                "{} bitrate={} gop-size=120 low-latency=true",
                self.element(),
                bitrate_kbps
            ),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Profile {
    pub encoder: Encoder,
    /// Which DXGI monitor index to capture.
    pub monitor_index: u32,
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub bitrate_kbps: u32,
    pub payload_type: u32,
    /// Separate SSRCs: video, camera, mic must never share one.
    pub ssrc_video: u32,
    pub ssrc_camera: u32,
    pub ssrc_mic: u32,
}

impl Profile {
    /// Sensible default for a hybrid laptop: QSV on the iGPU, because capture and
    /// encode then share one adapter and the dGPU stays in D3cold (spec §53.2/§54).
    pub fn laptop_default() -> Self {
        Self {
            encoder: Encoder::Qsv,
            monitor_index: 1,
            width: 1920,
            height: 1080,
            fps: 60,
            bitrate_kbps: 10_000,
            payload_type: 96,
            ssrc_video: 0x1000_0001,
            ssrc_camera: 0x2000_0001,
            ssrc_mic: 0x3000_0001,
        }
    }

    pub fn desktop_default() -> Self {
        Self {
            encoder: Encoder::Nvenc,
            ..Self::laptop_default()
        }
    }
}

/// Desktop/monitor capture with a launch line. `capture-api=dxgi` means the
/// element derives the device from the adapter that owns the monitor, which is
/// the safe choice on hybrid systems.
pub fn desktop(p: &Profile) -> String {
    format!(
        "d3d11screencapturesrc monitor-index={mon} capture-api=dxgi ! \
         d3d11convert ! video/x-raw(memory:D3D11Memory),format=NV12,width={w},height={h},framerate={fps}/1 ! \
         {enc} ! h264parse config-interval=-1 ! \
         rtph264pay config-interval=-1 aggregate-mode=zero-latency pt={pt} ssrc={ssrc} ! \
         application/x-rtp,media=video,encoding-name=H264,payload={pt},clock-rate=90000,ssrc={ssrc}",
        mon = p.monitor_index,
        w = p.width,
        h = p.height,
        fps = p.fps,
        enc = p.encoder.options(p.bitrate_kbps),
        pt = p.payload_type,
        ssrc = p.ssrc_video,
    )
}

/// Room view: camera only. No desktop capture at all, so this does not touch the
/// thermal/power budget of a session (spec §54.5). 720p30 at 1.5 Mbps is what a
/// laptop webcam can actually sustain.
pub fn camera(p: &Profile) -> String {
    format!(
        "mfvideosrc device-index=0 ! videoconvert ! videoscale ! videorate ! \
         video/x-raw,width=1280,height=720,framerate=30/1,format=NV12 ! \
         {enc} ! h264parse config-interval=-1 ! \
         rtph264pay config-interval=-1 pt={pt} ssrc={ssrc} ! \
         application/x-rtp,media=video,encoding-name=H264,payload={pt},clock-rate=90000,ssrc={ssrc}",
        enc = p.encoder.options(1_500),
        pt = p.payload_type + 2,
        ssrc = p.ssrc_camera,
    )
}

/// Microphone. `loopback=false` on purpose: we want the room, not the speakers,
/// otherwise the far end hears itself back.
pub fn mic(p: &Profile) -> String {
    format!(
        "wasapi2src loopback=false low-latency=true ! \
         audioconvert ! audioresample ! audio/x-raw,rate=48000,channels=1 ! \
         opusenc bitrate=32000 frame-size=20 inband-fec=true ! \
         rtpopuspay pt={pt} ssrc={ssrc} ! \
         application/x-rtp,media=audio,encoding-name=OPUS,payload={pt},clock-rate=48000,ssrc={ssrc}",
        pt = p.payload_type + 4,
        ssrc = p.ssrc_mic,
    )
}
