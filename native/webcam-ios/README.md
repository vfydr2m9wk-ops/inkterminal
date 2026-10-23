# Native Webcam 4K60 spike (iOS)

This folder is an isolated, experimental native path. It does not replace the current Safari/PeerJS route.

## Goal

Prove whether the target iPhone can expose 3840×2160 at 60 fps from AVFoundation before integrating native WebRTC. A requested profile is not treated as proof: the spike selects only a compatible active format and reports delivered/dropped sample counts.

## Current scope

- Enumerate camera formats and select a format whose dimensions are exactly 3840×2160 and whose supported frame-rate range includes 60 fps.
- Request bi-planar Y'CbCr output (NV12-compatible) to avoid forcing BGRA/RGBA at capture.
- Expose NV12-compatible CVPixelBuffers and presentation timestamps for the native WebRTC camera source; let WebRTC's VideoToolbox-backed encoder handle encoding to avoid a separate encode/packetize/re-encode path.
- Expose raw camera frames and timestamps through a callback seam for a native WebRTC capturer/source adapter.
- Fail clearly if the device cannot supply the requested camera format.

## Not yet implemented

- App target, signing, UI, and packaging.
- Native WebRTC session and pairing/signaling compatible with InkTerminal's current PeerJS flow.
- Windows native WebRTC receiver and Media Foundation Virtual Camera.
- End-to-end 4K60 test on a physical iPhone + Windows consumer app.

Do not call this a working webcam yet. This is the first high-risk vertical slice: camera format → native NV12 frames. WebRTC encoding, transport, and Windows output must follow in separate commits. The transport and Windows output must follow in separate commits and stay opt-in until measured.

## Integration contract

The future WebRTC layer should wrap each CVPixelBuffer as an RTCVideoFrame without converting it to RGBA, preserve presentation timestamps, and use WebRTC's hardware-backed VideoToolbox encoder. Verify actual encoder implementation and output dimensions/FPS through WebRTC stats. Do not add an independent encoder unless a measured benefit justifies the added RTP packetization complexity.

## Physical acceptance test

Run for at least 10 minutes with screen unlocked and device thermals monitored. Record active width/height, observed capture fps, WebRTC encoded fps/codec/bitrate, decoded and delivered fps, dropped frames, frame age, memory, and thermal state. Report measured results separately from estimates.