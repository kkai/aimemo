import Foundation
import whisper

enum WhisperError: Error {
    case couldNotInitializeContext
    case decodeFailed(status: Int32)
    case aborted
}


/// Cross-thread abort flag for an in-flight decode.
///
/// Read from ggml's worker threads via `abort_callback`, so it cannot live on
/// the actor: an actor-isolated cancel would queue behind the very decode it is
/// trying to interrupt.
final class WhisperAbortToken: @unchecked Sendable {
  private let lock = NSLock()
  private var requested = false

  var isRequested: Bool {
    lock.lock(); defer { lock.unlock() }
    return requested
  }

  func request() {
    lock.lock(); requested = true; lock.unlock()
  }

  func reset() {
    lock.lock(); requested = false; lock.unlock()
  }
}

/// ggml aborts when this returns true (whisper.cpp:2268).
private let whisperAbortTrampoline: ggml_abort_callback = { userData in
  guard let userData else { return false }
  return Unmanaged<WhisperAbortToken>.fromOpaque(userData).takeUnretainedValue().isRequested
}

/// whisper aborts when this returns false (whisper.cpp:5407).
private let whisperEncoderBeginTrampoline: whisper_encoder_begin_callback = { _, _, userData in
  guard let userData else { return true }
  return !Unmanaged<WhisperAbortToken>.fromOpaque(userData).takeUnretainedValue().isRequested
}

/// Meets Whisper C++ constraint: Don't access from more than one thread at a time.
actor WhisperContext {
    private var context: OpaquePointer

    /// Nonisolated so `abortInFlight()` can set it while a decode holds the actor.
    private nonisolated let abortToken = WhisperAbortToken()
    
    init(path: URL) throws {
        var params = whisper_context_default_params()
#if targetEnvironment(simulator)
        params.use_gpu = false
        print("Running on the simulator, using CPU")
#endif
        let context = whisper_init_from_file_with_params(path.path(), params)
        if let context {
            self.context = context
        } else {
            print("Couldn't load model at \(path.path())")
            throw WhisperError.couldNotInitializeContext
        }
    }
    
    deinit {
        whisper_free(context)
    }
    
    func fullTranscribe(samples: [Float], options: TranscriptionOptions = .default) {
        // Leave 2 processors free (i.e. the high-efficiency cores).
        let maxThreads = max(1, min(8, cpuCount() - 2))
        print("Selecting \(maxThreads) threads")
        
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        
        params.print_realtime   = true
        params.print_progress   = false
        params.print_timestamps = true
        params.print_special    = false
        params.translate        = options.translateToEnglish
        params.n_threads        = Int32(maxThreads)
        params.offset_ms        = 0
        params.no_context       = true
        params.single_segment   = true
        params.no_timestamps    = true
        // Keep the C-strings alive for the whole whisper_full call.
        // (A prior `"auto".withCString { params.language = $0 }` left a dangling
        // pointer once the closure returned, so auto-detect state — e.g.
        // whisper_full_lang_id — was never set. Same trap applies to the prompt.)
        let language = strdup(options.language.code)
        defer { free(language) }
        params.language = UnsafePointer(language)

        let prompt = options.initialPrompt.map { strdup($0) }
        defer { if let prompt { free(prompt) } }
        if let prompt {
            params.initial_prompt = UnsafePointer(prompt)
        }

        whisper_reset_timings(context)
        print("About to run whisper_full")

        samples.withUnsafeBufferPointer { samples in
            if (whisper_full(context, params, samples.baseAddress, Int32(samples.count)) != 0) {
                print("Failed to run the model")
            } else {
                whisper_print_timings(context)
            }
        }
    }
    
    func getTranscription() -> String {
        var transcription = ""
        for i in 0..<whisper_full_n_segments(context) {
            transcription += String.init(cString: whisper_full_get_segment_text(context, i))
        }
        return transcription
    }

    /// The language auto-detected during the last `fullTranscribe` run, as an
    /// ISO 639-1 code (e.g. "en", "de"). Returns nil if none was detected.
    func detectedLanguage() -> String? {
        let langId = whisper_full_lang_id(context)
        guard langId >= 0, let cStr = whisper_lang_str(langId) else { return nil }
        return String(cString: cStr)
    }

    // MARK: - Streaming (WindowTranscribing)

    /// Decodes one bounded window.
    ///
    /// Differs from `fullTranscribe` in three ways that matter: `single_segment`
    /// and `no_timestamps` are off, so whisper segments the window naturally and
    /// reports usable `t0`/`t1`; context is supplied explicitly as
    /// `prompt_tokens` rather than carried in `prompt_past`, which keeps it
    /// deterministic and assertable; and the temperature ladder is disabled so
    /// window latency is predictable.
    func transcribe(
        window: [Float],
        prompt: String?,
        options: TranscriptionOptions = .default,
        isPreview: Bool = false
    ) async throws -> TranscribedWindow {
        abortToken.reset()

        let maxThreads = max(1, min(8, cpuCount() - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

        params.print_realtime   = false
        params.print_progress   = false
        params.print_timestamps = false
        params.print_special    = false
        params.translate        = options.translateToEnglish
        params.n_threads        = Int32(maxThreads)
        params.offset_ms        = 0
        params.duration_ms      = 0
        // The window is already sliced, so whisper never needs to seek.
        params.single_segment   = false
        params.no_timestamps    = false
        // Context arrives as prompt_tokens; prompt_past would also accumulate
        // anything a future preview pass decoded.
        params.no_context       = true
        params.n_max_text_ctx   = 224
        // No fallback retries: one decode per window, predictable latency, and
        // it keeps t_cur below the 0.5 gate on prompt reuse (whisper.cpp:5484).
        params.temperature_inc  = 0

        // Keep every C buffer alive for the whole whisper_full call. The
        // dangling-pointer trap documented above for `language` applies
        // identically to the prompt tokens.
        let language = strdup(options.language.code)
        defer { free(language) }
        params.language = UnsafePointer(language)

        var promptTokens: [whisper_token] = []
        if let prompt, !prompt.isEmpty {
            promptTokens = tokenize(prompt, limit: 224)
        }
        // Custom vocabulary still rides in as initial_prompt when there is no
        // committed tail to carry, so the setting keeps working on window one.
        var vocabulary: UnsafeMutablePointer<CChar>?
        if promptTokens.isEmpty, let seed = options.initialPrompt {
            vocabulary = strdup(seed)
            params.initial_prompt = UnsafePointer(vocabulary)
        }
        defer { if let vocabulary { free(vocabulary) } }

        let tokenBox = Unmanaged.passUnretained(abortToken).toOpaque()
        params.abort_callback = whisperAbortTrampoline
        params.abort_callback_user_data = tokenBox
        params.encoder_begin_callback = whisperEncoderBeginTrampoline
        params.encoder_begin_callback_user_data = tokenBox

        whisper_reset_timings(context)

        var status: Int32 = 0
        promptTokens.withUnsafeBufferPointer { tokens in
            if !tokens.isEmpty {
                params.prompt_tokens = tokens.baseAddress
                params.prompt_n_tokens = Int32(tokens.count)
            }
            window.withUnsafeBufferPointer { samples in
                status = whisper_full(context, params, samples.baseAddress, Int32(samples.count))
            }
        }

        if abortToken.isRequested {
            throw WhisperError.aborted
        }
        guard status == 0 else {
            throw WhisperError.decodeFailed(status: status)
        }

        return TranscribedWindow(
            segments: collectSegments(),
            detectedLanguageCode: options.language == .automatic ? detectedLanguage() : nil
        )
    }

    /// Signals the running decode to stop. Safe to call from any thread.
    nonisolated func abortInFlight() {
        abortToken.request()
    }

    // MARK: - Result extraction

    private func collectSegments() -> [TranscribedWindow.Segment] {
        let endOfText = whisper_token_eot(context)
        var segments: [TranscribedWindow.Segment] = []

        for i in 0..<whisper_full_n_segments(context) {
            guard let raw = whisper_full_get_segment_text(context, i) else { continue }
            let text = String(cString: raw)

            // t0/t1 are centiseconds, relative to this window's start.
            let start = TimeInterval(whisper_full_get_segment_t0(context, i)) / 100
            let end = TimeInterval(whisper_full_get_segment_t1(context, i)) / 100

            // Mean probability over real text tokens; specials and timestamps
            // carry no useful confidence.
            var total: Float = 0
            var counted = 0
            for t in 0..<whisper_full_n_tokens(context, i) {
                let token = whisper_full_get_token_data(context, i, t)
                guard token.id < endOfText else { continue }
                total += token.p
                counted += 1
            }
            let confidence = counted > 0 ? total / Float(counted) : 0

            segments.append(
                TranscribedWindow.Segment(text: text, start: start, end: end, confidence: confidence))
        }

        return segments
    }

    private func tokenize(_ text: String, limit: Int) -> [whisper_token] {
        var tokens = [whisper_token](repeating: 0, count: limit)
        let count = text.withCString { whisper_tokenize(context, $0, &tokens, Int32(limit)) }
        guard count > 0 else { return [] }
        return Array(tokens.prefix(Int(count)))
    }
}

fileprivate func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}

extension WhisperContext: WindowTranscribing {}
