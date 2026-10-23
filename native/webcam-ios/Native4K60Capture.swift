import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

public struct NativeCameraFrame {
    public let pixelBuffer: CVPixelBuffer
    public let presentationTime: CMTime
    public let width: Int
    public let height: Int
}

public enum NativeCaptureError: Error, LocalizedError {
    case noBackCamera
    case no4K60Format
    case cannotAddInput
    case cannotAddOutput

    public var errorDescription: String? {
        switch self {
        case .noBackCamera: return "No rear wide-angle camera was found."
        case .no4K60Format: return "This device does not expose a 3840×2160 camera format supporting 60 fps."
        case .cannotAddInput: return "AVCaptureSession cannot add the selected camera input."
        case .cannotAddOutput: return "AVCaptureSession cannot add the NV12 video output."
        }
    }
}

/// Experimental native capture stage. It delivers NV12-compatible CVPixelBuffers
/// directly to the future WebRTC adapter; it intentionally does not create an
/// independent encoder or convert frames to RGBA.
public final class Native4K60Capture: NSObject {
    public var onFrame: ((NativeCameraFrame) -> Void)?
    public var onMetrics: ((CaptureMetrics) -> Void)?

    public struct CaptureMetrics {
        public let width: Int
        public let height: Int
        public let deliveredFrames: UInt64
        public let droppedFrames: UInt64
    }

    private let session = AVCaptureSession()
    private let outputQueue = DispatchQueue(label: "inkterminal.webcam.capture", qos: .userInteractive)
    private var selectedWidth = 0
    private var selectedHeight = 0
    private var deliveredFrames: UInt64 = 0
    private var droppedFrames: UInt64 = 0
    private var started = false

    public override init() { super.init() }

    public func start() throws {
        guard !started else { return }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        guard let device = discovery.devices.first else { throw NativeCaptureError.noBackCamera }
        guard let format = device.formats
            .filter({
                let subtype = CMFormatDescriptionGetMediaSubType($0.formatDescription)
                let isBiPlanar = subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                                 subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                return isBiPlanar && dimensions.width == 3840 && dimensions.height == 2160 &&
                    $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 60 && $0.maxFrameRate >= 60 }
            })
            .sorted(by: {
                CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            }).first else { throw NativeCaptureError.no4K60Format }

        try device.lockForConfiguration()
        device.activeFormat = format
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
        device.unlockForConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        guard session.canAddInput(input) else { session.commitConfiguration(); throw NativeCaptureError.cannotAddInput }
        session.addInput(input)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        guard session.canAddOutput(videoOutput) else { session.commitConfiguration(); throw NativeCaptureError.cannotAddOutput }
        session.addOutput(videoOutput)
        session.commitConfiguration()

        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        selectedWidth = Int(dimensions.width)
        selectedHeight = Int(dimensions.height)
        session.startRunning()
        started = true
    }

    public func stop() {
        if session.isRunning { session.stopRunning() }
        started = false
    }

    private func publishMetrics() {
        onMetrics?(CaptureMetrics(width: selectedWidth, height: selectedHeight,
                                  deliveredFrames: deliveredFrames, droppedFrames: droppedFrames))
    }
}

extension Native4K60Capture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            droppedFrames += 1
            return
        }
        deliveredFrames += 1
        onFrame?(NativeCameraFrame(pixelBuffer: pixelBuffer,
                                   presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                                   width: CVPixelBufferGetWidth(pixelBuffer),
                                   height: CVPixelBufferGetHeight(pixelBuffer)))
        if deliveredFrames % 60 == 0 { publishMetrics() }
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        droppedFrames += 1
        publishMetrics()
    }
}