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
/// `chunkDuration` seconds, decoded on demand: memory holds one chunk, not the file.
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
  ///
  /// Pull-based: a chunk is decoded only when the loop asks for the next one,
  /// so memory holds one chunk however long the file is. (It used to be an
  /// `AsyncThrowingStream` fed by a detached task; the decoder outruns
  /// Whisper by far, so the stream's unbounded buffer held the whole file,
  /// ~230 MB of floats per hour, and a long import could be killed.)
  func samples() -> Chunks {
    Chunks(url: url, chunkSamples: max(1, Int(chunkDuration * Self.sampleRate)))
  }

  struct Chunks: AsyncSequence {
    typealias Element = [Float]
    let url: URL
    let chunkSamples: Int

    func makeAsyncIterator() -> Iterator { Iterator(url: url, chunkSamples: chunkSamples) }

    final class Iterator: AsyncIteratorProtocol {
      private let url: URL
      private let chunkSamples: Int
      private var decoder: Decoder?
      private var finished = false

      init(url: URL, chunkSamples: Int) {
        self.url = url
        self.chunkSamples = chunkSamples
      }

      func next() async throws -> [Float]? {
        guard !finished else { return nil }
        do {
          try Task.checkCancellation()
          if decoder == nil { decoder = try await Decoder.open(url: url, chunkSamples: chunkSamples) }
          let decoder = decoder!
          // Off the caller's actor: the caller is the main actor.
          let chunk = try await Task.detached(priority: .userInitiated) { try decoder.nextChunk() }.value
          if chunk == nil { finish() }
          return chunk
        } catch {
          finish()
          throw error
        }
      }

      private func finish() {
        finished = true
        decoder?.cancel()
        decoder = nil
      }
    }
  }

  /// One `AVAssetReader` and the samples left over from its last buffer.
  /// Used by one iterator at a time, one call after another, never
  /// concurrently, which is what makes the unchecked conformance hold.
  final class Decoder: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput
    private let chunkSamples: Int
    private var pending: [Float] = []

    private init(reader: AVAssetReader, output: AVAssetReaderAudioMixOutput, chunkSamples: Int) {
      self.reader = reader
      self.output = output
      self.chunkSamples = chunkSamples
      pending.reserveCapacity(chunkSamples)
    }

    deinit { cancel() }

    static func open(url: URL, chunkSamples: Int) async throws -> Decoder {
      let asset = AVURLAsset(url: url)
      let protected: Bool
      let tracks: [AVAssetTrack]
      do {
        protected = try await asset.load(.hasProtectedContent)
        tracks = try await asset.loadTracks(withMediaType: .audio)
      } catch {
        // AVFoundation's own wording ("Cannot Open", "unknown error -17913")
        // helps nobody; the reason that matters is that it is not a media file.
        throw ImportError.unreadable(AudioFileReader.plainReason(for: error))
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
        AVSampleRateKey: AudioFileReader.sampleRate,
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
      return Decoder(reader: reader, output: output, chunkSamples: chunkSamples)
    }

    /// The next `chunkSamples` samples (fewer for the last chunk), or nil at the end.
    func nextChunk() throws -> [Float]? {
      while pending.count < chunkSamples {
        let more: Bool = autoreleasepool {
          guard let buffer = output.copyNextSampleBuffer() else { return false }
          pending.append(contentsOf: AudioFileReader.floats(in: buffer))
          return true
        }
        if !more { break }
      }
      if reader.status == .failed {
        throw ImportError.unreadable(reader.error?.localizedDescription ?? "Decoding failed.")
      }
      guard !pending.isEmpty else { return nil }
      let count = min(chunkSamples, pending.count)
      let chunk = Array(pending.prefix(count))
      pending.removeFirst(count)
      return chunk
    }

    func cancel() {
      if reader.status == .reading { reader.cancelReading() }
    }
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
