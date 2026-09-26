import 'package:app_review_readiness/app_review_readiness.dart';
import 'package:test/test.dart';

const fixtures = 'test/fixtures';

Map<String, Status> statuses(List<CheckResult> r) => {
      for (final c in r) c.id: c.status,
    };

void main() {
  group('rejected_app (Capacitor, every classic mistake)', () {
    final r = statuses(runChecks('$fixtures/rejected_app', Config()));

    test('flags unfinished content (2.1, 2.2)', () {
      expect(r['placeholder-content'], Status.fail);
      expect(r['coming-soon'], Status.fail);
      expect(r['beta-branding'], Status.fail);
      expect(r['dev-urls'], Status.warn);
    });
    test('flags a remote-website wrapper (4.2)', () {
      expect(r['web-wrapper'], Status.fail);
    });
    test('flags unguarded web checkout (3.1.1)', () {
      expect(r['external-purchase'], Status.fail);
    });
    test('flags Google login without Apple (4.8)', () {
      expect(r['sign-in-with-apple'], Status.fail);
    });
    test('flags sign-up without deletion (5.1.1(v))', () {
      expect(r['account-deletion'], Status.fail);
    });
    test('flags camera use without a purpose string', () {
      expect(r['usage-descriptions'], Status.fail);
      expect(r['privacy-manifest'], Status.warn);
      expect(r['privacy-policy-link'], Status.warn);
    });
  });

  group('ready_app (same app, fixed)', () {
    final results = runChecks(
      '$fixtures/ready_app',
      Config.load('$fixtures/ready_app/review_readiness.json'),
    );

    test('has no failures or warnings', () {
      final bad = results
          .where((c) => c.status == Status.fail || c.status == Status.warn)
          .map((c) => '${c.id}: ${c.findings.map((f) => f.message)}');
      expect(bad, isEmpty);
    });
    test('input placeholders and comments are not "unfinished content"', () {
      final s = statuses(results);
      expect(s['placeholder-content'], Status.pass);
      expect(s['coming-soon'], Status.pass);
    });
    test('config-driven checks ran', () {
      final s = statuses(results);
      expect(s['purchase-reachable'], Status.pass);
      expect(s['contrast'], Status.pass);
      expect(s['custom-rules'], Status.pass);
    });
  });

  group('flutter_app', () {
    final r = statuses(runChecks('$fixtures/flutter_app', Config()));

    test('catches a late field skipped by an early return', () {
      expect(r['flutter-late-init'], Status.fail);
    });
    test('ARB strings count only when referenced', () {
      // "Beta" is referenced from Dart; "Coming soon" is an unused key.
      expect(r['beta-branding'], Status.fail);
      expect(r['coming-soon'], Status.pass);
    });
  });

  group('config', () {
    test('skip list turns a check off', () {
      final r = statuses(runChecks(
        '$fixtures/rejected_app',
        Config.fromJson({
          'skip': ['sign-in-with-apple']
        }),
      ));
      expect(r['sign-in-with-apple'], Status.skip);
    });
    test('sellsDigitalGoods: false allows external payment', () {
      final r = statuses(runChecks(
        '$fixtures/rejected_app',
        Config.fromJson({'sellsDigitalGoods': false}),
      ));
      expect(r['external-purchase'], Status.skip);
    });
    test('rejects malformed values', () {
      expect(() => Config.fromJson({'skip': 'x'}), throwsFormatException);
      expect(() => Config.fromJson({'inAppPurchase': 'yes'}),
          throwsFormatException);
    });
  });

  group('helpers', () {
    test('stripComments keeps URLs and line count', () {
      final lines = stripComments(
        "const a = 'https://x.io'; // coming soon\n/* beta\n */ b();",
        '.ts',
      );
      expect(lines, hasLength(3));
      expect(lines[0], contains('https://x.io'));
      expect(lines[0], isNot(contains('coming soon')));
      expect(lines[1], isNot(contains('beta')));
      expect(lines[2], contains('b();'));
    });
    test('contrast ratio matches WCAG reference values', () {
      expect(contrastRatio(0xFFFFFF, 0x000000), closeTo(21.0, 0.01));
      expect(contrastRatio(0x777777, 0xFFFFFF), closeTo(4.48, 0.01));
      expect(parseHex('0xFF0B1B3A'), 0x0B1B3A);
      expect(parseHex('#fff'), 0xFFFFFF);
    });
  });
}
