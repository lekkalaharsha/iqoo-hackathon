import 'dart:typed_data';

/// Why a generation attempt did not produce usable text. Kept separate from any
/// one provider's error type so a second backend (on-device Gemma) can report
/// its own failures — model missing, out of memory — through the same channel.
enum LlmFailure {
  /// The backend is not usable at all (no key, model not installed).
  notReady,

  /// Reached the backend, but this backend cannot serve the request
  /// (e.g. the on-device path is not wired yet).
  unsupported,

  unauthorized,
  quota,
  unavailable,
  timeout,
  network,
  emptyResponse,
  invalidRequest,
}

/// Result of a single generation call: either text, or a typed failure.
/// Never both, never neither.
class LlmResult {
  const LlmResult.text(String this.value) : failure = null;
  const LlmResult.failed(LlmFailure this.failure) : value = null;

  final String? value;
  final LlmFailure? failure;

  /// True when [value] is present and not blank.
  bool get hasText => value != null && value!.trim().isNotEmpty;
}

/// One language-model provider behind a stable interface.
///
/// The app has exactly one seam for text generation. Today the only real
/// implementation is [GeminiBackend] (cloud REST). The hackathon build swaps in
/// an on-device implementation ([GemmaBackend]) without touching callers:
/// [AIService] tries the on-device backend first and falls back to cloud.
abstract class LlmBackend {
  /// Short stable id for diagnostics/overlays, e.g. `cloud-gemini`.
  String get id;

  /// Whether a [generate] call can succeed right now. Checked before use so the
  /// caller can speak a "not set up" message instead of failing silently.
  bool get isReady;

  /// One-time setup. Cheap/no-op for a REST client; loads the model for an
  /// on-device backend. Safe to call more than once.
  Future<void> initialize();

  /// Text in (plus optional images), full text out. Returns a typed
  /// [LlmResult]; implementations must not throw for expected failures.
  Future<LlmResult> generate({
    required String prompt,
    List<Uint8List>? images,
    Duration timeout,
  });

  /// Release any held resources (HTTP client, model handle).
  void dispose();
}
