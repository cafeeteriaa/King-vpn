# King AI continuous maintenance

King's maintenance loop is designed to make steady progress without bypassing
Android resource limits or owner security.

## Automatic read-only research

- On app startup, WorkManager schedules an immediate best-effort research pass
  and a periodic pass every six hours, subject to network and battery constraints.
- Research uses a strict HTTPS allowlist, stores bounded excerpts locally, and
  treats retrieved pages as untrusted reference material rather than commands.
- Research updates the local knowledge memory; it does not retrain or replace
  the installed model weights.

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
  published or silently installed. Owner review and green CI remain required.
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
