# Native Windows webcam output spike

## Chosen direction

Use a native WebRTC receiver with hardware decode where the WebRTC build and GPU support it, then expose the decoded frames through a Media Foundation Virtual Camera. Prefer NV12 and preserve timestamps; avoid routing frames through WebView2, Canvas, RGBA and BGR conversion.

## Existing compatibility path

The current Windows app at `windows/webcam/Program.cs` uses WebView2 and `CoreWebView2SharedBuffer`, then sends BGR frames to the existing DirectShow `softcam.dll`. This remains the fallback and must not be removed until the native path passes consumer-app tests.

## Implementation sequence

1. Select and pin a supported native WebRTC build for Windows x64; document exact SDK version, build options, codec support, and license obligations.
2. Implement signaling/pairing as an adapter. Do not assume a native WebRTC peer can directly speak PeerJS merely because both use WebRTC; validate the PeerServer protocol or introduce an explicit versioned signaling endpoint that the iPhone app can also use.
3. Decode into D3D11 textures where supported. Record decoder implementation, dimensions, FPS, frame age, packet loss, jitter, and keyframe recovery.
4. Build a Media Foundation Virtual Camera using Microsoft's Windows-Camera VirtualCamera sample as the reference. Advertise only formats actually supported by the implementation, including NV12 3840×2160 at 60 fps only after timing and downstream consumer validation.
5. Keep DirectShow `softcam.dll` as the fallback. Add an explicit experimental toggle and never silently replace the current default.

## Acceptance criteria

- At least 10 minutes of physical 3840×2160@60 operation with an actual consumer (OBS, Teams, Zoom, or equivalent).
- At least 59 delivered frames/s average; report p50/p95 frame age and drops.
- Stable memory and no progressive thermal or performance collapse.
- Test reconnect, source rotation, source format changes, receiver shutdown, device sleep/resume, and a consumer closing/reopening the virtual camera.
- If no physical machine or consumer is available, report build/simulation evidence only and do not mark 4K60 validated.