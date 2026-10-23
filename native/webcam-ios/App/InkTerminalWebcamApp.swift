import AVFoundation
import SwiftUI

@MainActor
final class CaptureTestModel: ObservableObject {
    @Published var status = "Pronto para testar"
    @Published var resolution = "Resolução: —"
    @Published var delivered = 0
    @Published var dropped = 0
    @Published var fps = 0.0
    @Published var isRunning = false

    private var capture: Native4K60Capture?
    private var lastFrameCount = 0
    private var lastSampleAt = Date()

    func start() {
        guard !isRunning else { return }
        status = "Solicitando permissão da câmera…"
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.status = "Permissão da câmera negada. Ative-a nos Ajustes do iPhone."
                    return
                }
                self.startCapture()
            }
        }
    }

    private func startCapture() {
        let camera = Native4K60Capture()
        camera.onFrame = { [weak self] frame in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resolution = "Quadros: \(frame.width) × \(frame.height)"
                let now = Date()
                if now.timeIntervalSince(self.lastSampleAt) >= 1 {
                    self.fps = Double(self.delivered - self.lastFrameCount) / now.timeIntervalSince(self.lastSampleAt)
                    self.lastFrameCount = self.delivered
                    self.lastSampleAt = now
                }
            }
        }
        camera.onMetrics = { [weak self] metrics in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resolution = "Formato selecionado: \(metrics.width) × \(metrics.height)"
                self.delivered = Int(metrics.deliveredFrames)
                self.dropped = Int(metrics.droppedFrames)
                self.status = "Capturando. Estes valores são medições locais."
            }
        }
        do {
            try camera.start()
            capture = camera
            isRunning = true
            lastSampleAt = Date()
            lastFrameCount = delivered
            status = "Câmera iniciada; aguardando quadros…"
        } catch {
            status = "Falha ao iniciar: \(error.localizedDescription)"
        }
    }

    func stop() {
        capture?.stop()
        capture = nil
        isRunning = false
        status = "Captura parada"
    }
}

@main
struct InkTerminalWebcamApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureTestView()
        }
    }
}

struct CaptureTestView: View {
    @StateObject private var model = CaptureTestModel()

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "web.camera.fill")
                .font(.system(size: 48))
            Text("InkTerminal")
                .font(.largeTitle.bold())
            Text("Teste nativo de captura 4K60")
                .font(.headline)
            Text(model.status)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Divider()
            metric("Formato", model.resolution)
            metric("Quadros entregues", "\(model.delivered)")
            metric("Quadros descartados", "\(model.dropped)")
            metric("FPS medidos (aprox.)", String(format: "%.1f", model.fps))
            Text("O formato selecionado não garante 60 FPS sustentados. Este protótipo só testa captura local; ainda não transmite para o Windows.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Iniciar captura") { model.start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning)
                Button("Parar") { model.stop() }
                    .buttonStyle(.bordered)
                    .disabled(!model.isRunning)
            }
        }
        .padding(24)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit())
                .multilineTextAlignment(.center)
        }
    }
}
