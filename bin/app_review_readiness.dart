// app-review-readiness — App Review's point of view, not the code's.
//
// Unit tests and linters ask "is the code correct?". App Review asks a
// different question: "can a stranger who just installed this, on a free
// plan, with nothing configured, actually use and pay for the app?" Every
// check here names the guideline whose rejection it descends from.
//
// Run: dart run bin/app_review_readiness.dart --root path/to/app
import 'dart:convert';
import 'dart:io';

import 'package:app_review_readiness/app_review_readiness.dart';

const _usage = '''
Usage: dart run bin/app_review_readiness.dart [options]

  --root <dir>        project to check (default: current directory)
  --config <file>     JSON config (default: <root>/review_readiness.json if present)
  --only <ids>        comma-separated check ids to run
  --skip <ids>        comma-separated check ids to skip
  --strict            treat warnings as failures
  --json              machine-readable output
  --list-checks       print check ids and their guidelines
  -h, --help          this text

Exit codes: 0 ready, 1 at least one failure, 2 usage or config error.''';

void main(List<String> args) {
  String root = '.';
  String? configPath;
  var only = <String>{};
  var skip = <String>{};
  var strict = false;
  var json = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String next() {
      if (i + 1 >= args.length) _die('$a needs a value');
      return args[++i];
    }

    switch (a) {
      case '--root':
        root = next();
      case '--config':
        configPath = next();
      case '--only':
        only = next().split(',').map((s) => s.trim()).toSet();
      case '--skip':
        skip = next().split(',').map((s) => s.trim()).toSet();
      case '--strict':
        strict = true;
      case '--json':
        json = true;
      case '--list-checks':
        for (final c in checks) {
          stdout.writeln(
              '${c.id.padRight(22)} ${c.guideline.padRight(20)} ${c.title}');
        }
        exit(0);
      case '-h' || '--help':
        stdout.writeln(_usage);
        exit(0);
      default:
        _die('unknown option: $a');
    }
  }

  root = Directory(root).absolute.path.replaceFirst(RegExp(r'/\.?$'), '');
  if (!Directory(root).existsSync()) _die('no such directory: $root');
  final ids = checks.map((c) => c.id).toSet();
  for (final id in {...only, ...skip}) {
    if (!ids.contains(id)) _die('unknown check id: $id (see --list-checks)');
  }

  configPath ??= File('$root/review_readiness.json').existsSync()
      ? '$root/review_readiness.json'
      : null;
  Config config;
  try {
    config = configPath == null ? Config() : Config.load(configPath);
  } on FormatException catch (e) {
    _die('bad config $configPath: ${e.message}');
  } on FileSystemException catch (e) {
    _die('cannot read config $configPath: ${e.message}');
  }

  final results = runChecks(root, config, only: only, skip: skip);
  final fails = results.where((r) => r.status == Status.fail).length;
  final warns = results.where((r) => r.status == Status.warn).length;
  final failed = fails > 0 || (strict && warns > 0);
  final manual = [
    ...baseManualChecks,
    ...results.expand((r) => r.manual),
    ...config.manualChecks,
  ];

  if (json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'version': version,
      'root': root,
      'config': configPath,
      'ready': !failed,
      'failures': fails,
      'warnings': warns,
      'checks': results.map((r) => r.toJson()).toList(),
      'manual': manual,
    }));
    exit(failed ? 1 : 0);
  }

  stdout.writeln('app-review-readiness $version');
  stdout.writeln('root:   $root');
  stdout.writeln('config: ${configPath ?? '(defaults)'}');
  stdout.writeln('=' * 66);
  var n = 0;
  for (final r in results) {
    n++;
    stdout.writeln('\n$n. [${r.guideline}] ${r.title}  (${r.id})');
    for (final f in r.findings) {
      stdout.writeln('  ${_tag(f.status)} ${f.message}');
      for (final d in f.details) {
        stdout.writeln('         $d');
      }
    }
  }
  stdout.writeln('\n${'=' * 66}');
  if (failed) {
    stdout.writeln('NOT READY: $fails failing check(s), $warns with warnings'
        '${strict && fails == 0 ? ' (--strict)' : ''}.');
    stdout.writeln(
        'Each failure above matches a real App Review rejection pattern.');
  } else {
    stdout.writeln('READY: no failing checks, $warns with warnings.');
  }
  stdout.writeln('\nStill a human job before submitting:');
  for (final m in manual) {
    stdout.writeln('  - $m');
  }
  exit(failed ? 1 : 0);
}

String _tag(Status s) => switch (s) {
      Status.pass => 'PASS',
      Status.warn => 'WARN',
      Status.fail => 'FAIL',
      Status.skip => 'SKIP',
    };

Never _die(String msg) {
  stderr.writeln('app-review-readiness: $msg\n');
  stderr.writeln(_usage);
  exit(2);
}
