# Proof exporter execution evidence

The [Darwin receipt](darwin.json) and [Linux receipt](linux.json) record actual
native builds and acceptance of the repository-owned proof exporter under
Lean 4.34.1. Both platforms use unpatched lean4export at
`076e8e57707e813375e8f9da8bf989799ace9680`.
Implementation: `79e844a5`; docstring correction: `5a18b5bf`.

All three original T03 input sets produce the exact retained patched-producer
bundle lengths and SHA-256 digests. Their statuses remain `VERIFIED`,
`VIOLATED` and `VERIFIED`. The tests verify the input digests before comparing
the produced bytes. The example sources have no changes from T03.
These comparisons are a fixed-input checkpoint. Later planned changes to proof
inputs or model ownership must identify their new inputs and expectations;
the original T03 receipts remain immutable.

Both platforms pass actual preparation and kernel verification of a used
caller-owned declaration in `SqliteVerifier.Candidate`. A separate native Lean
test checks that a candidate artifact cannot replace a trusted definition in
a split package. The exporter also omits transitive trusted declarations in an
unrelated namespace while exporting a caller declaration in a trusted-looking
namespace. These checks use actual compilation and the shipped executable.
The algorithm selects declaration origins and import closure across ordered
roots, including roots supplied by separate packages.

| Native check | Darwin | Linux |
| --- | ---: | ---: |
| Source JUnit cases, including subtests | 353, no skips | 353, two existing optional reviewer-CLI skips |
| Atuin / bundle / CLI / kernel / sample / upstream Nix suites | 12 / 42 / 13 / 19 / 12 / 58 | 12 / 42 / 13 / 19 / 12 / 58 |
| Nix input, isolation and staging checks | 72 selected checks | 68 `just test-nix` checks |
| Actual offline-installed acceptance | 30, including exporter cases | 21 original cases plus 9 exporter cases |

Every listed check has zero failures and errors. All exporter-specific and
Nix suites have zero skips. Linux's two source skips are the existing checks
for optional installed `codex` and `claude` CLIs. Independent reviews ran on
the authoring host, where those tools are installed.

The original XML bytes are retained in [Darwin JUnit](darwin-junit.json.gz) and
[Linux JUnit](linux-junit.json.gz). Each gzip file contains a JSON map to the
original UTF-8 XML. The receipts bind its compressed and uncompressed digests,
each original XML digest, exact counts and source/runtime identities.
Darwin's docstring-only correction rebuilt successfully; all three runtime
executable digests remained identical.

Linux ran on the reserved idle `vihren` host in a fresh task directory.
The [snapshot](linux-snapshot.json) binds the public tracked source archive and
the [executed helper](linux-driver.sh). Both hashes passed before extraction.
The [source check](linux-source-unchanged.json) confirms that all 823 tracked
source files still match after validation. The prior T03 and T04b directories
were preserved. The driver completed with exit code 0 and released host compute.
The receipts retain the actual offline archive and executable digests.

The helper is retained exactly as executed, including its byte hash. Test
deadlines are unchanged. No exporter performance comparison is claimed.

Claude review of `79e844a5` reported the required final owner-review gates and
one docstring recommendation. The recommendation is fixed; correction
`5a18b5bf` passed review with no findings. The
[owner packet](../../plans/20261006-proof-exporter-owner-review.md) remains
pending before publication, merge or release.
