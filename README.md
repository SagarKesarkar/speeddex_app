# SpeedDex — Flutter client

Car-spotting and collection app. Built from
`../reference/SpeedDex_Detailed_Application_Specification_v2.docx`; the MotorDex
reference material was used only as genre/visual inspiration (collector-card
anatomy), not copied.

## Run

```bash
flutter pub get
flutter run                                                   # built-in development data
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080   # local API (see ../Backend)
flutter test
flutter analyze
```

`API_BASE_URL` switches every repository to the real SpeedDex API.

| Build | Allowed `API_BASE_URL` |
|---|---|
| Debug / profile | `https://…`, or `http://` to `10.0.2.2`, `localhost` or `127.0.0.1` only (debug/profile network security config) |
| Release | `https://…` only. Anything else fails at startup, and Android blocks all cleartext. |

Without `API_BASE_URL`, every tab header shows a **DEV DATA** tag and nothing leaves the device.

For a release APK pointed at a server: `flutter build apk --release --dart-define=API_BASE_URL=https://your.api.host`.

### Ads (Google AdMob)

| `--dart-define=ADS_MODE=` | Ads shown |
|---|---|
| `test` (default) | Google's sample ad units, labelled "Test Ad". Use these for all development and testing. |
| `live` | SpeedDex's own units (feed banner `…/3613905313`, rewarded `…/7536391340`). Store builds only. |
| `off` | None. |

The AdMob app ID (`ca-app-pub-1566668211654188~8609799865`) is in `AndroidManifest.xml`. Ads run on Android only; `ios/Runner/Info.plist` has Google's sample iOS app ID until there is an iOS AdMob app.

- **Feed:** one inline adaptive banner in each block of 20 posts, after a random post of that block. A feed that ends sooner shows its ad after the last post.
- **Rewarded:** "Watch reward ad · +1 scan" on the daily-limit card, and "Watch an ad to unlock free" when a player can't afford a spec sheet. The server grants the reward (see Backend README, Rewarded ads).
- **Consent:** Google's User Messaging Platform runs before the first ad, showing a consent form only where the law requires one. Configure the message in AdMob → Privacy & messaging.

## Structure

```
lib/
  app/            composition root: providers.dart, router.dart
  core/           design system (theme/, widgets/), config, errors, security, util
  domain/         typed models: RarityTier (9 spec tiers), CarCard, FeedPost, UserProfile…
  data/           repositories.dart — the integration boundary (one method per endpoint)
    api/          ApiClient (auth, refresh, error mapping), JSON mappers, HTTP repositories
  dev/            in-memory DevStore + fixtures implementing the same interfaces
  features/
    onboarding/   4-slide carousel → register / sign in
    auth/         login, register, forgot password, AuthController, validators
    shell/        5-tab shell (Feed, Ranking, Scan, Garage, Profile), splash
    feed/         list + card/reel modes, optimistic likes, comments, report
    cards/        CollectorCard widget, card detail, 5-coin unlock flow
    ranking/      scope + period filters, podium, pinned viewer rank
    scan/         camera-only capture state machine and result screens
    garage/       summary, tier distribution, grid/list, sort & filter
    profile/      spotter license, wallet, badges, edit profile, sign out
```

State management: **Riverpod 3** (`Notifier` / `FutureProvider`). Navigation:
**go_router** with `StatefulShellRoute.indexedStack` so each tab keeps its stack;
auth state drives redirects.

## API integration

- **`ApiClient`:**
  - Sends the bearer token on every request.
  - On `AUTH_TOKEN_EXPIRED`, refreshes once (concurrent requests share one refresh), stores the rotated tokens and retries.
  - If refresh fails, clears the tokens and signs the user out.
  - Maps the API error envelope onto typed `AppFailure`s: `InsufficientCoinsFailure`, `GarageFullFailure`, `DailyScanLimitFailure`, `RequestFailure(code, fieldErrors)` and so on.
  - Network errors become `NetworkFailure`; server internals are never shown.
- **Signed URLs:** upload and media links are re-pointed at the configured host. Signatures cover the path and query, so this still works behind a proxy or tunnel.
- **Scan:** upload session → signed JPEG upload → identify → poll with backoff (up to 60 s). Captures a reviewer approves later appear in **Garage → Ready to add** and reopen in the normal result screen.
- **Retries:** `providerRetry` in `main.dart` retries only transient failures, three times. Riverpod's default endless retry would otherwise hide errors behind a loading spinner.

Tests: `test/api_client_test.dart` (transport, refresh, error mapping, the HTTPS rule, mappers), `test/widgets_test.dart`, `test/ranking_screen_test.dart`, `test/retry_test.dart` and `test/logic_test.dart`. There are 28 in total, including `test/collector_card_test.dart` (cards with sparse catalogue data).

## Recent behaviour

- The app opens on the **Scan** tab, after launch and after signing in. Android back retraces visited tabs to Scan, and a second press on Scan exits.
- **Shutter to preview is instant:** the photo is shown as taken (turned upright if the phone was held sideways). Tapping **Identify** runs straightening, compression and the on-device face/plate blur (`photo_pipeline.dart`, "Blurring faces and number plates…"), then uploads. A photo that hasn't been through that step is never sent; if the check fails, nothing is sent and **Try again** runs it again.
- **Zoom:** pinch on the viewfinder, or tap 1× / 2× / 5× (only those the lens supports, up to 8×). Each camera start resets to 1×.
- Signing in refreshes Profile, Wallet, Garage and Feed, so nothing cached while signed out is shown afterwards.
- Edit profile picks Country, then City, from type-to-search lists (`SdSearchPicker`, backed by `/v1/geo`). Only listed values can be saved.
- Feed posts show the full name with `@username · level · time` muted below. Tapping the author opens `/user/:id` with Follow/Following; your own posts open the Profile tab.
- The unlock sheet re-reads the coin balance when it opens and only offers ads when the balance is short.
- Another spotter's card keeps its capture record (location, date, condition) hidden until it is unlocked. Card headers no longer show the `#00001` number; the full serial stays in the footer.
- A public profile lists that spotter's cars, 12 at a time, loading more on scroll. Locked cards carry a lock badge and open the card screen, where they can be unlocked.
- Scan: the app is portrait-only, so a photo taken with the phone sideways is turned upright using the accelerometer reading at the shutter (`photo_orientation.dart`). Every photo is re-encoded without EXIF (no GPS or device data) and capped at 1920 px before upload.
- Scan: before a shot is shown or sent, faces and number plates are found on the device with Google ML Kit (bundled models, no network) and blurred (`privacy_blur.dart`). The photo is checked whole and as four overlapping tiles (small faces, distant plates). Plates are found from recognised text: a plate-like run of words within a line, two stacked rows, or a lone number block. Photos are taken at 1080p. Known gaps: side-on faces, and plates the text recogniser can't read (tiny, steeply angled, non-Latin script). If the check can't run, the photo is discarded rather than sent unblurred. Release builds need the keep rules in `android/app/proguard-rules.pro`.
- Faces get a soft blur and plates a stronger one, each fading out at the edges (`faceBlur`, `plateBlur` in `privacy_blur.dart`).
- Tapping Followers or Following on any profile opens that list (`/followers/:id`, `/following/:id`), paged, each entry opening the spotter's profile.
- At the daily limit, Identify (or Add) shows "Oh no! Daily limit reached" over the photo with **Go Premium** and **Watch reward ad** (`DailyLimitOffer`). Neither exists yet (no store, ad SDK or ad verification), so both say "coming soon"; pass `onPremium` / `onWatchAd` to wire them up.
- Capture is native where it can be: rotation, resizing and EXIF stripping (`uprightJpegFast`, flutter_image_compress), zoom tiles cut by the GPU and passed to ML Kit as raw pixels, and the blur drawn by the GPU. Text (plates) is read on the whole photo only; faces on the whole photo and the four tiles.
- After a network error, **Try again** continues the same capture instead of uploading the photo again.
- **Share card** sits directly under the main buttons on the scan result and "In the Garage" screens, and at the end of your own cards in the Garage. The card is rendered to a PNG and handed to the system share sheet (WhatsApp, Instagram, Facebook and other installed apps). The caption names the car and tier only.
- Android back walks back through visited tabs, then to Feed; leaving the app from Feed takes a second press. On Scan, back first leaves a shot under review.
- Unlocked and own cards list everything on record: a Capture record (time captured and added, location, colour, condition, AI match, XP, serial) and Vehicle details (maker, parent company, origin, production status, engine, power, gearbox, dimensions, weight…). Figures the catalogue lacks are left out.

## Design system

| Token | Value |
|---|---|
| Surfaces | graphite `#0B0C0F` → `#242830` |
| Primary action | signal red `#E2352E` (one per screen) |
| Rewards / status | champagne gold `#D9B970` |
| Display type | Chakra Petch, uppercase |
| Body / data | Inter / JetBrains Mono (tabular figures) |
| Tier colours | `RarityTier` enum — Base → Mythic; Rare and above get a foil frame |

Tokens live in `lib/core/theme/`. Shared components: `SdButton`, `SdPanel`,
`SdSectionLabel`, `TierChip`, `StatBar`, `SdSegmented`, `SdFilterChip`,
skeleton/empty/error states, and `CarVisual`, which shows the capture photo or a
vector silhouette. No third-party car artwork is bundled.

## Security notes

Done in the client:
- Tokens only in `flutter_secure_storage` (Keychain / Keystore). Cleared on sign-out even if the server call fails.
- HTTPS enforced for `API_BASE_URL` in release builds; `usesCleartextTraffic=false`; `allowBackup=false`. The local-HTTP exception exists only in the debug and profile manifests.
- Generic login error and neutral password-reset copy (no account enumeration).
- Camera permission requested only when Scan opens; there is no photo-library path.
- Discarded captures are deleted from the device cache.
- Unlocks send an idempotency key per confirmation, so a double tap can't charge twice.
- User and server text is rendered as plain text only. Comments are trimmed and length-capped.
- Errors shown to users come from typed `AppFailure`s, never raw exceptions.

**Enforced by the backend** (`../Backend`, see its README):
- Coins, XP, rarity, Garage capacity and the daily scan limit.
- Duplicate and replace policy, and anti-spoof checks.
- Token rotation and revocation, rate limiting, and moderator/admin roles.

Store-receipt and rewarded-ad verification aren't built, so those endpoints refuse rather than trust the app.

The dev backend imitates some of these rules for UI purposes only.

## Not yet implemented
- Google sign-in in the app (needs the native Google Sign-In SDK; the API side is ready).
- A notifications inbox screen. The API records likes, comments, follows and moderation results.
- GPS tagging on capture and the Nearby ranking: the API supports both, but the app doesn't request location permission yet.
- Store purchases and the Garage-slot offers. These show as disabled "not available yet" buttons.
- Share links and account deletion.
- Legal documents: the sheet says they can't be shown yet.
- Persisting "onboarding seen" across launches.
- Bundling fonts as assets: `google_fonts` currently fetches them at runtime.
