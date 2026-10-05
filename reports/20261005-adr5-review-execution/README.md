# V5 platform execution evidence

These receipts record actual execution against public source commit
`fe116b8744c7825529ec8eee21c33f15684a0694` and the unchanged v5 corpus.
[Byte inventory](sha256.json) binds the retained helper, source snapshot and
receipts; each successful receipt also binds its report and verifies unchanged
source, runtime, native libraries and input identities before and after execution.

The macOS ARM64 routes passed:

- [Full native replay](darwin/native.json): all 4,376 cases, 128.27 seconds.
- [Development sample](darwin/sample.json): 184 cases, 37.21 seconds for fresh
  loading, native replay and classification, within the unchanged 60-second bound.
- [Full progress](darwin/progress.json): 4,376 MODEL_UNSUPPORTED, zero disagreements
  or harness errors, and all 3,500 requirement rows retained.

The [Darwin helper](darwin/validate.py) retains the executed commands and checks;
the [source snapshot](darwin/snapshot.json) retains the 722 tracked file digests.
The linked reports remain in the parent reports directory.

The first [Linux full-native receipt](linux-native-420-timeout/native.json)
records exit 124 after 420.16 seconds, with no completed success report.
[Post-timeout bindings](linux-native-420-timeout/post-timeout-source-check.json)
confirm unchanged inputs. This is an incomplete measurement, not a disagreement
or a passing native gate. Later attempts must retain separate receipts.

The [second Linux full-native attempt](linux-native-900-timeout/native-900.json)
also times out: exit 124 after 900.17 seconds, with unchanged before/after
bindings and no completed native success report. A dropped SSH connection was
recovered to inspect this actual receipt; no duplicate replay was started.

The [Linux development sample](linux-sample/sample-independent.json) also passes
with the same 184 selected identities, measuring 56.58 seconds within its
unchanged 60-second phase deadline. The completed
[isolated model verification](model/verification.json) records 322 passed tests
and one expected Tcl-capture skip in 350.278 seconds. All 446 source/input
bindings remain unchanged; the separate upstream target owns the skipped check.

The [current isolated upstream target](upstream/verification.json) passes all
58 checks, including the model suite's omitted Tcl capture check. The
[final source-owned host check](source/verification.json) passes 286 tests plus
28 subtests in 37.911 seconds with unchanged source/document/runtime bindings.
The [first source attempt](source-first-failed/20261005-final-source-v5.verification.json)
is retained as a failed setup attempt: the selected conformance runtime lacked
example fixtures, and the sandbox prevented a process-group test. Selecting the
existing full runtime and an approved execution retry resolved those restrictions.

The successful [Linux full-native receipt](linux-native-tmpfs/native-tmpfs-420.json)
records all 4,376 cases passing in 98.13 seconds under the original 420-second
bound. SQLite still uses ordinary file-backed databases with the same profiles,
SQL, connection setup and native libraries; `TMPDIR` places their files on tmpfs.
Every native temporary-directory path is audited beneath that declared root.
This proves replay fidelity on tmpfs; the retained ext4 timeouts do not establish
disk replay performance or crash durability, which is outside this ADR's scope.

The [paired filesystem diagnostic](linux-filesystem-diagnostic/receipt.json)
retains three deterministic case inputs and all six fresh outputs. All native
observations match across ext4 and tmpfs and match the frozen observations.
The longest selected trigger prefix takes 10.72 seconds on ext4 and 0.10 seconds
on tmpfs. The [executed Linux helpers and source snapshot](linux-helpers/)
bind the unchanged executable sources; no loader or recording optimization was
adopted. The ordinary Linux development sample above still passes on ext4.

[Linux full progress](linux-progress/progress-independent.json) completes in
37.71 seconds: 4,376 MODEL_UNSUPPORTED, no disagreements or harness errors,
with all 3,500 requirement rows. Its cases and coverage views match macOS.

The [final Nix checks](nix/verification.json) pass all 68 configured requires_nix
tests in 95.266 seconds, including 28 input/dependency checks. All 450 relevant
code/input bindings and checked runtime hashes remain unchanged. Original
command paths are retained in summaries; copied logs, JUnit and before/after
inventories are bound by the byte inventory here.

External workload baseline closure remains pending. These observations do not
extend the semantic model.
