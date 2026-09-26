import 'dart:io';

import 'config.dart';

/// Files larger than this are build output or data, not hand-written UI.
const maxFileBytes = 400 * 1024;

/// Lines longer than this are minified code or embedded data.
const maxLineLength = 1500;

/// A place in the source, for pointing a human at it.
class Hit {
  final String file;
  final int line;
  final String text;
  Hit(this.file, this.line, this.text);

  @override
  String toString() => '$file:$line  ${_clip(text)}';

  static String _clip(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 90 ? '${t.substring(0, 87)}...' : t;
  }
}

/// One scanned source file.
class SourceFile {
  final String path; // relative to the project root, '/'-separated
  final String ext;
  final String raw;

  /// Same line count as [raw], with comments blanked out. Checks look for
  /// patterns by substring, and a comment explaining a fixed defect naturally
  /// quotes the defect, so comments must not count.
  final List<String> codeLines;

  SourceFile(this.path, this.ext, this.raw)
      : codeLines = stripComments(raw, ext);

  late final String code = codeLines.join('\n');
  late final List<String> rawLines = raw.split('\n');
  late final String lowerCode = code.toLowerCase();
  late final List<String> lowerLines = lowerCode.split('\n');

  /// Character offset of each line start in [code].
  late final List<int> lineOffsets = () {
    final out = <int>[];
    var at = 0;
    for (final l in codeLines) {
      out.add(at);
      at += l.length + 1;
    }
    return out;
  }();

  /// [userFacingText] for every code line, computed once and shared by all
  /// content checks.
  late final List<List<String>> texts = [
    for (final l in codeLines) userFacingText(l, this),
  ];

  bool get isMarkup => const {
        '.jsx',
        '.tsx',
        '.html',
        '.vue',
        '.svelte',
      }.contains(ext);
}

/// The project under review.
class Project {
  final String root;
  final Config config;
  final List<SourceFile> files;

  Project._(this.root, this.config, this.files);

  factory Project.scan(String root, Config config) {
    final files = <SourceFile>[];
    final roots = config.sourceDirs ?? detectSourceDirs(root);
    final entries = <File>[
      for (final d in roots)
        if (d == '.' || d.isEmpty)
          ...walk(Directory(root), config.excludeDirs)
        else if (FileSystemEntity.isFileSync('$root/$d'))
          File('$root/$d')
        else if (Directory('$root/$d').existsSync())
          ...walk(Directory('$root/$d'), config.excludeDirs),
    ];
    for (final e in entries) {
      final rel = relative(e.path, root);
      final parts = rel.split('/');
      final name = parts.last;
      final dot = name.lastIndexOf('.');
      if (dot < 0) continue;
      final ext = name.substring(dot);
      if (!config.extensions.contains(ext)) continue;
      if (_isTestOrGenerated(name)) continue;
      if (e.lengthSync() > maxFileBytes) continue; // bundles, data dumps
      String text;
      try {
        text = e.readAsStringSync();
      } on FileSystemException {
        continue; // binary or unreadable
      }
      files.add(SourceFile(rel, ext, text));
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return Project._(root, config, files);
  }

  /// The folders that end up in the app binary, for common project shapes.
  static List<String> detectSourceDirs(String root) {
    final pubspec = File('$root/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec
            .readAsStringSync()
            .contains(RegExp(r'^\s*flutter:', multiLine: true)) &&
        Directory('$root/lib').existsSync()) {
      return const ['lib'];
    }
    if (File('$root/package.json').existsSync()) {
      const web = [
        'src',
        'app',
        'pages',
        'components',
        'lib',
        'public',
        'index.html',
      ];
      final found = web
          .where((d) =>
              FileSystemEntity.typeSync('$root/$d') !=
              FileSystemEntityType.notFound)
          .toList();
      if (found.isNotEmpty) return found;
    }
    return const ['.'];
  }

  static bool _isTestOrGenerated(String name) =>
      name.endsWith('_test.dart') ||
      name.endsWith('.g.dart') ||
      name.endsWith('.freezed.dart') ||
      name.contains('.test.') ||
      name.contains('.spec.') ||
      name.contains('.stories.') ||
      name.endsWith('.min.js') ||
      name.endsWith('.d.ts');

  /// ARB message keys exempt from content checks; `prefix*` matches a prefix.
  bool isExemptKey(String key) => config.exemptKeys.any(
        (x) => x.endsWith('*')
            ? key.startsWith(x.substring(0, x.length - 1))
            : key == x,
      );

  bool isExempt(String relPath) =>
      config.exemptFiles.any((x) => relPath == x || relPath.endsWith(x));

  /// Reads a file relative to the root, or null.
  String? read(String relPath) {
    final f = File('$root/$relPath');
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  bool exists(String relPath) =>
      File('$root/$relPath').existsSync() ||
      Directory('$root/$relPath').existsSync();

  /// Dependency manifests, concatenated — detecting a plugin by its package
  /// name is more reliable than guessing from call sites.
  late final String manifests = [
    read('package.json'),
    read('pubspec.yaml'),
    read('ios/App/Podfile'),
    read('ios/Podfile'),
  ].whereType<String>().join('\n');

  /// All app code (comments stripped) plus the manifests.
  late final String allCode = [
    ...files.map((f) => f.code),
    manifests,
  ].join('\n');
  late final String allCodeLower = allCode.toLowerCase();

  /// All Dart code, comments stripped (for ARB key lookups).
  late final String dartCode =
      files.where((f) => f.ext == '.dart').map((f) => f.code).join('\n');

  /// Capacitor config text, whichever flavor exists.
  late final ({String path, String text})? capacitorConfig = () {
    for (final p in const [
      'capacitor.config.json',
      'capacitor.config.ts',
      'capacitor.config.js',
    ]) {
      final t = read(p);
      if (t != null) return (path: p, text: t);
    }
    return null;
  }();

  /// The app target's Info.plist, if there is an iOS project.
  late final ({String path, String text})? infoPlist = () {
    final ios = Directory('$root/ios');
    if (!ios.existsSync()) return null;
    final candidates = <String>[];
    for (final e in walk(ios, _iosSkip)) {
      if (!e.path.endsWith('/Info.plist')) continue;
      final rel = relative(e.path, root);
      if (RegExp(
        r'/(Pods|DerivedData|build)/|\.(framework|bundle|xcframework|appex)/|Tests?/',
      ).hasMatch(rel)) {
        continue;
      }
      candidates.add(rel);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      int score(String p) =>
          (p.contains('/App/App/') || p.contains('/Runner/')) ? 0 : 1;
      final s = score(a).compareTo(score(b));
      return s != 0 ? s : a.length.compareTo(b.length);
    });
    return (path: candidates.first, text: read(candidates.first)!);
  }();

  bool get hasIosProject => Directory('$root/ios').existsSync();

  /// Finds privacy manifests anywhere in the iOS project, excluding Pods.
  List<String> privacyManifests() {
    final ios = Directory('$root/ios');
    if (!ios.existsSync()) return const [];
    return walk(ios, _iosSkip)
        .map((f) => relative(f.path, root))
        .where((p) => p.endsWith('PrivacyInfo.xcprivacy'))
        .where((p) => !p.contains('/Pods/') && !p.contains('/build/'))
        .toList();
  }
}

const _iosSkip = {
  'Pods',
  'DerivedData',
  'build',
  '.symlinks',
  'Flutter',
  'public'
};

/// Recursive file walk that never descends into [skipDirs] — listing
/// node_modules or Pods first and filtering afterwards takes minutes.
Iterable<File> walk(Directory dir, Set<String> skipDirs) sync* {
  List<FileSystemEntity> entries;
  try {
    entries = dir.listSync(followLinks: false);
  } on FileSystemException {
    return;
  }
  for (final e in entries) {
    if (e is File) {
      yield e;
    } else if (e is Directory) {
      final name = e.path.substring(e.path.lastIndexOf('/') + 1);
      if (name.startsWith('.') || skipDirs.contains(name)) continue;
      yield* walk(e, skipDirs);
    }
  }
}

String relative(String path, String root) {
  final r = root.endsWith('/') ? root : '$root/';
  return path.startsWith(r) ? path.substring(r.length) : path;
}

/// Blanks `//`, `/* */` and `<!-- -->` comments while keeping line numbers.
/// Quoted strings are respected so URLs survive. Single and double quotes end
/// at a newline (an apostrophe in markup text must not swallow the file);
/// backtick template strings may span lines.
List<String> stripComments(String src, String ext) {
  if (ext == '.arb' || ext == '.json') return src.split('\n');
  final slashComments = ext != '.html';
  final htmlComments = const {'.html', '.vue', '.svelte'}.contains(ext);

  final out = StringBuffer();
  var i = 0;
  String? quote; // current string delimiter
  var block = false; // inside /* */
  var html = false; // inside <!-- -->
  bool at(String s) => src.startsWith(s, i);

  while (i < src.length) {
    final c = src[i];
    if (block) {
      if (at('*/')) {
        block = false;
        i += 2;
      } else {
        out.write(c == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    if (html) {
      if (at('-->')) {
        html = false;
        i += 3;
      } else {
        out.write(c == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    if (quote != null) {
      if (c == '\\' && i + 1 < src.length) {
        out.write(src.substring(i, i + 2));
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      if (c == '\n' && quote != '`') quote = null;
      out.write(c);
      i++;
      continue;
    }
    if (slashComments && at('//')) {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (slashComments && at('/*')) {
      block = true;
      i += 2;
      continue;
    }
    if (htmlComments && at('<!--')) {
      html = true;
      i += 4;
      continue;
    }
    if (slashComments && (c == '"' || c == "'" || c == '`')) quote = c;
    out.write(c);
    i++;
  }
  return out.toString().split('\n');
}

final _single = RegExp(r"'((?:[^'\\\n]|\\.)*)'");
final _double = RegExp(r'"((?:[^"\\\n]|\\.)*)"');
final _backtick = RegExp(r'`((?:[^`\\\n]|\\.)*)`');
final _markupText = RegExp(r'>([^<>{}]+)<');
final _hintContext = RegExp(
  r'(placeholder|hintText|hint|labelText|aria-label|alt|className|class|id|key|href|src|to|path|name|type|testID|data-testid)\s*[=:]\s*\{?\s*$',
);

/// Lines whose strings go to logs, exceptions, or annotations — developers
/// read those, reviewers do not.
final _devOnlyLine = RegExp(
  r'\b(print|debugPrint|log|assert)\(|console\.\w+\(|\blogger\.|\bLogger\.|'
  r'\bthrow\b|Exception\(|Error\(|@Deprecated|@deprecated|Sentry\.|captureMessage',
);

final _looksLikeCode =
    RegExp(r'[;=(){}<>]|^\s*(import|export|const|let|var|return)\b');

/// Text a user could plausibly see: string literals, plus markup text for
/// JSX/HTML-like files. Strings used as input hints, class names, ids, and
/// routes are skipped — "Your company name" as an input placeholder is
/// correct UI, not unfinished content.
List<String> userFacingText(String line, SourceFile f) {
  final out = <String>[];
  if (line.length > maxLineLength) return out; // minified or data blob
  if (_devOnlyLine.hasMatch(line)) return out;
  for (final re in [_single, _double, _backtick]) {
    for (final m in re.allMatches(line)) {
      if (_hintContext.hasMatch(line.substring(0, m.start))) continue;
      final s = m.group(1)!;
      if (s.startsWith('package:') ||
          s.startsWith('./') ||
          s.startsWith('../')) {
        continue;
      }
      out.add(s);
    }
  }
  if (f.isMarkup) {
    out.addAll(
      _markupText
          .allMatches(line)
          .map((m) => m.group(1)!)
          .where((t) => t.contains(RegExp('[A-Za-z]'))),
    );
    final t = line.trim();
    if (t.isNotEmpty &&
        !_looksLikeCode.hasMatch(t) &&
        RegExp('[A-Za-z]{2}').hasMatch(t)) {
      out.add(t); // a bare text line between tags
    }
  }
  return out;
}
