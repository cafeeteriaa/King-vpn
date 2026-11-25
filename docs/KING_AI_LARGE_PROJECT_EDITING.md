# KING AI — Large-project editing

## Purpose

The owner-authorized coding pipeline must not impose arbitrary project-wide quotas on
file count, aggregate source bytes, generated file count, or prompt length. Large
changes are represented as one coherent change set and one review-only pull request.

## Changes in this revision

- Repository discovery no longer truncates candidates to 40 files or selected paths to 6.
- Repository inventory walks Git trees iteratively, one directory at a time, rather than using GitHub's truncating recursive-tree response. If a single directory response is itself truncated, the scan fails visibly instead of returning an incomplete inventory.
- Repository source reads no longer reject files at 16 KB, 4 KB, or an aggregate 7.5 KB.
- Proposal generation no longer rejects more than 6 source files or more than 3 changed files.
- Documentation under `docs/` and root-level Markdown files can be included in project context; native VPN/service code, owner/security policy, CI, and dependency manifests remain protected.
- Owner-requested feature proposals and CI repair changes have no two-file quota. The separate autonomous background maintenance audit intentionally retains its two-file safety boundary and review-only behavior.
- Pull-request creation accepts the complete validated change map.
- Owner task descriptions have no fixed character ceiling; they are passed intact. If the task plus a source batch exceeds the actual model context, inference must fail visibly rather than truncate the request.
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

## Resumable multi-stage repair

- Every successfully validated inference batch is checkpointed in the app-private support directory.
- The checkpoint includes the exact task hash, a canonical source-snapshot hash, completed batch index, validated file changes, pending large-file patch operations, and summaries.
- Writes use a flushed temporary file followed by an atomic rename; an incomplete temporary write is not treated as a checkpoint. On resume, every restored path is revalidated against the current owner-editable inventory, secret scanning is rerun, and patch operations are structurally validated before they are trusted.
- Resume is automatic only for the same task and byte-identical source snapshot. An explicit checkpoint identifier that does not match the current task/source is rejected. Corrupt or stale checkpoints fail visibly.
- Checkpoint listing and deletion require an active owner session. Completed repairs remove their checkpoint.

## Cross-file dependency planning

Before model generation, the supplied Dart/Python inventory is analyzed for relative and project-package imports, unresolved project references, and import cycles. Each inference batch receives a scoped graph slice containing its files' outgoing references, unresolved project imports, and relevant cycles. Cross-batch targets remain visible as path references without duplicating the full repository graph in every prompt. SDK and external package imports are distinguished from unresolved in-project paths. This is a static source graph, not a claim of full semantic/type analysis.

## Owner ZIP project import

- Owner-authenticated ZIP imports are extracted into a new app-private workspace.
- The importer supports stored and DEFLATE entries using Dart SDK streams; it verifies declared expanded size and CRC32 before accepting a file.
- Absolute paths, drive paths, `..` traversal, normalized duplicates, symbolic links, encrypted entries, unsupported compression methods, multi-disk archives, invalid local/central metadata, and suspicious expansion ratios are rejected.
- There is no fixed file-count or total expanded-byte quota. Extraction is streamed; actual storage failures stop the import and the incomplete workspace is deleted rather than reported as complete.
- ZIP64 end records and ZIP64 entry sizes/offsets are supported within the platform's signed-integer range. Multi-disk archives remain explicitly unsupported. The owner-only `importProjectZip` API accepts a selected local `File`; a native file-picker UI is not wired into the screen yet.
