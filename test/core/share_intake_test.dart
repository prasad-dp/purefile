import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:purefile/core/share_intake/share_intake.dart';
import 'package:purefile/features/tools/tool_flow_screen.dart'
    show toolUiSpec;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

SharedMediaFile media(String path, SharedMediaType type) =>
    SharedMediaFile(path: path, type: type);

/// Simulates an environment with no platform channel (desktop/tests).
class _ThrowingIntent extends ReceiveSharingIntent {
  @override
  Future<List<SharedMediaFile>> getInitialMedia() async {
    throw MissingPluginException('no channel in this environment');
  }

  @override
  Stream<List<SharedMediaFile>> getMediaStream() => const Stream.empty();

  @override
  Future<dynamic> reset() async {}
}

/// Real fixture files on disk — the eligibility pass runs the ACTUAL
/// validator (exists → non-empty → magic vs extension), so it needs bytes.
Future<Directory> makeFixtures() async {
  final dir = Directory.systemTemp.createTempSync('pf_share_test');
  final pdf = List<int>.generate(64, (i) => i);
  pdf[0] = 0x25;
  pdf[1] = 0x50;
  pdf[2] = 0x44;
  pdf[3] = 0x46; // %PDF
  File('${dir.path}${Platform.pathSeparator}doc.pdf').writeAsBytesSync(pdf);

  final png = List<int>.filled(64, 0);
  png[0] = 0x89;
  png[1] = 0x50;
  png[2] = 0x4E;
  png[3] = 0x47; // \x89PNG
  File('${dir.path}${Platform.pathSeparator}img.png').writeAsBytesSync(png);

  final zip = List<int>.filled(64, 0);
  zip[0] = 0x50;
  zip[1] = 0x4B;
  zip[2] = 0x03;
  zip[3] = 0x04; // PK\x03\x04
  File('${dir.path}${Platform.pathSeparator}a.zip').writeAsBytesSync(zip);

  return dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory fixtures;
  late ProviderContainer container;

  setUp(() async {
    fixtures = await makeFixtures();
    container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() {
      try {
        fixtures.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  String p(String name) =>
      '${fixtures.path}${Platform.pathSeparator}$name';

  group('ShareIntake controller', () {
    test('cold start: initial media lands in pending state', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: [media(p('doc.pdf'), SharedMediaType.file)],
        mediaStream: const Stream.empty(),
      );
      final intake = container.read(shareIntakeProvider.notifier);
      await intake.start();

      expect(container.read(shareIntakeProvider), [p('doc.pdf')]);
    });

    test('warm share: stream event lands in pending state', () async {
      final controller = StreamController<List<SharedMediaFile>>();
      ReceiveSharingIntent.setMockValues(
        initialMedia: const [],
        mediaStream: controller.stream,
      );
      final intake = container.read(shareIntakeProvider.notifier);
      await intake.start();
      expect(container.read(shareIntakeProvider), isEmpty);

      controller.add([media(p('img.png'), SharedMediaType.image)]);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(shareIntakeProvider), [p('img.png')]);
      await controller.close();
    });

    test('text/url shares are ignored; videos stay for the chooser to explain',
        () async {
      final controller = StreamController<List<SharedMediaFile>>();
      ReceiveSharingIntent.setMockValues(
        initialMedia: const [],
        mediaStream: controller.stream,
      );
      final intake = container.read(shareIntakeProvider.notifier);
      await intake.start();

      controller.add([
        media('cache/video.mp4', SharedMediaType.video),
        media('text-only', SharedMediaType.text),
        media('https://example.com', SharedMediaType.url),
      ]);
      await Future<void>.delayed(Duration.zero);
      // No tool can process a video — but the chooser's "no tool fits"
      // explanation beats a silent drop, so videos stay pending.
      expect(container.read(shareIntakeProvider), ['cache/video.mp4']);
      await controller.close();
    });

    test('consume clears pending and returns the paths', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          media(p('doc.pdf'), SharedMediaType.file),
          media(p('img.png'), SharedMediaType.image),
        ],
        mediaStream: const Stream.empty(),
      );
      final intake = container.read(shareIntakeProvider.notifier);
      await intake.start();

      final consumed = intake.consume();
      expect(consumed, [p('doc.pdf'), p('img.png')]);
      expect(container.read(shareIntakeProvider), isEmpty);
    });

    test('discard clears pending without returning them', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: [media(p('doc.pdf'), SharedMediaType.file)],
        mediaStream: const Stream.empty(),
      );
      final intake = container.read(shareIntakeProvider.notifier);
      await intake.start();

      intake.discard();
      expect(container.read(shareIntakeProvider), isEmpty);
    });

    test('missing plugin channel stays dormant (no crash)', () async {
      // Deterministic no-channel environment: a fake whose calls throw.
      ReceiveSharingIntent.instance = _ThrowingIntent();
      final intake = container.read(shareIntakeProvider.notifier);
      await intake.start();
      expect(container.read(shareIntakeProvider), isEmpty);
    });

    test('double start is idempotent', () async {
      ReceiveSharingIntent.setMockValues(
        initialMedia: [media(p('doc.pdf'), SharedMediaType.file)],
        mediaStream: const Stream.empty(),
      );
      final intake = container.read(shareIntakeProvider.notifier);
      await intake.start();
      await intake.start();
      expect(container.read(shareIntakeProvider), [p('doc.pdf')],
          reason: 'second start must not duplicate or wipe the intake');
    });
  });

  group('eligibility (real validator + real tool specs)', () {
    Future<List<String>> eligibleFor(List<String> paths) => eligibleToolIds(
          paths,
          specFor: (toolId) {
            final spec = toolUiSpec(toolId);
            return (allowedMagic: spec.allowedMagic, maxFiles: spec.maxFiles);
          },
        );

    test('a single PDF is offered to every PDF tool (incl. zip_create)',
        () async {
      final eligible = await eligibleFor([p('doc.pdf')]);
      expect(eligible, containsAll(['pdf_compress', 'pdf_split', 'zip_create']));
    });

    test('an image never lands in PDF-only tools', () async {
      final eligible = await eligibleFor([p('img.png')]);
      expect(eligible, isNot(contains('pdf_compress')));
      expect(eligible, isNot(contains('zip_extract')));
      expect(eligible, containsAll(['image_compress', 'image_convert', 'images_to_pdf']));
    });

    test('a zip fits the zip tools only', () async {
      final eligible = await eligibleFor([p('a.zip')]);
      // zip_create takes ANY files by design; zip_extract wants archives.
      expect(eligible, containsAll(['zip_create', 'zip_extract']));
      expect(eligible.length, 2, reason: 'nothing else accepts a bare zip');
    });

    test('pdf+png mix fits only merge and zip_create', () async {
      final eligible = await eligibleFor([p('doc.pdf'), p('img.png')]);
      expect(eligible, containsAll(['pdf_merge', 'zip_create']));
      expect(eligible, isNot(contains('pdf_compress')), reason: 'maxFiles 1');
      expect(eligible, isNot(contains('image_compress')),
          reason: 'pdf is not an image');
    });
  });
}
