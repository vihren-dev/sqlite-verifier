# v0.1.0 — Verified SQLite schema extensions

Initial stable release of the owner-accepted Step 1 product.

The offline CLI checks exact SQL and Lean inputs for supported ordinary table
creation and restricted nullable-column additions. Profiles pin SQLite 3.51.0 or
3.46.0. Independent kernel replay, dependency checks and protected approved-input
baselines distinguish verified contracts from compilation alone. Unsupported
semantics fail explicitly; a rejected proof is not a demonstrated violation.

The source-backed Atuin case study proves preservation of approved old business
histories through the upstream shell-column addition. The same protected model
also accepts a different nullable added column: requirements do not anticipate
new fields or prescribe a target schema. The guarantee is successful modeled
execution and complete recovery of old information for every admitted database,
under the documented decoder and execution assumptions. It does not certify
SQLx, new features, application queries or SQLite's native implementation.
Synthetic examples additionally demonstrate reusable schema requirements,
checked negative theorems and explicit permitted-failure contracts.

The owner accepted Step 1's current state on 2026-09-25. The
[acceptance review](https://github.com/vihren-dev/sqlite-verifier/blob/v0.1.0/docs/atuin-pilot-review.md) separates human business-model guidance
and approval from agent-executed checks. Human effort comparisons remain
unmeasured; no productivity improvement is claimed.

Native archives target Apple Silicon macOS and x86_64 Linux, with a pinned Lean
runtime and offline Nix cache. Nix is an installation prerequisite; follow the
archive README and [installation guide](https://github.com/vihren-dev/sqlite-verifier/blob/v0.1.0/docs/install.md). Publication requires both
platform checks and extracted-installation tests. See the
[semantic subset](https://github.com/vihren-dev/sqlite-verifier/blob/v0.1.0/docs/semantic-subset.md), [execution profile](https://github.com/vihren-dev/sqlite-verifier/blob/v0.1.0/docs/execution-profile.md)
and [trust boundary](https://github.com/vihren-dev/sqlite-verifier/blob/v0.1.0/docs/trust-boundary.md) for the precise supported scope.
