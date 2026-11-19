# King AI continuous maintenance

King's maintenance lifecycle is continuous in intent, but bounded by Android
background scheduling, device resources and explicit owner security.

## Currently scheduled background work

- A best-effort WorkManager job researches official Android, Flutter, Dart,
  protocol and network-measurement documentation every six hours when network
  and battery constraints permit.
- Research is limited to an explicit HTTPS host allowlist, short excerpts and a
  bounded local history. Retrieved text is untrusted reference material, never
  executable instructions.
- This worker currently performs research only. It does not read source files,
  create code candidates, change runtime settings, or install application
  updates. The policy engine below defines the gates for those future actions;
  it is not itself an executor.

## Evidence and safe optimization gates

- Reversible runtime tuning requires at least four network samples, four
  connection samples and a rollback snapshot. Domestic and global evidence
  must both be present.
- A code candidate is eligible only after a reproducible issue is supported by
  at least eight network and connection samples. A candidate is not an applied
  change.
- Applying source changes requires an authenticated owner session, an explicit
  owner command scoped to that exact candidate, and passing CI.
- Dependencies, native VPN services, owner-security policy and releases remain
  separately protected. Publishing a release also requires separate owner
  release authorization and release validation.
- The in-app owner feature-request workflow and the background research worker
  are separate. Background research must never imply that a code change was
  owner-approved.

## Owner idea workflow

When the owner submits an idea, King should analyze feasibility, security,
network impact, testability and rollback cost first. It should explain the
recommendation in Persian and prepare a review candidate only after owner
authentication. An explicit, scoped authorization is required before applying
the candidate. Ordinary users remain limited to allowlisted connection and
troubleshooting commands.

## Limits

Android may defer WorkManager jobs for Doze, battery, network, OEM restrictions
or user force-stop; six hours is a requested cadence, not an exact execution
guarantee. Research updates the local technical knowledge base, not the model
weights. A successful probe on one carrier or device does not characterize all
Iranian networks. If evidence is incomplete, the safe action is to observe and
explain what is missing rather than guess.
