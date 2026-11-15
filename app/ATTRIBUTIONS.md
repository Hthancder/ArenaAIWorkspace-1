# Attributions / Ghi công

## App code — NoteFall

This app is a fork of **NoteFall** by ekkx — https://github.com/ekkx/notefall

- License: **PolyForm Shield License 1.0.0** (see `LICENSE.md`, kept unchanged).
  This is a *source-available* license with a Noncompete clause: personal,
  study and internal use is allowed; **releasing a competing product
  (piano visualizer / MIDI editor / video export) is NOT allowed without
  permission from the author**. If you plan to publish this app, contact the
  NoteFall author first or rewrite the parts you ship.
- Required Notice: Copyright (c) 2026 ekkx.

## Piano samples — Salamander Grand Piano V3

- **Salamander Grand Piano V3** by **Alexander Holm**, licensed **CC BY 3.0**
  (<https://creativecommons.org/licenses/by/3.0/>). Free to share and adapt
  with attribution.
- Fetched via `scripts/fetch-samples.sh` from the GitHub mirror
  `d-buckner/salamander-piano` (the same pre-encoded OGG release the upstream
  NoteFall pipeline prepares): 30 root keys × 16 velocity layers,
  close-mic position, ~150 MB, served self-hosted from
  `public/samples/salamander-v3-close/` (gitignored).
- To use the samples elsewhere, credit: *“Salamander Grand Piano V3 by
  Alexander Holm (CC BY 3.0)”*.

## Hand models (if you enable Hands)

Virtual hand meshes/motion in `src/hands/` are CC0 per upstream NoteFall.
The motion data download (fetched on first enable) comes from the upstream
project's CDN and is only available while that endpoint is reachable.

## UI strings

Vietnamese (`src/i18n/locales/vi/`) and Japanese (`ja/`) translations follow
the terminology in `research-piano/25-tieng-viet-va-ban-dia-hoa.md`.
