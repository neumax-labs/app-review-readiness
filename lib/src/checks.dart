import 'contrast.dart';
import 'project.dart';
import 'result.dart';

/// A check, and the App Review Guideline it descends from.
class CheckDef {
  final String id;
  final String guideline;
  final String title;
  final CheckResult Function(Project, CheckDef) run;
  const CheckDef(this.id, this.guideline, this.title, this.run);

  CheckResult result(List<Finding> f, [List<String> manual = const []]) =>
      CheckResult(id, guideline, title, f, manual);
}

const checks = <CheckDef>[
  CheckDef('placeholder-content', '2.1',
      'Does anything read as placeholder content?', _placeholder),
  CheckDef(
      'coming-soon',
      '2.1',
      'Is there a control whose only job is to say "coming soon"?',
      _comingSoon),
  CheckDef('beta-branding', '2.2',
      'Does the app call itself a beta, demo, or trial?', _beta),
  CheckDef('dev-urls', '2.1',
      'Does the build point at a dev or preview server?', _devUrls),
  CheckDef('web-wrapper', '4.2',
      'Is the app more than a remote website in a frame?', _webWrapper),
  CheckDef(
      'external-purchase',
      '3.1.1',
      'Does the iOS build steer the reviewer to pay outside the app?',
      _externalPurchase),
  CheckDef('purchase-reachable', '3.1.1 / 2.1',
      'Can a reviewer on a free plan actually buy something?', _purchase),
  CheckDef('sign-in-with-apple', '4.8',
      'Is Sign in with Apple offered next to third-party logins?', _siwa),
  CheckDef('account-deletion', '5.1.1(v)',
      'Can every account delete itself from inside the app?', _deletion),
  CheckDef(
      'usage-descriptions',
      '5.1.1(ii) / 2.1',
      'Does every permission the code asks for have a purpose string?',
      _usageDescriptions),
  CheckDef('privacy-manifest', '5.1.2 / ITMS-91053',
      'Does the iOS project ship a privacy manifest?', _privacyManifest),
  CheckDef('privacy-policy-link', '5.1.1(i)',
      'Is a privacy policy reachable inside the app?', _privacyPolicy),
  CheckDef('flutter-late-init', '2.1',
      'Do feature-gated Flutter screens survive their own gate?', _lateInit),
  CheckDef('contrast', '4',
      'Are configured controls visible on their background?', _contrast),
  CheckDef('custom-rules', 'config',
      'Project-specific rules from the config file', _customRules),
];

// ── helpers ─────────────────────────────────────────────────────────────────

bool _ignored(SourceFile f, int i) {
  final raw = f.rawLines;
  bool has(int n) =>
      n >= 0 && n < raw.length && raw[n].contains('review-readiness: ignore');
  return has(i) || has(i - 1);
}

/// Scans user-facing text in every non-exempt file for [pattern].
List<Hit> _scanText(Project p, RegExp pattern) {
  final hits = <Hit>[];
  final arbKeysUsed = p.dartCode;
  for (final f in p.files) {
    if (p.isExempt(f.path)) continue;
    if (f.ext == '.arb') {
      if (!_isDefaultLocaleArb(f.path)) continue;
      hits.addAll(
        _scanArb(f, pattern, arbKeysUsed)
            .where((h) => !p.isExemptKey(h.text.split(':').first)),
      );
      continue;
    }
    for (var i = 0; i < f.codeLines.length; i++) {
      final match = f.texts[i].firstWhere(pattern.hasMatch, orElse: () => '');
      if (match.isNotEmpty && !_ignored(f, i)) {
        hits.add(Hit(f.path, i + 1, match));
      }
    }
  }
  return hits;
}

/// Scan English (or unsuffixed) ARB files only: the patterns are English, and
/// a translation of a flagged string is the same finding again.
bool _isDefaultLocaleArb(String path) {
  final m =
      RegExp(r'_([a-z]{2,3})(?:[_-][A-Za-z]{2,4})?\.arb$').firstMatch(path);
  return m == null || m.group(1) == 'en';
}

const _arbMetaKeys = {'description', 'context', 'type', 'example', 'format'};

/// ARB values count only if the key is referenced from Dart code — an unused
/// message cannot render.
Iterable<Hit> _scanArb(SourceFile f, RegExp pattern, String dart) sync* {
  final re = RegExp(r'"([a-zA-Z0-9_]+)"\s*:\s*"((?:[^"\\]|\\.)*)"');
  final lines = f.raw.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final m in re.allMatches(lines[i])) {
      final key = m.group(1)!;
      if (_arbMetaKeys.contains(key)) continue;
      final value = m.group(2)!;
      if (!pattern.hasMatch(value)) continue;
      if (dart.isNotEmpty && !dart.contains('.$key')) continue;
      yield Hit(f.path, i + 1, '$key: "$value"');
    }
  }
}

List<String> _listHits(List<Hit> hits, [int max = 12]) => [
      ...hits.take(max).map((h) => h.toString()),
      if (hits.length > max) '... and ${hits.length - max} more',
    ];

/// Case-insensitive: [lowerHaystack] must already be lower-cased.
bool _containsAny(String lowerHaystack, Iterable<String> needles) =>
    needles.any((n) => lowerHaystack.contains(n.toLowerCase()));

/// Files whose code contains any of [needles], with the first hit line.
List<Hit> _codeHits(Project p, Iterable<String> needles) {
  final out = <Hit>[];
  final lower = needles.map((n) => n.toLowerCase()).toList();
  for (final f in p.files) {
    for (var i = 0; i < f.lowerLines.length; i++) {
      final l = f.lowerLines[i];
      if (lower.any(l.contains) && !_ignored(f, i)) {
        out.add(Hit(f.path, i + 1, f.codeLines[i]));
      }
    }
  }
  return out;
}

// ── 2.1 / 2.2: unfinished content ───────────────────────────────────────────

CheckResult _placeholder(Project p, CheckDef d) {
  final hits = _scanText(
    p,
    RegExp(
      r'lorem ipsum|your logo|(your|company|app|brand|business) name here|'
      r'\[(your|insert|company|app) [^\]]{1,30}\]|insert .{0,20} here|'
      r'\bTBD\b|placeholder (text|image|content)|sample (text|content)|'
      r'\bacme (inc|corp)',
      caseSensitive: false,
    ),
  );
  if (hits.isEmpty) {
    return d.result(
        [Finding(Status.pass, 'no placeholder text in user-facing strings')]);
  }
  return d.result([
    Finding(Status.fail, 'placeholder text in user-facing strings', [
      ..._listHits(hits),
      'Hide the section until real content exists. A placeholder that looks',
      'deliberate in code review reads as an unfinished app to a reviewer.',
    ]),
  ]);
}

CheckResult _comingSoon(Project p, CheckDef d) {
  final hits = _scanText(
    p,
    RegExp(r'coming\s+soon|not (yet )?implemented|under construction',
        caseSensitive: false),
  );
  if (hits.isEmpty) {
    return d.result(
        [Finding(Status.pass, 'no "coming soon" copy in user-facing strings')]);
  }
  return d.result([
    Finding(Status.fail, '"coming soon" copy is reachable', [
      ..._listHits(hits),
      'Hide the control instead of shipping one whose only function is to',
      'announce that the feature is missing.',
    ]),
  ]);
}

CheckResult _beta(Project p, CheckDef d) {
  final hits = _scanText(
    p,
    RegExp(r'\b(beta|demo version|trial version|early access|prototype)\b',
        caseSensitive: false),
  );
  if (hits.isEmpty) {
    return d.result([Finding(Status.pass, 'no beta/demo/trial branding')]);
  }
  return d.result([
    Finding(Status.fail, 'the app presents itself as a beta, demo, or trial', [
      ..._listHits(hits),
      'Guideline 2.2: betas, demos, and trial versions belong in TestFlight,',
      'not the App Store. Remove the label from the store build.',
    ]),
  ]);
}

CheckResult _devUrls(Project p, CheckDef d) {
  final hits = _scanText(
    p,
    RegExp(
      r'https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|10\.0\.2\.2|192\.168\.)|'
      r'ngrok|lovableproject\.com|id-preview--|\.replit\.dev|\.repl\.co|'
      r'stackblitz|webcontainer',
      caseSensitive: false,
    ),
  );
  if (hits.isEmpty) {
    return d
        .result([Finding(Status.pass, 'no localhost or preview-server URLs')]);
  }
  return d.result([
    Finding(Status.warn, 'dev or preview URLs in app code', [
      ..._listHits(hits),
      'If any of these is reached at runtime, the reviewer sees a blank or',
      'broken screen. Point release builds at production.',
    ]),
  ]);
}

// ── 4.2: minimum functionality ──────────────────────────────────────────────

CheckResult _webWrapper(Project p, CheckDef d) {
  final cap = p.capacitorConfig;
  if (cap == null) {
    return d.result(
        [Finding(Status.skip, 'no capacitor.config.* — not a Capacitor app')]);
  }
  final code = stripComments(cap.text, '.ts').join('\n');
  final m = RegExp(
    r'''["']?server["']?\s*:\s*\{[^}]*?["']?url["']?\s*:\s*["']([^"']+)["']''',
    dotAll: true,
  ).firstMatch(code);
  if (m == null) {
    return d.result([
      Finding(Status.pass, '${cap.path} bundles the web app (no server.url)'),
    ], [
      'open the app in airplane mode: the first screen should still render, '
          'not a white page (Guideline 4.2 and 2.1)',
    ]);
  }
  final url = m.group(1)!;
  final local =
      RegExp(r'localhost|127\.0\.0\.1|192\.168\.|10\.0\.').hasMatch(url);
  return d.result([
    Finding(
      Status.fail,
      local
          ? '${cap.path} still has live-reload server.url = $url'
          : '${cap.path} loads a remote site: server.url = $url',
      local
          ? [
              'A store build would try to reach a dev machine and show a blank',
              'screen. Remove server.url before `npx cap sync ios`.',
            ]
          : [
              'An app that only frames a website is the classic Guideline 4.2',
              'rejection. Bundle the built web app (webDir) instead, and add',
              'something native: push, offline, camera, share sheet, widgets.',
            ],
    ),
  ]);
}

// ── 3.1.1: payments ─────────────────────────────────────────────────────────

CheckResult _externalPurchase(Project p, CheckDef d) {
  if (!p.config.sellsDigitalGoods) {
    return d.result([
      Finding(Status.skip,
          'sellsDigitalGoods is false — physical goods and real-world services may use external payment'),
    ]);
  }
  const links = [
    'buy.stripe.com',
    'checkout.stripe.com',
    'billing.stripe.com',
    'redirectToCheckout',
    'createCheckoutSession',
    'create-checkout-session',
    'paypal.com/checkout',
    'lemonsqueezy.com/checkout',
    'Paddle.Checkout',
    'gumroad.com/l/',
  ];
  final copy = RegExp(
    r'(subscribe|upgrade|buy|purchase|pay|manage (your )?(subscription|billing|plan)).{0,40}'
    r'\b(on|at|via|from) (the web|our (web)?site|the website|[a-z0-9-]{1,40}\.(com|app|io|co))\b|'
    r'cheaper (on|at) (the web|our (web)?site)',
    caseSensitive: false,
  );

  final lowerLinks = links.map((l) => l.toLowerCase()).toList();
  final unguarded = <Hit>[];
  var guarded = 0;
  for (final f in p.files) {
    if (p.isExempt(f.path)) continue;
    final lower = f.lowerCode;
    for (var i = 0; i < f.codeLines.length; i++) {
      final line = f.codeLines[i];
      final ll = f.lowerLines[i];
      final isLink = lowerLinks.any(ll.contains);
      final isCopy = !isLink && f.texts[i].any(copy.hasMatch);
      if (!isLink && !isCopy) continue;
      if (_ignored(f, i)) continue;
      // Offset of this line in the file, to look for a platform guard shortly
      // before it — the same guard that should hide the button.
      final offset = f.lineOffsets[i];
      final window = lower.substring(
          (offset - 600).clamp(0, offset), offset + line.length);
      if (p.config.platformGuardPatterns
          .any((g) => window.contains(g.toLowerCase()))) {
        guarded++;
      } else {
        unguarded.add(Hit(f.path, i + 1, line));
      }
    }
  }
  if (unguarded.isEmpty) {
    return d.result([
      Finding(
        Status.pass,
        guarded == 0
            ? 'no external checkout links or "pay on the web" copy'
            : 'external checkout appears only behind a platform guard ($guarded place(s))',
      ),
    ]);
  }
  return d.result([
    Finding(Status.fail, 'external payment is reachable on iOS', [
      ..._listHits(unguarded),
      'Digital goods sold in an iOS app must use in-app purchase, and the app',
      'may not point the reviewer to a web checkout (3.1.1, 3.1.3). Hide these',
      'behind a native-platform check, or use StoreKit / RevenueCat on iOS.',
      'If you sell only physical goods or services, set "sellsDigitalGoods": false.',
    ]),
  ]);
}

CheckResult _purchase(Project p, CheckDef d) {
  if (!p.config.inAppPurchase) {
    return d.result([
      Finding(Status.skip, 'inAppPurchase is false in config — nothing to buy'),
    ]);
  }
  final hits = _codeHits(p, p.config.purchaseCallPatterns);
  if (hits.isEmpty) {
    return d.result([
      Finding(Status.fail,
          'in-app purchase is enabled but no purchase call exists', [
        'Looked for: ${p.config.purchaseCallPatterns.join(', ')}',
        'A buy button that does nothing is read as an incomplete app (2.1) and',
        'leaves the submitted subscriptions unreviewable (3.1.1).',
      ]),
    ]);
  }
  return d.result([
    Finding(Status.pass,
        'a real purchase call exists (${hits.first.file}:${hits.first.line})'),
  ], [
    'buy one product in the sandbox on a real device, from a FREE account',
    'from a free account, reach the paywall from settings/billing without '
        'hitting a feature gate first',
  ]);
}

// ── 4.8: login services ─────────────────────────────────────────────────────

CheckResult _siwa(Project p, CheckDef d) {
  const thirdParty = [
    "provider: 'google'",
    'provider: "google"',
    "provider: 'facebook'",
    'provider: "facebook"',
    "provider: 'github'",
    'provider: "github"',
    "provider: 'twitter'",
    "provider: 'discord'",
    'GoogleAuthProvider',
    'FacebookAuthProvider',
    'GithubAuthProvider',
    'TwitterAuthProvider',
    'GoogleSignIn',
    'google_sign_in',
    'signInWithGoogle',
    'loginWithGoogle',
    'capacitor-google-auth',
    'social-login',
    'flutter_facebook_auth',
    'Sign in with Google',
    'Continue with Google',
    'Login with Google',
    'Continue with Facebook',
  ];
  const apple = [
    "provider: 'apple'",
    'provider: "apple"',
    "OAuthProvider('apple.com')",
    'OAuthProvider("apple.com")',
    'AppleAuthProvider',
    'SignInWithApple',
    'sign_in_with_apple',
    'signInWithApple',
    'apple-sign-in',
    'ASAuthorizationAppleIDProvider',
    'Sign in with Apple',
    'Continue with Apple',
  ];
  final code = p.allCodeLower;
  if (!_containsAny(code, thirdParty)) {
    return d.result([
      Finding(Status.pass,
          'no third-party social login detected — 4.8 does not apply'),
    ]);
  }
  final used = thirdParty.where((t) => code.contains(t.toLowerCase()));
  if (_containsAny(code, apple)) {
    return d.result([
      Finding(
          Status.pass, 'Sign in with Apple is offered alongside ${used.first}'),
    ], [
      'with an Apple ID that has never used this app, one tap on the Apple '
          'button must land inside the app without a relaunch',
      'on a real iPhone and iPad, the Apple button is plainly a button '
          '(Apple\'s own style, readable against its background)',
    ]);
  }
  return d.result([
    Finding(Status.fail, 'third-party login without Sign in with Apple', [
      'Detected: ${used.take(4).join(', ')}',
      'Guideline 4.8: an app that offers a third-party login must also offer',
      'an equivalent privacy-focused option — in practice, Sign in with Apple.',
      'If the app qualifies for an exception, add "sign-in-with-apple" to "skip".',
    ]),
  ]);
}

// ── 5.1.1(v): account deletion ──────────────────────────────────────────────

CheckResult _deletion(Project p, CheckDef d) {
  const creates = [
    'signUp(',
    'auth.signUp',
    'createUserWithEmailAndPassword',
    'createUser(',
    'Create account',
    'Create an account',
    'Sign up',
    'signInWithOAuth',
    'signInWithIdToken',
    'GoogleSignIn',
    'SignInWithApple',
  ];
  const deletes = [
    'deleteUser',
    'deleteAccount',
    'delete_account',
    'delete_user',
    'Delete account',
    'Delete my account',
    'Delete your account',
    'currentUser?.delete(',
    'currentUser!.delete(',
    'user.delete(',
    'auth.admin.deleteUser',
    'Close account',
  ];
  if (!_containsAny(p.allCodeLower, creates)) {
    return d.result([
      Finding(Status.pass,
          'no account creation detected — 5.1.1(v) does not apply'),
    ]);
  }
  final hits = _codeHits(p, deletes);
  if (hits.isEmpty) {
    return d.result([
      Finding(
          Status.fail, 'accounts can be created but not deleted in the app', [
        'Guideline 5.1.1(v): apps that support account creation must let the',
        'user start account deletion from inside the app. A support email or',
        'a "deactivate" toggle is not enough.',
      ]),
    ]);
  }

  // The deletion entry must not sit behind a role check: a review account
  // with the default role would never see it.
  final guarded = <Hit>[];
  final guards =
      p.config.roleGuardPatterns.map((g) => g.toLowerCase()).toList();
  for (final h in hits) {
    final f = p.files.firstWhere((f) => f.path == h.file);
    final offset = f.lineOffsets[h.line - 1];
    final window =
        f.lowerCode.substring((offset - 800).clamp(0, offset), offset);
    if (guards.any(window.contains)) guarded.add(h);
  }
  final findings = [
    Finding(Status.pass,
        'an account deletion path exists (${hits.first.file}:${hits.first.line})'),
    if (guarded.isNotEmpty)
      Finding(
          Status.warn, 'account deletion may be hidden behind a role check', [
        ..._listHits(guarded, 5),
        'Deletion is self-scoped, so every role must see it. The review account',
        'usually has the default role, and cannot find what it cannot see.',
      ]),
  ];
  return d.result(findings, [
    'sign in as the review account and find "Delete account" in two taps or '
        'fewer from the main screen',
  ]);
}

// ── 5.1.1: permissions and privacy ──────────────────────────────────────────

const _permissions = <String, List<String>>{
  'NSCameraUsageDescription': [
    '@capacitor/camera',
    'Camera.getPhoto',
    'getUserMedia',
    'image_picker',
    'CameraController',
    'mobile_scanner',
    'barcode-scanner',
    'BarcodeScanner',
    'AVCaptureDevice',
    'ImageSource.camera',
    'CameraSource.Camera',
  ],
  'NSPhotoLibraryUsageDescription': [
    'Camera.pickImages',
    'CameraSource.Photos',
    'ImageSource.gallery',
    'pickMultiImage',
    'PHPhotoLibrary',
    'photo_manager',
  ],
  'NSLocationWhenInUseUsageDescription': [
    'navigator.geolocation',
    '@capacitor/geolocation',
    'Geolocation.getCurrentPosition',
    'Geolocator',
    'geolocator',
    'CLLocationManager',
    'package:location/',
  ],
  'NSMicrophoneUsageDescription': [
    'audio: true',
    'speech_to_text',
    'speech-recognition',
    'SpeechRecognition',
    'AVAudioRecorder',
    'MediaRecorder',
    'voice-recorder',
    'package:record/',
  ],
  'NSContactsUsageDescription': [
    'capacitor-community/contacts',
    'flutter_contacts',
    'CNContactStore',
  ],
  'NSFaceIDUsageDescription': [
    'local_auth',
    'LAContext',
    'native-biometric',
    'NativeBiometric',
    'BiometricAuth',
  ],
  'NSUserTrackingUsageDescription': [
    'AppTrackingTransparency',
    'requestTrackingAuthorization',
    'app_tracking_transparency',
  ],
  'NSCalendarsUsageDescription': [
    'device_calendar',
    'EKEventStore',
    'capacitor-calendar',
  ],
};

CheckResult _usageDescriptions(Project p, CheckDef d) {
  final code = p.allCode;
  final needed = <String, String>{};
  _permissions.forEach((key, signals) {
    for (final s in signals) {
      if (code.contains(s)) {
        needed[key] = s;
        break;
      }
    }
  });
  if (needed.isEmpty) {
    return d.result([Finding(Status.pass, 'no permission-gated API detected')]);
  }
  final plist = p.infoPlist;
  if (plist == null) {
    return d.result([
      Finding(Status.warn, 'permissions used but no iOS Info.plist found', [
        'Needed: ${needed.keys.join(', ')}',
        'Run `npx cap add ios` (Capacitor) or check ios/Runner (Flutter), then',
        're-run this check.',
      ]),
    ]);
  }
  final findings = <Finding>[];
  needed.forEach((key, because) {
    final m = RegExp(
      '<key>$key</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(plist.text);
    if (m == null) {
      findings.add(Finding(Status.fail, '$key missing from ${plist.path}', [
        'The code uses "$because". Without the purpose string iOS terminates the',
        'app the moment it asks — a crash in review (2.1).',
      ]));
      return;
    }
    final text = m.group(1)!.trim();
    // Apple wants the purpose, not just the permission: "needs camera
    // access" alone is the vague shape; "... to scan receipts" is not.
    final vague = text.length < 25 ||
        !RegExp(r'\b(to|so|for|when|while|in order)\b', caseSensitive: false)
            .hasMatch(text) ||
        RegExp(r'lorem|\btodo\b|\btbd\b|\btest\b', caseSensitive: false)
            .hasMatch(text);
    findings.add(vague
        ? Finding(Status.warn, '$key is vague: "$text"', [
            'Guideline 5.1.1(ii): say what the data is used for, with an example,',
            'e.g. "Takes a photo of your receipt so it can be attached to the expense."',
          ])
        : Finding(Status.pass, '$key: "$text"'));
  });
  return d.result(findings);
}

CheckResult _privacyManifest(Project p, CheckDef d) {
  if (!p.hasIosProject) {
    return d.result([Finding(Status.skip, 'no ios/ directory yet')]);
  }
  final found = p.privacyManifests();
  if (found.isEmpty) {
    return d.result([
      Finding(Status.warn, 'no PrivacyInfo.xcprivacy in the iOS project', [
        'Apple requires a privacy manifest declaring any "required reason" APIs',
        '(UserDefaults, file timestamps, disk space, boot time) and tracking',
        'domains. Missing entries produce ITMS-91053 emails and can block upload.',
        'Add ios/App/App/PrivacyInfo.xcprivacy (Capacitor) or',
        'ios/Runner/PrivacyInfo.xcprivacy (Flutter) to the app target.',
      ]),
    ]);
  }
  return d.result([
    Finding(Status.pass, 'privacy manifest: ${found.join(', ')}')
  ], [
    'the App Privacy answers in App Store Connect match every SDK in the app '
        '(analytics, crash reporting, ads, auth)',
  ]);
}

CheckResult _privacyPolicy(Project p, CheckDef d) {
  final hits = _scanText(p, RegExp(r'privacy', caseSensitive: false));
  final links = _codeHits(
      p, ['/privacy', 'privacy-policy', 'privacy_policy', 'privacyPolicy']);
  if (hits.isEmpty && links.isEmpty) {
    return d.result([
      Finding(Status.warn, 'no privacy policy link found in the app', [
        'Guideline 5.1.1(i): the privacy policy must be reachable inside the app',
        'as well as in App Store Connect. A link in settings or on the sign-up',
        'screen is enough.',
      ]),
    ]);
  }
  final at = links.isNotEmpty ? links.first : hits.first;
  return d.result([
    Finding(Status.pass, 'privacy policy referenced (${at.file}:${at.line})')
  ]);
}

// ── Flutter: a gated screen that crashes on the reviewer's plan ─────────────

CheckResult _lateInit(Project p, CheckDef d) {
  final dartFiles = p.files.where((f) => f.ext == '.dart').toList();
  if (dartFiles.isEmpty) {
    return d.result([Finding(Status.skip, 'no Dart source')]);
  }
  final broken = <String>[];
  for (final f in dartFiles) {
    final src = f.code;
    final init = RegExp(r'void initState\(\)\s*\{(.*?)\n  \}', dotAll: true)
        .firstMatch(src);
    if (init == null) continue;
    final body = init.group(1)!;
    final ret = RegExp(r'^\s*return;\s*$', multiLine: true).firstMatch(body);
    if (ret == null) continue;
    final lateFields = RegExp(
      r'^\s*late\s+(?:final\s+)?[\w<>,\s?]+\s+(_\w+)\s*;',
      multiLine: true,
    ).allMatches(src).map((m) => m.group(1)!).toSet();
    final before = body.substring(0, ret.start);
    final after = body.substring(ret.start);
    for (final field in lateFields) {
      final assign = RegExp('${RegExp.escape(field)}\\s*=(?!=)');
      if (assign.hasMatch(after) && !assign.hasMatch(before)) {
        broken.add('${f.path} -> $field');
      }
    }
  }
  if (broken.isEmpty) {
    return d.result([
      Finding(Status.pass,
          'no late field is skipped by an early return in initState'),
    ]);
  }
  return d.result([
    Finding(Status.fail, 'a gated screen crashes before its upgrade prompt', [
      ...broken,
      'These fields are assigned only after an early return, so build() reads',
      'them unassigned and throws LateInitializationError — on exactly the',
      'free plan the reviewer is using. Do the synchronous setup first; let the',
      'gate skip only the network fetch.',
    ]),
  ]);
}

// ── Guideline 4: configured contrast pairs ──────────────────────────────────

CheckResult _contrast(Project p, CheckDef d) {
  final pairs = p.config.contrast;
  if (pairs.isEmpty) {
    return d.result([Finding(Status.skip, 'no "contrast" pairs in config')]);
  }
  final findings = <Finding>[];
  for (final c in pairs) {
    final label = (c['label'] ?? 'unnamed pair').toString();
    final min = (c['min'] as num?)?.toDouble() ?? 3.0;
    final fg = resolveColor(c['foreground'], p.read);
    final bg = resolveColor(c['background'], p.read);
    if (fg == null || bg == null) {
      findings.add(Finding(Status.fail, '$label: could not resolve a color', [
        'foreground=${c['foreground']}  background=${c['background']}',
      ]));
      continue;
    }
    final r = contrastRatio(fg, bg);
    findings.add(r >= min
        ? Finding(Status.pass, '$label is visible (${r.toStringAsFixed(2)}:1)')
        : Finding(Status.fail,
            '$label is not visible (${r.toStringAsFixed(2)}:1, need $min:1)', [
            'A sign-in button painted near-black on near-black was rejected with',
            '"should be clearly identifiable to users as buttons".',
          ]));
  }
  return d.result(findings);
}

// ── Free-form rules from config ─────────────────────────────────────────────

CheckResult _customRules(Project p, CheckDef d) {
  if (p.config.rules.isEmpty) {
    return d.result([Finding(Status.skip, 'no "rules" in config')]);
  }
  final findings = <Finding>[];
  for (final r in p.config.rules) {
    final id = (r['id'] ?? r['file'] ?? 'rule').toString();
    final g = r['guideline'] == null ? '' : '[${r['guideline']}] ';
    final why =
        (r['why'] ?? '').toString().split('\n').where((l) => l.isNotEmpty);
    final file = r['file']?.toString();
    if (file == null) {
      findings.add(Finding(Status.fail, '$g$id: rule has no "file"'));
      continue;
    }
    final raw = p.read(file);
    if (raw == null) {
      findings
          .add(Finding(Status.fail, '$g$id: $file not found', why.toList()));
      continue;
    }
    final dot = file.lastIndexOf('.');
    final code =
        stripComments(raw, dot < 0 ? '' : file.substring(dot)).join('\n');
    final problems = <String>[];
    for (final s in (r['mustContain'] as List?) ?? const []) {
      if (!code.contains(s.toString())) problems.add('missing: $s');
    }
    final must = r['mustMatch']?.toString();
    if (must != null && !RegExp(must, multiLine: true).hasMatch(code)) {
      problems.add('does not match /$must/');
    }
    final mustNot = r['mustNotMatch']?.toString();
    if (mustNot != null && RegExp(mustNot, multiLine: true).hasMatch(code)) {
      problems.add('matches forbidden /$mustNot/');
    }
    findings.add(problems.isEmpty
        ? Finding(Status.pass, '$g$id')
        : Finding(Status.fail, '$g$id ($file)', [...problems, ...why]));
  }
  return d.result(findings);
}
