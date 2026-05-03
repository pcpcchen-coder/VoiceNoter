import Foundation
import AVFoundation

enum AudioRecorderError: LocalizedError {
    case engineFailed(String)
    case converterFailed
    case writeFailed(String)
    case tooShort
    case notRecording

    var errorDescription: String? {
        switch self {
        case .engineFailed(let msg): return "錄音引擎啟動失敗：\(msg)"
        case .converterFailed: return "音訊格式轉換失敗"
        case .writeFailed(let msg): return "WAV 寫檔失敗：\(msg)"
        case .tooShort: return "錄音過短，已忽略"
        case .notRecording: return "目前並未在錄音"
        }
    }
}

/// Captures microphone input at 16kHz mono Float32 PCM and writes a temporary WAV file.
final class AudioRecorder {
    static let targetSampleRate: Double = 16_000
    static let minDurationSeconds: TimeInterval = 0.3
    static let maxDurationSeconds: TimeInterval = 60.0

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var startedAt: Date?
    private var isRecording: Bool = false
    private let queue = DispatchQueue(label: "com.george.voicenote.audio", qos: .userInitiated)

    /// Output format: 16kHz mono Float32 PCM, non-interleaved.
    private static let targetFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!
    }()

    func start() throws {
        guard !isRecording else { return }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat) else {
            throw AudioRecorderError.converterFailed
        }
        self.converter = converter

        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(Int(Self.targetSampleRate * Self.maxDurationSeconds))

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.queue.async {
                self?.handleInput(buffer: buffer, inputFormat: inputFormat)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecorderError.engineFailed(error.localizedDescription)
        }

        startedAt = Date()
        isRecording = true
        Log.audio.info("Recording started")
    }

    func stop() async throws -> URL {
        guard isRecording else {
            throw AudioRecorderError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        let started = startedAt ?? Date()
        let duration = Date().timeIntervalSince(started)
        startedAt = nil

        // Snapshot samples on the audio queue to avoid race with installTap callback.
        let collected: [Float] = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.samples)
                self.samples.removeAll(keepingCapacity: false)
            }
        }

        Log.audio.info("Recording stopped: duration=\(duration, format: .fixed(precision: 2))s samples=\(collected.count)")

        if duration < Self.minDurationSeconds {
            throw AudioRecorderError.tooShort
        }
        if collected.count < Int(Self.targetSampleRate * Self.minDurationSeconds) {
            throw AudioRecorderError.tooShort
        }

        return try writeWav(samples: collected)
    }

    func cancel() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        startedAt = nil
        queue.async { self.samples.removeAll(keepingCapacity: false) }
        Log.audio.info("Recording cancelled")
    }

    var currentDuration: TimeInterval {
        guard let started = startedAt else { return 0 }
        return Date().timeIntervalSince(started)
    }

    // MARK: - Private

    private func handleInput(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard let converter else { return }

        let ratio = Self.targetFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: outputCapacity) else {
            return
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: outBuffer, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            Log.audio.error("Conversion error: \(conversionError.localizedDescription, privacy: .public)")
            return
        }
        guard status != .error,
              let channelData = outBuffer.floatChannelData?[0] else {
            return
        }

        let count = Int(outBuffer.frameLength)
        let bufferPointer = UnsafeBufferPointer(start: channelData, count: count)
        samples.append(contentsOf: bufferPointer)

        // Hard cap to prevent unbounded growth in case stop() is missed.
        let maxSamples = Int(Self.targetSampleRate * Self.maxDurationSeconds)
        if samples.count > maxSamples {
            samples.removeLast(samples.count - maxSamples)
        }
    }

    private func writeWav(samples: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicenote-\(UUID().uuidString).wav")

        let format = Self.targetFormat
        do {
            let file = try AVAudioFile(forWriting: url,
                                       settings: format.settings,
                                       commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            // Write in chunks to avoid huge contiguous allocations.
            let chunkFrames: AVAudioFrameCount = 4096
            var offset = 0
            while offset < samples.count {
                let remaining = samples.count - offset
                let frames = AVAudioFrameCount(min(Int(chunkFrames), remaining))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                      let dst = buffer.floatChannelData?[0] else {
                    throw AudioRecorderError.writeFailed("PCM buffer alloc failed")
                }
                buffer.frameLength = frames
                samples.withUnsafeBufferPointer { src in
                    dst.update(from: src.baseAddress! + offset, count: Int(frames))
                }
                try file.write(from: buffer)
                offset += Int(frames)
            }
        } catch {
            throw AudioRecorderError.writeFailed(error.localizedDescription)
        }

        Log.audio.info("Wrote WAV: \(url.path, privacy: .public)")
        return url
    }
}
