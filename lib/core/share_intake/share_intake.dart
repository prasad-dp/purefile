import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../formats.dart' show PfMagic;
import '../validation/validator.dart';

/// Feature 16: files shared INTO PureFile from other apps (Android
/// SEND/SEND_MULTIPLE intent filters). The plugin copies shared content to a
/// temp cache dir; we only ever hold local file paths.
///
/// Two delivery paths, both landing in [pendingPaths]:
///  • cold start — app launched by a share: [start] pulls `getInitialMedia`.
///  • warm share — app already running: the media stream emits.
///
/// The tool-chooser screen consumes the pending paths; a tool flow screen
/// auto-fills its selection from them (validated against the tool's spec).
class ShareIntake extends Notifier<List<String>> {
  StreamSubscription<List<SharedMediaFile>>? _sub;
  bool _started = false;

  /// Shared files awaiting consumption (empty = nothing pending).
  @override
  List<String> build() => const [];

  bool get hasPending => state.isNotEmpty;

  /// Idempotent. Platform-channel failures (tests, desktop) leave the intake
  /// idle instead of crashing — share-sheet is an Android-only entry.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    ref.onDispose(() => _sub?.cancel());
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      _absorb(initial);
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
            _absorb,
            onError: (_) {},
          );
    } on MissingPluginException {
      // No channel in this environment — share intake stays dormant.
    } on PlatformException {
      // Malformed/unsupported share payload — nothing to intake.
    }
  }

  void _absorb(List<SharedMediaFile> media) {
    final paths = [
      for (final m in media)
        if (m.type == SharedMediaType.file ||
            m.type == SharedMediaType.image ||
            m.type == SharedMediaType.video)
          m.path,
    ].where((p) => p.isNotEmpty).toList();
    if (paths.isEmpty) return;
    // Newest share wins (one intake slot keeps the flow simple and predictable).
    state = paths;
  }

  /// The chooser validated the user's tool pick; hand over and clear.
  List<String> consume() {
    final paths = state;
    state = const [];
    return paths;
  }

  /// Chooser dismissed without a pick — keep the files pending so the user
  /// can still reach them via the chooser? No: a dismissed share is dropped
  /// (predictable; matches how other apps treat cancelled shares).
  void discard() {
    state = const [];
  }
}

final shareIntakeProvider =
    NotifierProvider<ShareIntake, List<String>>(ShareIntake.new);

/// Tools that are NOT generic flow tools (custom screens with their own
/// intake UX). Shared files never auto-route into them.
const kNonFlowToolIds = {'scan', 'sign', 'vault'};

/// Per-tool validation contract the eligibility check needs (kept record-
/// typed so core never imports the widget layer).
typedef ShareSpecResolver = ({Set<PfMagic>? allowedMagic, int? maxFiles})
    Function(String toolId);

/// Which flow tools can process this selection end-to-end? A tool is
/// eligible when every file passes its spec validation (magic + size rules)
/// — the same gate a manual pick would hit, so the chooser never offers a
/// tool that would reject the files later.
Future<List<String>> eligibleToolIds(
  List<String> paths, {
  required ShareSpecResolver specFor,
}) async {
  final eligible = <String>[];
  for (final toolId in isFlowToolAll) {
    final spec = specFor(toolId);
    final probe = await validatePick(paths, allowedMagic: spec.allowedMagic);
    final maxFiles = spec.maxFiles;
    if (probe.accepted.length == paths.length &&
        (maxFiles == null || paths.length <= maxFiles)) {
      eligible.add(toolId);
    }
  }
  return eligible;
}

/// Registry order for the chooser; kept here to avoid importing the widget
/// layer. Mirrors kPfTools ids (flow tools only).
const isFlowToolAll = [
  'pdf_compress',
  'pdf_merge',
  'pdf_split',
  'images_to_pdf',
  'pdf_to_images',
  'image_compress',
  'image_convert',
  'zip_create',
  'zip_extract',
  'ocr',
];
