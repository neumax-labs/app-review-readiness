# app-review-readiness

Pre-submission checks for iOS App Review, written from the reviewer's seat.

Unit tests and linters ask *"is the code correct?"* App Review asks something
else: *"can a stranger who just installed this, on a free plan, with nothing
configured, actually use and pay for the app?"* An app can pass thousands of
tests and still be rejected for a "coming soon" button, a missing Sign in with
Apple, or an account-deletion screen the review account cannot see.

This tool scans your project for the patterns behind those rejections and
tells you which App Review Guideline each one maps to. Every check started as
a real rejection.

It works on:

- **Capacitor** apps (React, Vite, Next, Vue, Svelte) — including apps
  generated with AI app builders and wrapped for iOS
- **Flutter** apps (Dart source and `.arb` localization files)
- anything else with JS/TS/HTML/Dart/Swift/Kotlin source, with less coverage

It is a static, heuristic scan. A pass does not guarantee approval, and a
failure can be a false positive — see [Silencing a finding](#silencing-a-finding).
Nothing is uploaded anywhere; the tool only reads files on your disk.

## Quick start

Requires the [Dart SDK](https://dart.dev/get-dart) 3.5 or newer (Flutter
installs include it). No other dependencies.

```sh
git clone <this repository>
cd app-review-readiness
dart run bin/app_review_readiness.dart --root /path/to/your-app
```

Or install it as a command:

```sh
dart pub global activate --source path .
app_review_readiness --root /path/to/your-app
```

Exit codes: `0` ready, `1` at least one failing check, `2` usage or config
error — so it can gate a CI job or a release script.

## What it checks

| id | Guideline | What it looks for |
|---|---|---|
| `placeholder-content` | 2.1 App Completeness | "Lorem ipsum", "Your logo here", "[Your company]", "TBD", "sample text" in user-facing strings |
| `coming-soon` | 2.1 App Completeness | "Coming soon", "not implemented", "under construction" |
| `beta-branding` | 2.2 Beta Testing | The app calling itself a beta, demo, trial version, prototype, or early access |
| `dev-urls` | 2.1 App Completeness | `localhost`, LAN IPs, ngrok, and AI-builder preview hosts left in app code (warning) |
| `web-wrapper` | 4.2 Minimum Functionality | Capacitor `server.url` pointing at a remote site (the app is a website in a frame) or a leftover live-reload address |
| `external-purchase` | 3.1.1 In-App Purchase, 3.1.3 | Stripe/PayPal/Paddle/Lemon Squeezy/Gumroad checkout links and "subscribe on our website" copy that are not behind a native-platform check |
| `purchase-reachable` | 3.1.1, 2.1 | In-app purchase is declared but no purchase call exists (a buy button that does nothing) |
| `sign-in-with-apple` | 4.8 Login Services | Google/Facebook/GitHub login offered without Sign in with Apple |
| `account-deletion` | 5.1.1(v) Account Deletion | Sign-up exists but in-app deletion does not; deletion placed behind a role check (warning) |
| `usage-descriptions` | 5.1.1(ii) Permission, 2.1 | Camera, photos, location, microphone, contacts, Face ID, tracking, or calendar APIs used without the matching `NS...UsageDescription` in `Info.plist`; vague purpose strings (warning) |
| `privacy-manifest` | 5.1.2, ITMS-91053 | No `PrivacyInfo.xcprivacy` in the iOS project (warning) |
| `privacy-policy-link` | 5.1.1(i) Privacy Policies | No privacy policy link anywhere in the app (warning) |
| `flutter-late-init` | 2.1 App Completeness | A `late` field assigned only after an early `return` in `initState` — the screen crashes on exactly the plan the reviewer holds |
| `contrast` | 4 Design | Configured foreground/background pairs below a contrast ratio (for example, a sign-in button that disappears into its background) |
| `custom-rules` | yours | Project-specific rules from the config file |

Run `--list-checks` to print the ids.

After the automated checks, the tool prints a short **"still a human job"**
list: things only a person with a device can confirm (a working demo account
in the review notes, a sandbox purchase from a free account, a first run as a
stranger, and so on). Checks add items to this list as they apply.

### How content checks avoid false positives

- Comments are stripped before scanning, so a comment explaining a fixed
  defect does not trip the check it describes.
- Only user-facing text is scanned: string literals, and text between tags in
  JSX/HTML/Vue/Svelte. Strings used as input hints (`placeholder=`,
  `hintText:`), class names, ids, and routes are skipped.
- Strings on log, exception, assert, and `@Deprecated` lines are skipped.
- `.arb` messages count only when their key is referenced from Dart code, and
  only the English (or unsuffixed) file is scanned; `@key` metadata is ignored.
- Only folders that ship in the app are scanned (see `sourceDirs`). Within
  them, tests, stories, generated files, build output, `node_modules`, native
  shells (`ios/`, `android/`), and server code (`supabase/`, `functions/`,
  `server/`) are excluded by default. Files over 400 KB and lines over 1,500
  characters (minified bundles) are skipped.

## Options

```
--root <dir>        project to check (default: current directory)
--config <file>     JSON config (default: <root>/review_readiness.json if present)
--only <ids>        comma-separated check ids to run
--skip <ids>        comma-separated check ids to skip
--strict            treat warnings as failures
--json              machine-readable output
--list-checks       print check ids and their guidelines
```

## Configuration

Everything is optional. Put `review_readiness.json` in the project root, or
pass `--config`. A full example is in
[`example/review_readiness.json`](example/review_readiness.json).

| key | default | meaning |
|---|---|---|
| `sellsDigitalGoods` | `true` | Set `false` if the app sells only physical goods or real-world services, which may use external payment. Turns off `external-purchase`. |
| `inAppPurchase` | `false` | Set `true` if the build ships in-app purchases. Turns on `purchase-reachable`. |
| `purchaseCallPatterns` | RevenueCat, `in_app_purchase`, cordova-plugin-purchase, StoreKit 2 calls | Code that proves a real purchase happens. Replaces the default list. |
| `platformGuardPatterns` | `Capacitor.isNativePlatform()`, `kIsWeb`, `Platform.isIOS`, ... | Code that hides web-only billing on iOS. Added to the defaults. |
| `roleGuardPatterns` | `RoleGuard`, `isAdmin`, `hasRole(`, ... | Role checks that must not wrap account deletion. Replaces the default list. |
| `sourceDirs` | auto: `lib/` for Flutter; `src/`, `app/`, `pages/`, `components/`, `lib/`, `public/`, `index.html` for web projects; else the whole root | Folders whose code ships in the app. Use `["."]` to scan everything. |
| `exclude` | build, tests, native, server dirs | Extra directory names to skip. Added to the defaults. |
| `include` | — | Directory names to scan even though they are excluded by default. |
| `extensions` | `.dart .arb .js .jsx .ts .tsx .mjs .vue .svelte .html .swift .kt` | Source file extensions. Replaces the default list. |
| `exemptFiles` | — | Paths (or path suffixes) exempt from the content checks — for reviewed surfaces that cannot render in the iOS build. |
| `exemptKeys` | — | Localization (`.arb`) message keys exempt from the content checks, for messages that exist but cannot render in the store build. `prefix_*` matches a prefix. |
| `skip` | — | Check ids to turn off, e.g. `sign-in-with-apple` for an app that qualifies for a 4.8 exception. |
| `contrast` | — | `{label, foreground, background, min}`. Colors are `#RRGGBB`, `0xAARRGGBB`, or `{file, pattern}` where the regex's first group captures the hex value. |
| `rules` | — | `{id, guideline, file, mustContain, mustMatch, mustNotMatch, why}`. Use for anything specific to your app: "the paywall is linked from settings", "this feature flag stays false until the content is real", "the release script refuses to build without the purchase API key". |
| `manualChecks` | — | Extra lines for the "still a human job" list. |

## Silencing a finding

Put `review-readiness: ignore` in a comment on the flagged line or the line
above it:

```tsx
{/* review-readiness: ignore — web-only page, never bundled into the iOS build */}
<p>Coming soon to Android</p>
```

For whole files, use `exemptFiles`. For whole checks, use `skip`.

## Example output

```
5. [4.2] Is the app more than a remote website in a frame?  (web-wrapper)
  FAIL capacitor.config.ts loads a remote site: server.url = https://my-app.example-host.app
         An app that only frames a website is the classic Guideline 4.2
         rejection. Bundle the built web app (webDir) instead, and add
         something native: push, offline, camera, share sheet, widgets.

8. [4.8] Is Sign in with Apple offered next to third-party logins?  (sign-in-with-apple)
  FAIL third-party login without Sign in with Apple
         Detected: provider: 'google', Continue with Google
```

## Development

```sh
dart pub get
dart analyze
dart test
```

`test/fixtures/` holds three tiny projects: a Capacitor app with every classic
mistake, the same app fixed, and a Flutter app with a gated-screen crash.

## License

MIT. See [LICENSE](LICENSE).
