# Original-root case correction

The first independent review requires owner review of the trusted/caller
package-selection change. Finding `20261008T103804Z-a630a4fb#1` is deferred
to the owner's requested final integrated PR #56 review. The branch remains
gated for that review.

The reviewer also noted that probing only the workspace could miss a
case-insensitive original root on a different filesystem. The helper now
probes the original root directories, groups equivalent package names,
and exposes their original spellings in the merged view. For each artifact,
it selects the first original root in which that name resolves. The merged
view keeps first-root precedence. Original artifacts remain unchanged.

A fresh immutable macOS runtime containing this correction passes all 18
affected documentation, import-path, real compiler and exporter checks.
The differently cased caller passes actual preparation, export and kernel
replay. Original logs and XML are retained. The test command has a 600-second
outer limit. This host's native test does not cover a mixture of filesystem
case modes; no such native validation is claimed.

`source.json` binds the helper and runtime. `sha256.json` binds these original
receipts. The parent directory retains the first implementation's checks;
they remain bound to that earlier helper. Full integrated acceptance and
final owner review remain pending.
