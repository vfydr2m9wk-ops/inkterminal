# Native Webcam 4K60 spike (iOS)

This folder is an isolated, experimental native path. It does not replace the current Safari/PeerJS route.

## Goal

Prove whether the target iPhone can produce sustained 3840×2160 at 60 fps from AVFoundation and a hardware VideoToolbox encoder before integrating transport. A requested profile is not treated as proof: the spike reports the active capture format and observed sample cadence.

## Current scope

- Enumerate camera formats and select a format whose dimensions are exactly 3840×2160 and whose supported frame-rate range includes 60 fps.
- Request bi-planar Y'CbCr output (NV12-compatible) to avoid forcing BGRA/RGBA at capture.
- Configure a real-time hardware H.264 VideoToolbox compression session.
- Expose encoded access units and timestamps through a callback seam for a later native WebRTC sender.
- Fail clearly if the device cannot supply the requested format or hardware encoder.

## Not yet implemented

- App target, signing, UI, and packaging.
- Native WebRTC session and pairing/signaling compatible with InkTerminal's current PeerJS flow.
- Windows native WebRTC receiver and Media Foundation Virtual Camera.
- End-to-end 4K60 test on a physical iPhone + Windows consumer app.

Do not call this a working webcam yet. This is the first high-risk vertical slice: camera format → hardware encoder. The transport and Windows output must follow in separate commits and stay opt-in until measured.

## Integration contract

The future WebRTC layer should consume EncodedAccessUnit values with monotonic presentation timestamps and codec configuration (SPS/PPS) delivered by the encoder. Prefer a WebRTC implementation that can accept native encoded frames without re-encoding; if the chosen API requires decoded frames, revisit the architecture rather than silently introducing an expensive pixel conversion.

## Physical acceptance test

Run for at least 10 minutes with screen unlocked and device thermals monitored. Record active width/height, observed input fps, encoder output fps, bitrate, dropped frames, keyframe cadence, memory, and thermal state. Report measured results separately from estimates.