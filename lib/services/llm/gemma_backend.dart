import 'dart:typed_data';

import 'llm_backend.dart';

/// On-device backend seam — Gemma via `flutter_gemma` (LiteRT-LM / MediaPipe on
/// the Snapdragon NPU/GPU).
///
/// NOT wired yet: [isReady] is false and [generate] returns
/// [LlmFailure.unsupported], so [AIService] falls straight through to the cloud
/// backend. The "Voice Chat" home mode (index 2) already sends its turns through
/// [AIService], so wiring this class is all that is needed to make that mode run
/// on-device — no new UI, no new mode.
///
/// ## Enabling it (hackathon build)
///
/// 1. `flutter pub add flutter_gemma` (adds the LiteRT/MediaPipe native libs;
///    bumps APK size — verify the split-per-abi release still builds).
///    Android: `android:largeHeap="true"` on `<application>` in the manifest,
///    `minSdkVersion` >= 24.
/// 2. Ship or download a model. Text-only Gemma 3 1B (~0.5 GB, instruction
///    tuned, function calling) is the safe pick for the explanation/chat job;
///    Gemma 3n E2B (~3 GB) if multimodal is needed. Do NOT bundle a multi-GB
///    file in the APK — copy it to app storage on first run, or `.fromFile()`
///    a path pushed via Office Kit.
/// 3. Flip the `on_device_llm` feature flag (config / Settings) — `AIService`
///    calls [initialize] only when that flag is set, then prefers this backend.
///
/// ## Reference implementation (paste once the dependency is added)
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
///
/// InferenceModel? _model;
/// InferenceChat? _chat;
/// bool _ready = false;
///
/// @override
/// Future<void> initialize() async {
///   try {
///     final mgr = FlutterGemmaPlugin.instance.modelManager;
///     if (!await mgr.isModelInstalled) {
///       // e.g. a path handed over via Office Kit, or a first-run download.
///       await mgr.setModelPath(_modelFilePath);
///     }
///     _model = await FlutterGemmaPlugin.instance.createModel(
///       modelType: ModelType.gemmaIt,
///       preferredBackend: PreferredBackend.gpu, // benchmark vs .cpu on device
///       maxTokens: 1024,
///     );
///     _chat = await _model!.createChat(
///       temperature: 0.4,
///       topK: 40,
///       supportImage: false, // true only with a 3n/vision model
///     );
///     _ready = true;
///   } catch (_) {
///     _ready = false; // AIService stays on cloud
///   }
/// }
///
/// @override
/// Future<LlmResult> generate({
///   required String prompt,
///   List<Uint8List>? images,
///   Duration timeout = const Duration(seconds: 15),
/// }) async {
///   final chat = _chat;
///   if (!_ready || chat == null) {
///     return const LlmResult.failed(LlmFailure.notReady);
///   }
///   try {
///     await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
///     final buffer = StringBuffer();
///     await chat
///         .generateChatResponseAsync()
///         .where((r) => r is TextResponse)
///         .cast<TextResponse>()
///         .forEach((r) => buffer.write(r.token))
///         .timeout(timeout);
///     final text = buffer.toString().trim();
///     return text.isEmpty
///         ? const LlmResult.failed(LlmFailure.emptyResponse)
///         : LlmResult.text(text);
///   } on TimeoutException {
///     return const LlmResult.failed(LlmFailure.timeout);
///   } catch (_) {
///     return const LlmResult.failed(LlmFailure.unavailable);
///   }
/// }
///
/// @override
/// void dispose() {
///   _chat = null;
///   _model?.close();
///   _model = null;
///   _ready = false;
/// }
/// ```
///
/// `AIService.explain` already splits the returned text into sentences for
/// early TTS. If token streaming to speech is wanted, add an `onToken` callback
/// to [generate] and forward `TextResponse.token` as it arrives.
class GemmaBackend implements LlmBackend {
  bool _ready = false;

  @override
  String get id => 'on-device-gemma';

  @override
  bool get isReady => _ready;

  @override
  Future<void> initialize() async {
    // No model bundled and no flutter_gemma dependency yet. Real load lands
    // here — see the class doc for the exact sequence.
    _ready = false;
  }

  @override
  Future<LlmResult> generate({
    required String prompt,
    List<Uint8List>? images,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return const LlmResult.failed(LlmFailure.unsupported);
  }

  @override
  void dispose() {}
}
