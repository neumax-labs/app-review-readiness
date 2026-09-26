import 'dart:convert';
import 'dart:io';

/// Everything project-specific lives here. Every field has a default that
/// works for a typical Capacitor (React/Vite/Next) or Flutter project, so an
/// empty config — or no config file at all — is a valid starting point.
class Config {
  /// Directory names never scanned for user-facing source (build output,
  /// dependencies, native shells, server code that never ships in the binary).
  final Set<String> excludeDirs;

  /// Directories (relative to the root) that hold code shipped in the app.
  /// Null means auto-detect: `lib/` for Flutter, `src/` plus the usual
  /// framework folders for web projects, otherwise the whole root.
  final List<String>? sourceDirs;

  /// File extensions treated as app source.
  final Set<String> extensions;

  /// Relative file paths (or path suffixes) that are exempt from the content
  /// scans. Use for reviewed, unreachable surfaces (web-only pages, dead code).
  final List<String> exemptFiles;

  /// Localization message keys (ARB) exempt from the content scans, for
  /// messages that exist but cannot render in the store build. A trailing `*`
  /// matches a key prefix, e.g. `paywall_testimonial_*`.
  final List<String> exemptKeys;

  /// Check ids to skip entirely (e.g. `sign-in-with-apple` for an app that
  /// qualifies for a Guideline 4.8 exception).
  final Set<String> skip;

  /// True if the app sells digital content or features (subscriptions,
  /// credits, unlocks). Physical goods and real-world services may use
  /// external payment, so set this to false for those apps.
  final bool sellsDigitalGoods;

  /// True if the build ships in-app purchases. Enables the "can the reviewer
  /// actually buy something" check.
  final bool inAppPurchase;

  /// Code patterns that prove a real purchase call exists.
  final List<String> purchaseCallPatterns;

  /// Code patterns that, when they appear shortly before web-billing copy or
  /// an external checkout link in the same file, mean it is hidden on iOS.
  final List<String> platformGuardPatterns;

  /// Patterns that restrict a UI element to certain roles. Account deletion
  /// appearing right after one of these is flagged.
  final List<String> roleGuardPatterns;

  /// Extra free-form rules: `{id, guideline, file, mustContain, mustMatch,
  /// mustNotMatch, why}`.
  final List<Map<String, dynamic>> rules;

  /// Contrast checks: `{label, foreground, background, min, guideline}`.
  /// Colors are `#RRGGBB`, or `{file, pattern}` where the pattern captures a
  /// 6- or 8-digit hex color.
  final List<Map<String, dynamic>> contrast;

  /// Extra lines added to the "still a human job" list.
  final List<String> manualChecks;

  Config({
    Set<String>? excludeDirs,
    Set<String>? extensions,
    this.sourceDirs,
    this.exemptFiles = const [],
    this.exemptKeys = const [],
    this.skip = const {},
    this.sellsDigitalGoods = true,
    this.inAppPurchase = false,
    List<String>? purchaseCallPatterns,
    List<String>? platformGuardPatterns,
    List<String>? roleGuardPatterns,
    this.rules = const [],
    this.contrast = const [],
    this.manualChecks = const [],
  })  : excludeDirs = excludeDirs ?? defaultExcludeDirs,
        extensions = extensions ?? defaultExtensions,
        purchaseCallPatterns = purchaseCallPatterns ?? defaultPurchaseCalls,
        platformGuardPatterns = platformGuardPatterns ?? defaultPlatformGuards,
        roleGuardPatterns = roleGuardPatterns ?? defaultRoleGuards;

  static const defaultExcludeDirs = <String>{
    '.git',
    'node_modules',
    'build',
    'dist',
    'out',
    '.dart_tool',
    '.next',
    '.nuxt',
    '.output',
    '.svelte-kit',
    '.vercel',
    '.idea',
    '.vscode',
    'coverage',
    'ios',
    'android',
    'macos',
    'windows',
    'linux',
    'web-build',
    'Pods',
    'DerivedData',
    '.gradle',
    'test',
    'tests',
    '__tests__',
    'e2e',
    'integration_test',
    'cypress',
    'playwright',
    'supabase',
    'functions',
    'server',
    'scripts',
    'fixtures',
    'mocks',
    '__mocks__',
    'stories',
    'example',
    'generated',
  };

  static const defaultExtensions = <String>{
    '.dart',
    '.arb',
    '.js',
    '.jsx',
    '.ts',
    '.tsx',
    '.mjs',
    '.vue',
    '.svelte',
    '.html',
    '.swift',
    '.kt',
  };

  static const defaultPurchaseCalls = <String>[
    'purchasePackage(', // RevenueCat (Flutter, Capacitor, RN)
    'purchaseStoreProduct(', // RevenueCat
    'Purchases.purchase', // RevenueCat Capacitor plugin
    'buyNonConsumable(', // in_app_purchase (Flutter)
    'buyConsumable(', // in_app_purchase (Flutter)
    'store.order(', // cordova-plugin-purchase
    'NativePurchases.purchaseProduct', // @capgo/native-purchases
    'InAppPurchase2', // older cordova plugin
    'Product.purchase(', // StoreKit 2
    '.purchase(', // generic fallback
  ];

  static const defaultPlatformGuards = <String>[
    'Capacitor.isNativePlatform()',
    "Capacitor.getPlatform() === 'web'",
    'Capacitor.getPlatform() === "web"',
    "Capacitor.getPlatform() !== 'ios'",
    'Capacitor.getPlatform() !== "ios"',
    'isNativePlatform',
    'kIsWeb',
    'Platform.isIOS',
    'externalPurchaseAllowed',
  ];

  static const defaultRoleGuards = <String>[
    'RoleGuard',
    'isAdmin',
    'isOwner',
    "role === 'admin'",
    'role === "admin"',
    "role == 'admin'",
    'hasRole(',
  ];

  /// Loads [path]; throws [FormatException] on malformed input.
  static Config load(String path) {
    final raw = jsonDecode(File(path).readAsStringSync());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('config root must be a JSON object');
    }
    return Config.fromJson(raw);
  }

  factory Config.fromJson(Map<String, dynamic> j) {
    List<String>? strings(String key) {
      final v = j[key];
      if (v == null) return null;
      if (v is! List) throw FormatException('"$key" must be a list');
      return v.map((e) => e.toString()).toList();
    }

    List<Map<String, dynamic>> maps(String key) {
      final v = j[key];
      if (v == null) return const [];
      if (v is! List) throw FormatException('"$key" must be a list');
      return v.map((e) {
        if (e is! Map<String, dynamic>) {
          throw FormatException('every entry of "$key" must be an object');
        }
        return e;
      }).toList();
    }

    bool flag(String key, bool fallback) {
      final v = j[key];
      if (v == null) return fallback;
      if (v is! bool) throw FormatException('"$key" must be true or false');
      return v;
    }

    final extraExclude = strings('exclude') ?? const [];
    final ext = strings('extensions');
    return Config(
      excludeDirs: {...defaultExcludeDirs, ...extraExclude}
        ..removeAll(strings('include') ?? const []),
      extensions: ext?.map((e) => e.startsWith('.') ? e : '.$e').toSet(),
      sourceDirs: strings('sourceDirs'),
      exemptFiles: strings('exemptFiles') ?? const [],
      exemptKeys: strings('exemptKeys') ?? const [],
      skip: (strings('skip') ?? const []).toSet(),
      sellsDigitalGoods: flag('sellsDigitalGoods', true),
      inAppPurchase: flag('inAppPurchase', false),
      purchaseCallPatterns: strings('purchaseCallPatterns'),
      platformGuardPatterns: [
        ...defaultPlatformGuards,
        ...?strings('platformGuardPatterns'),
      ],
      roleGuardPatterns: strings('roleGuardPatterns'),
      rules: maps('rules'),
      contrast: maps('contrast'),
      manualChecks: strings('manualChecks') ?? const [],
    );
  }
}
