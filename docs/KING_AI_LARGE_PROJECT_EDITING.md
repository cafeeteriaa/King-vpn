# KING AI — Large-project editing

## Purpose

The owner-authorized coding pipeline must not impose arbitrary project-wide quotas on
file count, aggregate source bytes, generated file count, or prompt length. Large
changes are represented as one coherent change set and one review-only pull request.

## Changes in this revision

- Repository discovery no longer truncates candidates to 40 files or selected paths to 6.
- Repository source reads no longer reject files at 16 KB, 4 KB, or an aggregate 7.5 KB.
- Proposal generation no longer rejects more than 6 source files or more than 3 changed files. The autonomous maintenance proposal also no longer imposes its former two-file ceiling.
- Documentation under `docs/` and root-level Markdown files can be included in project context; native VPN/service code, owner/security policy, CI, and dependency manifests remain protected.
- Pull-request creation accepts the complete validated change map.
- Source prompts are no longer silently truncated at 18 KB; incomplete context must not
  be passed off as complete context.
- The owner-authenticated coding engine may update its own implementation. Owner
  authentication, GitHub owner identity, path validation, and secret rejection remain.

## Boundaries that are not arbitrary product quotas

The local inference engine still has finite context, memory, and output-token capacity.
Project-wide input is now divided into sequential inference batches (targeting about
9,000 source characters per batch); this is an execution slice, not an inventory or
project-size ceiling. A single file larger than the target is split into lossless Unicode-safe source chunks and is never silently truncated. Each chunk carries the original file SHA-256 and its index/count. Large files must be changed with anchored operations against the original complete file; chunk operations are accumulated and applied once to that exact source. GitHub also imposes API, blob, tree, and request-size
limits. If one individual file exceeds the loaded model's actual context window or its
practical complete-file generation capacity, the operation must fail visibly; Patch-based output now supports SHA-256-anchored exact-text operations. Each anchor must match exactly once, operations are applied sequentially, and stale source hashes or ambiguous anchors fail visibly. This reduces output-token pressure and avoids regenerating unchanged sections. The number of chunks grows with file size; the 6,000-character chunk size and 9,000-character batch target are processing sizes, not project/file inventory ceilings.

## Safety and delivery

- Changes remain limited to validated source roots and explicitly supplied source paths.
- Secrets are rejected before commit creation.
- The authenticated GitHub account must match the official repository owner.
- Changes are written to a new branch and a draft pull request, never directly to main.
- No merge, release, or production deployment is performed by this workflow.
- Exact-head source guards, unit tests, analyzer, build, and review remain required.


## Large-file patch protocol

For a file too large to regenerate safely, the coding model may return a patch change
instead of a full replacement:

- `path` identifies a file included in the current authenticated source batch.
- `baseSha256` must match the SHA-256 of the exact original UTF-8 file.
- `operations` is an ordered list of exact `find`/`replace` pairs.
- Every `find` anchor must occur exactly once when its operation is applied.
- Each operation is applied to the result of the preceding operation; stale hashes,
  missing anchors, ambiguous anchors, malformed operations, and generated secrets fail.
- Full-file replacements remain supported for small files. A patch does not bypass
  owner authentication, path policy, secret checks, review, or CI.


## Lossless per-file chunking

- Each source file is hashed before chunking; chunks preserve the original Unicode text
  exactly when concatenated.
- Chunk metadata includes path, zero-based index, total count, and the full-source SHA-256.
- Large-file responses must be anchored operations, not partial-file replacements.
- Anchors must be present in the supplied chunk and unique in the original source when
  applied. All operations are collected and applied to the original file once.
- Empty, stale, ambiguous, out-of-chunk, and malformed patches fail closed.
