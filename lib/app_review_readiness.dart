/// Pre-submission checks for iOS App Review, from the reviewer's seat.
library;

import 'src/checks.dart';
import 'src/config.dart';
import 'src/project.dart';
import 'src/result.dart';

export 'src/checks.dart' show checks, CheckDef;
export 'src/config.dart';
export 'src/contrast.dart' show contrastRatio, parseHex;
export 'src/project.dart' show Project, stripComments;
export 'src/result.dart';

const version = '0.1.0';

/// Runs every check (minus `config.skip` and [skip], limited to [only] when
/// non-empty) against the project at [root].
List<CheckResult> runChecks(
  String root,
  Config config, {
  Set<String> only = const {},
  Set<String> skip = const {},
}) {
  final project = Project.scan(root, config);
  final out = <CheckResult>[];
  for (final c in checks) {
    if (only.isNotEmpty && !only.contains(c.id)) continue;
    if (config.skip.contains(c.id) || skip.contains(c.id)) {
      out.add(c.result([Finding(Status.skip, 'skipped by configuration')]));
      continue;
    }
    out.add(c.run(project, c));
  }
  return out;
}

/// Human-job reminders that always apply, whatever the code says.
const baseManualChecks = <String>[
  'App Review notes contain a working demo account (and any 2FA bypass) '
      'that reaches every paid screen',
  'screenshots show the app in use, not a splash or login screen (2.3.3)',
  'metadata names no other platform ("Android", "Google Play") (2.3.10)',
  'first run on a device, as a stranger, on a free plan, with nothing '
      'configured: every tab opens without a crash or a blank screen',
];
