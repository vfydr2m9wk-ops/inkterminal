import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// One H.264 access unit produced by VideoToolbox. `bytes` uses the encoder's
/// length-prefixed representation; the transport adapter must packetize it for WebRTC.
public struct EncodedAccessUnit {
    public let bytes: Data
    public let presentationTime: CMTime
    public let isKeyframe: Bool
    public let width: Int
    public let height: Int
}

public enum NativeCaptureError: Error, LocalizedError {
    case noBackCamera
    case no4K60Format
    case cannotAddInput
    case cannotAddOutput
    case encoderCreation(OSStatus)
    case encoderNotHardwareAccelerated
    case missingPixelBuffer

    public var errorDescription: String? {
        switch self {
        case .noBackCamera: return "No rear wide-angle camera was found."
        case .no4K60Format: return "This device does not expose a 3840×2160 camera format supporting 60 fps."
        case .cannotAddInput: return "AVCaptureSession cannot add the selected camera input."
        case .cannotAddOutput: return "AVCaptureSession cannot add the NV12 video output."
        case .encoderCreation(let status): return "VideoToolbox encoder creation failed: \(status)."
        case .encoderNotHardwareAccelerated: return "VideoToolbox did not confirm hardware encoding; refusing the 4K60 profile."
        case .missingPixelBuffer: return "The camera sample did not contain a pixel buffer."
        }
    }
}

/// Experimental capture → hardware H.264 encoder. It deliberately contains no WebRTC
/// or UI dependency; that keeps the high-risk capture/encode proof independently testable.
public final class Native4K60Capture: NSObject {
    public var onAccessUnit: ((EncodedAccessUnit) -> Void)?
    public var onMetrics: ((CaptureMetrics) -> Void)?

    public struct CaptureMetrics {
        public let width: Int
        public let height: Int
        public let inputFrames: UInt64
        public let encodedFrames: UInt64
        public let droppedFrames: UInt64
        public let hardwareEncoder: Bool
    }

    private let session = AVCaptureSession()
    private let outputQueue = DispatchQueue(label: "inkterminal.webcam.capture", qos: .userInteractive)
    private var compressionSession: VTCompressionSession?
    private var selectedWidth = 0
    private var selectedHeight = 0
    private var inputFrames: UInt64 = 0
    private var encodedFrames: UInt64 = 0
    private var droppedFrames: UInt64 = 0
    private var hardwareEncoder = false
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
            .filter({ CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                      CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange })
            .filter({
                let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                return d.width == 3840 && d.height == 2160 &&
                    $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 60 && $0.maxFrameRate >= 60 }
            })
            .sorted(by: {
                // Prefer a format with the least costly pixel type when multiple match.
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
        try createHardwareEncoder(width: selectedWidth, height: selectedHeight)
        session.startRunning()
        started = true
    }

    public func stop() {
        if session.isRunning { session.stopRunning() }
        if let compressionSession { VTCompressionSessionCompleteFrames(compressionSession, untilPresentationTimeStamp: .invalid) }
        if let compressionSession { VTCompressionSessionInvalidate(compressionSession) }
        compressionSession = nil
        started = false
    }

    private func createHardwareEncoder(width: Int, height: Int) throws {
        var created: VTCompressionSession?
        let specification: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
        ]
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: specification as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: inkterminalVTOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &created
        )
        guard status == noErr, let created else { throw NativeCaptureError.encoderCreation(status) }
        compressionSession = created
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: 60))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: 30_000_000))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 2))
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(created)
        guard prepareStatus == noErr else { throw NativeCaptureError.encoderCreation(prepareStatus) }
        var usingHardware: CFTypeRef?
        let propertyStatus = VTSessionCopyProperty(created, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, allocator: kCFAllocatorDefault, valueOut: &usingHardware)
        hardwareEncoder = propertyStatus == noErr && (usingHardware as? Bool) == true
        guard hardwareEncoder else {
            VTCompressionSessionInvalidate(created)
            compressionSession = nil
            throw NativeCaptureError.encoderNotHardwareAccelerated
        }
    }

    private func encode(_ sampleBuffer: CMSampleBuffer) {
        guard let encoder = compressionSession, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            droppedFrames += 1
            return
        }
        inputFrames += 1
        var flags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            encoder,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            duration: CMSampleBufferGetDuration(sampleBuffer),
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        if status != noErr { droppedFrames += 1 }
        if inputFrames % 60 == 0 { publishMetrics() }
    }

    fileprivate func consumeEncoded(_ sampleBuffer: CMSampleBuffer, status: OSStatus, flags: VTEncodeInfoFlags) {
        guard status == noErr, !flags.contains(.frameDropped), CMSampleBufferDataIsReady(sampleBuffer),
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            droppedFrames += 1
            return
        }
        let length = CMBlockBufferGetDataLength(block)
        var bytes = Data(count: length)
        let copyStatus = bytes.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return kCMBlockBufferBadCustomBlockSourceErr }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
        }
        guard copyStatus == kCMBlockBufferNoErr else { droppedFrames += 1; return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let keyframe = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        let accessUnit = EncodedAccessUnit(
            bytes: bytes,
            presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            isKeyframe: keyframe,
            width: selectedWidth,
            height: selectedHeight
        )
        encodedFrames += 1
        onAccessUnit?(accessUnit)
        if encodedFrames % 60 == 0 { publishMetrics() }
    }

    private func publishMetrics() {
        onMetrics?(CaptureMetrics(width: selectedWidth, height: selectedHeight, inputFrames: inputFrames,
                                  encodedFrames: encodedFrames, droppedFrames: droppedFrames,
                                  hardwareEncoder: hardwareEncoder))
    }

    deinit { stop() }
}

extension Native4K60Capture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        encode(sampleBuffer)
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        droppedFrames += 1
        publishMetrics()
    }
}

private let inkterminalVTOutputCallback: VTCompressionOutputCallback = { refcon, _, status, infoFlags, sampleBuffer in
    guard let refcon, let sampleBuffer else { return }
    let capture = Unmanaged<Native4K60Capture>.fromOpaque(refcon).takeUnretainedValue()
    capture.consumeEncoded(sampleBuffer, status: status, flags: infoFlags)
}