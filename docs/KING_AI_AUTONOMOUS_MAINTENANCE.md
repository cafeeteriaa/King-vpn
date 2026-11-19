# King AI continuous maintenance

King's maintenance lifecycle is intentionally continuous but bounded by Android
background scheduling and device resources.

## Automatic work

- The app observes real domestic/global reachability and connection outcomes
  through its network diagnostics and endpoint history.
- A best-effort WorkManager job researches official Android, Flutter, Dart,
  protocol and network-measurement documentation every six hours when network
  and battery constraints permit.
- Research is limited to an explicit HTTPS host allowlist, short excerpts and a
  bounded local history. Retrieved text is untrusted reference material, never
  executable instructions.
- The local model may prepare an isolated source candidate only when a problem
  is reproducible and supported by at least eight domestic/global and
  connection samples. Candidate preparation does not modify the installed app.

## Gates

- Reversible runtime tuning requires at least four network samples, four
  connection samples and a rollback snapshot.
- Applying source changes requires an authenticated owner session and passing
  CI. Dependencies, native VPN services, owner-security policy and releases
  remain separately protected.
- Publishing a release additionally requires release validation.
- Background work is best-effort. Android may defer it for Doze, battery,
  network, OEM restrictions or user force-stop; it is not an always-on daemon.
- If evidence is incomplete, the safe action is to observe and explain what is
  missing rather than guessing or claiming the whole Iranian network was tested.

## Owner idea workflow

When the owner submits an idea, King should analyze feasibility, security,
network impact, testability and rollback cost first. It should explain the
recommendation in Persian and prepare a review candidate only after the owner
is authenticated. Ordinary users remain limited to the app's allowlisted
connection and troubleshooting commands.
