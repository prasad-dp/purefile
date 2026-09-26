import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:purefile/core/router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('static tool routes are not shadowed by the /tools/:toolId catch-all', () {
    // F13-pre regression: /tools/scan was declared AFTER the parameterized
    // route, so go_router served the generic flow for the scanner card.
    final routes = pfRouter.configuration.routes;
    final paths = [
      for (final r in routes)
        if (r is GoRoute) r.path,
    ];
    final scanIndex = paths.indexOf('/tools/scan');
    final catchAllIndex = paths.indexOf('/tools/:toolId');
    expect(scanIndex, greaterThan(-1), reason: 'scan route exists');
    expect(catchAllIndex, greaterThan(-1), reason: 'catch-all exists');
    expect(scanIndex < catchAllIndex, isTrue,
        reason: 'static /tools/scan must precede /tools/:toolId');

    // F14: the vault got its own screen — same shadowing trap.
    final vaultIndex = paths.indexOf('/tools/vault');
    expect(vaultIndex, greaterThan(-1), reason: 'vault route exists');
    expect(vaultIndex < catchAllIndex, isTrue,
        reason: 'static /tools/vault must precede /tools/:toolId');
  });
}
