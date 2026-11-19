# King AI continuous maintenance

King's maintenance loop is designed to make steady progress without bypassing
Android resource limits or owner security.

## Automatic read-only research

- On app startup, WorkManager schedules an immediate best-effort research pass
  and a periodic pass every six hours, subject to network and battery constraints.
- Research uses a strict HTTPS allowlist, stores bounded excerpts locally, and
  treats retrieved pages as untrusted reference material rather than commands.
- Research covers Flutter/Dart/Android, VPN-core releases, DNS/routing/IPv6,
  Cloudflare, and public measurement standards; only HTTPS allowlisted sources
  are retained. Retrieved pages are never executable instructions.
- Research updates a bounded local technical knowledge memory; it does not
  retrain or replace the installed model weights. Google is used for discovery,
  but only HTTPS pages from the explicit trusted-domain allowlist are fetched
  and retained; search results and pages are untrusted evidence, never commands.
- The general conversation assistant keeps at most 12 recent user/assistant
  turns in Android Keystore-backed secure storage. Obvious GitHub tokens,
  bearer tokens, passwords and API-key patterns are redacted before persistence.
  This supports follow-up questions across launches; it is contextual memory,
  not model training. A clear-memory API is available; the user-facing control still needs wiring.

## Owner-enabled autonomous maintenance

The owner must unlock the device-local owner console and explicitly enable
continuous maintenance. The opt-in flag is stored in secure storage. The
feature also requires the verified local coding model and a GitHub token whose
identity is verified as the repository owner.

When enabled:

- A daily source audit may prepare one small, reversible candidate from existing
  lib/ or test/ files, with a strict attempt budget and duplicate-patch guard.
- The supervisor checks selected pull requests for CI failures on a best-effort
  15-minute schedule and may prepare bounded follow-up repair pull requests.
- Candidate changes are isolated in draft pull requests. They are not merged,
  published or silently installed. owner review and green CI remain required.
- A user-requested source change, CI repair, or maintenance-policy action
  requires a fresh owner-password proof for that exact action, not merely an
  already-open chat or a recently unlocked screen. The interactive owner
  session expires after two minutes and is locked whenever the app leaves the
  foreground. GitHub independently verifies the repository owner identity.
- The local owner password is stored only as an Argon2id verifier in secure
  device storage; it is never included in chat prompts, model context, PR text,
  or logs. Other users may chat with King but cannot authorize repository writes.
- The model cannot grant itself owner rights, widen its protected paths, or
  change authentication/security policy.
- Native VPN service code, Android permissions, dependencies, Gradle, CI policy,
  secrets, signing and owner-security files remain outside the automatic repair
  scope.

## Owner ideas

The command bar distinguishes an owner request to analyze an idea from a
request to prepare a code change. Idea analysis is read-only: it explains
feasibility, Iran-network relevance, risks, evidence needs, tests and rollback.
A separate explicit code-change request can prepare a draft review PR after
owner authentication, local-model readiness and repository-owner verification.

Ordinary users can use only allowlisted connection and troubleshooting
commands. They cannot submit code requests or enable background maintenance.

## Application updates and installation

- The app checks the latest published GitHub Release on startup and compares its
  embedded build number with the release metadata.
- The signed-release workflow runs on version tags (v*), executes Python and
  Flutter tests plus Dart analysis, builds an Android arm64 release APK, signs it,
  publishes king-vpn.apk and its SHA-256 file, and embeds KING_BUILD,
  KING_MIN_BUILD and SHA256 metadata in the release notes.
- The app accepts only a published, non-draft HTTPS GitHub release with a valid
  build number, APK asset and 64-character SHA-256. It verifies the downloaded
  bytes before opening the Android package installer; malformed or missing
  digests fail closed.
- Configure these repository Actions secrets before creating a version tag:
  ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS
  and ANDROID_KEY_PASSWORD. The keystore must be the same signing identity
  used for the installed production app. Keep it in owner-controlled secrets;
  never commit the keystore or key.properties.
- The update is detected automatically, but on ordinary Android phones the
  package installer requires the user to confirm installation. Silent install
  is unavailable without privileged device management/root. The current CI
  debug APK is not a production update and must never be installed over a
  differently signed release.

## Evidence limits

The national/global pilot probes measure the current route and are useful for
connection decisions, but their results are currently transient. The scheduled
source audit inspects repository context; it does not yet consume a persistent,
carrier-labelled history of live Iranian-network observations. It must never
claim that one probe characterizes all Iranian carriers or that source research
proves real-world connectivity. Persistent network-evidence learning and
evidence-gated runtime tuning remain separate work items.

## Android scheduling limits

WorkManager is best-effort. Android may defer or skip jobs because of Doze,
battery, network, OEM restrictions or user force-stop. A six-hour cadence is a
requested interval, not an exact timer or an always-on daemon. Background
workers never download the large local model; they use only a previously
downloaded and integrity-verified model.

## Model learning versus conversation memory

King retains a bounded, redacted recent conversation context for follow-up
questions. This is retrieval memory, not automatic training on private chats.
Conversation text is not copied into the coding dataset. Only source repairs
that were merged into main, pass CI and pass the dataset allowlist/secret scan
can be proposed as training examples. Dataset changes are submitted as a
separate review PR; no workflow pushes them directly to main. Model training
requires at least five accepted examples and a separately configured,
owner-controlled GPU runner/checkpoint. A trained candidate is an artifact for
review, not an automatically installed replacement model.
