import 'dart:math' as math;

/// Resolves a config color: `"#RRGGBB"`, `"0xAARRGGBB"`, or
/// `{"file": "...", "pattern": "..."}` whose first capture group is a 6- or
/// 8-digit hex color (8 digits are read as AARRGGBB). Returns 0xRRGGBB.
int? resolveColor(Object? spec, String? Function(String) read) {
  if (spec is String) return parseHex(spec);
  if (spec is Map) {
    final file = spec['file']?.toString();
    final pattern = spec['pattern']?.toString();
    if (file == null || pattern == null) return null;
    final src = read(file);
    if (src == null) return null;
    final m = RegExp(pattern).firstMatch(src);
    if (m == null || m.groupCount < 1) return null;
    return parseHex(m.group(1)!);
  }
  return null;
}

int? parseHex(String s) {
  var h = s
      .trim()
      .replaceFirst('#', '')
      .replaceFirst(RegExp('^0x', caseSensitive: false), '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 8) h = h.substring(2); // AARRGGBB -> RRGGBB
  if (h.length != 6) return null;
  return int.tryParse(h, radix: 16);
}

double _channel(int eight) {
  final v = eight / 255.0;
  return v <= 0.03928
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4) as double;
}

double luminance(int rgb) =>
    0.2126 * _channel((rgb >> 16) & 0xFF) +
    0.7152 * _channel((rgb >> 8) & 0xFF) +
    0.0722 * _channel(rgb & 0xFF);

/// WCAG 2.x contrast ratio, 1.0 to 21.0.
double contrastRatio(int a, int b) {
  final la = luminance(a);
  final lb = luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
