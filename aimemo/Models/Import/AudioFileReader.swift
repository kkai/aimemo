//
//  AudioFileReader.swift
//  aimemo
//
//  Decodes any audio or video file to whisper's 16 kHz mono float stream
//

import AVFoundation
import Foundation

/// Reads a file through `AVAssetReader` with an audio mix output pinned to
/// 16 kHz mono Float32, so one path handles m4a, mp3, wav, caf, aac, mov and
/// mp4 and the asset does the resampling. Audio is yielded in chunks of about
/// `chunkDuration` seconds; a one-hour file never sits in memory as floats.
struct AudioFileReader: Sendable {

  enum ImportError: LocalizedError, Equatable {
    case noAudioTrack
    case protectedContent
    case unreadable(String)

    var errorDescription: String? {
      switch self {
      case .noAudioTrack: return "This file has no audio track."
      case .protectedContent: return "This file is copy-protected and cannot be transcribed."
      case .unreadable(let detail): return "This file could not be read. \(detail)"
      }
    }
  }

  let url: URL
  var chunkDuration: TimeInterval = 10
  static let sampleRate: Double = 16_000

  init(url: URL, chunkDuration: TimeInterval = 10) {
    self.url = url
    self.chunkDuration = chunkDuration
  }

  /// The file's duration in seconds, from the container.
  func duration() async throws -> TimeInterval {
    let asset = AVURLAsset(url: url)
    do {
      return try await asset.load(.duration).seconds
    } catch {
      throw ImportError.unreadable(error.localizedDescription)
    }
  }

  /// 16 kHz mono samples, in order. Finishes after the last chunk; throws
  /// `ImportError` for files without audio, protected files, or decode failures.
  func samples() -> AsyncThrowingStream<[Float], Error> {
    AsyncThrowingStream { continuation in
      let task = Task.detached(priority: .userInitiated) {
        do {
          try await Self.read(url: url, chunkSamples: Int(chunkDuration * Self.sampleRate)) { chunk in
            guard !Task.isCancelled else { return false }
            continuation.yield(chunk)
            return true
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Runs the reader loop. `emit` returns false to stop early.
  private static func read(url: URL, chunkSamples: Int,
                           emit: @Sendable ([Float]) -> Bool) async throws {
    let asset = AVURLAsset(url: url)
    let protected: Bool
    let tracks: [AVAssetTrack]
    do {
      protected = try await asset.load(.hasProtectedContent)
      tracks = try await asset.loadTracks(withMediaType: .audio)
    } catch {
      // AVFoundation's own wording ("Cannot Open", "unknown error -17913")
      // helps nobody; the reason that matters is that it is not a media file.
      throw ImportError.unreadable(Self.plainReason(for: error))
    }
    if protected { throw ImportError.protectedContent }
    guard !tracks.isEmpty else { throw ImportError.noAudioTrack }

    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      throw ImportError.unreadable(error.localizedDescription)
    }

    let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw ImportError.unreadable("Unsupported audio format.") }
    reader.add(output)
    guard reader.startReading() else {
      throw ImportError.unreadable(reader.error?.localizedDescription ?? "The decoder did not start.")
    }

    var pending: [Float] = []
    pending.reserveCapacity(chunkSamples)
    while let buffer = output.copyNextSampleBuffer() {
      try Task.checkCancellation()
      pending.append(contentsOf: floats(in: buffer))
      while pending.count >= chunkSamples {
        let chunk = Array(pending.prefix(chunkSamples))
        pending.removeFirst(chunkSamples)
        guard emit(chunk) else { reader.cancelReading(); return }
      }
    }
    if reader.status == .failed {
      throw ImportError.unreadable(reader.error?.localizedDescription ?? "Decoding failed.")
    }
    if !pending.isEmpty { _ = emit(pending) }
  }

  /// A sentence for the error line. AVFoundation's failure reason when it has
  /// one ("This media format is not supported."), otherwise a generic line.
  private static func plainReason(for error: Error) -> String {
    let ns = error as NSError
    if let reason = ns.localizedFailureReason, !reason.isEmpty { return reason }
    return "It is not an audio or video file the device can play."
  }

  /// Copies the Float32 payload out of a sample buffer.
  private static func floats(in sampleBuffer: CMSampleBuffer) -> [Float] {
    var blockBuffer: CMBlockBuffer?
    var list = AudioBufferList(mNumberBuffers: 1,
                               mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: &list,
      bufferListSize: MemoryLayout<AudioBufferList>.size,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: &blockBuffer)
    guard status == noErr, let data = list.mBuffers.mData else { return [] }
    let count = Int(list.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
    return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
  }
}
