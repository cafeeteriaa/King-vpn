# KING AI — Large-project editing

## Purpose

The owner-authorized coding pipeline must not impose arbitrary project-wide quotas on
file count, aggregate source bytes, generated file count, or prompt length. Large
changes are represented as one coherent change set and one review-only pull request.

## Changes in this revision

- Repository discovery no longer truncates candidates to 40 files or selected paths to 6.
- Repository source reads no longer reject files at 16 KB, 4 KB, or an aggregate 7.5 KB.
- Proposal generation no longer rejects more than 6 source files or more than 3 changed files.
- Pull-request creation accepts the complete validated change map.
- Source prompts are no longer silently truncated at 18 KB; incomplete context must not
  be passed off as complete context.
- The owner-authenticated coding engine may update its own implementation. Owner
  authentication, GitHub owner identity, path validation, and secret rejection remain.

## Boundaries that are not arbitrary product quotas

The local inference engine still has finite context, memory, and output-token capacity.
GitHub also imposes API, blob, tree, and request-size limits. Removing application-level
quotas does not make those physical/provider limits infinite. Large tasks must fail
visibly rather than silently discard source context. A later staged/chunked inference
pipeline is required for files that exceed the loaded model's actual context window or
its practical complete-file generation capacity.

## Safety and delivery

- Changes remain limited to validated source roots and explicitly supplied source paths.
- Secrets are rejected before commit creation.
- The authenticated GitHub account must match the official repository owner.
- Changes are written to a new branch and a draft pull request, never directly to main.
- No merge, release, or production deployment is performed by this workflow.
- Exact-head source guards, unit tests, analyzer, build, and review remain required.
