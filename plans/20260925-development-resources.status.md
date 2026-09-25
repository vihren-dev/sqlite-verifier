# Development resource repair status

Created: 2026-09-25. Status: IN PROGRESS.
Task: [required outcomes](20260925-development-resources.task.md).

The owner requested repair of the supplied process report. Initial evidence
showed only 916 MiB free and the root flake invoked from changing non-Git
workspaces. Earlier inventory identified 96 unreferenced project snapshots,
43.17 GiB in total. This team has not deleted caches; future cleanup requires
explicit scoped approval.

Existing checked Atuin integration is root `9c22065b`. Uncommitted Atuin proof,
conformance, CLI tests and documentation remain preserved in their workspaces.
Resource repair is authorized; expensive Atuin builds remain paused.

Assignments: integration engineer fixes environment boundary/resource ownership;
conformance engineer fixes incremental parser compilation; coordinator handles
CI routing and duplicate aggregate evidence; Ultra lead independently reviews
the environment and final integration. No new orchestration system is planned.

An external state change restored about 50 GiB free; this team performed no
deletion. New lightweight CI routing/documentation tests (4) and coverage tests
(6) pass. Coverage now consumes each complete test wrapper's fresh JSON, retaining
provenance and negative-proof checks; stale report files cannot substitute for
fresh comparisons. Shared recipes now route those comparisons through coverage.
Integrated independently accepted environment unit `eb6b728e`: exact 3264-byte
source identity remains unchanged in real Git-parent and non-Git tests; three
resource checks pass, lock bytes are preserved, and the capture environment and
shared command dry-run pass. CI retains
required platform names and baseline security, selects docs/check/package scopes
and preserves tag/manual runs from ordinary cancellation. Final integration and
hosted verification remain pending; no completion claim is made. Pinned actionlint
and shellcheck pass. Independent lead review corrected the Markdown fast path
to match the scanner and confirmed preflight before Nix, release concurrency and
the unchanged target-owned baseline workflow.

The merged one-shell batch passed fresh native/model coverage (all comparisons
and named proof checks), seven routing/resource tests and six coverage tests.
Workflow lint passed on the merged source. The actual shared-command dry-run has
one parser build, one coverage collector and no duplicate parser/native/model
comparison commands or nested `nix develop`. Root comparison output is retained
at `build/resources-coverage.json`; the command trace is
`build/resources-check-dry-run.txt`. Incremental parser and full package/hosted
checks remain pending before the repair is complete.

Repair-only integration is based on public `e094a5ff`, applying reviewed units
`eb6b728e`, `d10e7eb3` and `215e06c5`. Backport conflict resolution retains the
public test inventory and excludes unfinished Atuin payload/model files. The
former separate CI capture step is included once in the shared check instead.
Protected example sources/manifests and the target-owned baseline workflow are
unchanged. The five incremental parser tests are part of the shared recipe;
the author and Ultra reviewer observed fresh-shell cache hits on macOS.
Full repair-only `just package` passed on aarch64-darwin, including the complete
verifier checks, archive creation and offline installed positive/refuted/unsupported
checks (`build/resources-package-1.log`, exit 0). After packaging, the real Nix
regression still reports the same 3264-byte source for both fixture types. Both
native parser outputs were reused without any compiler or generator calls; this
check now runs in the shared recipe on each platform. All five invalidation tests
and authored documentation checks pass. Both hosted platforms remain pending.

## Linux native-cache correction (2026-09-25)

Hosted Linux reached the real no-tool reuse gate after coverage, tiny snapshot
identity and five fake-tool tests passed; reuse invoked a compiler unexpectedly.
A bounded two-file pinned-environment diagnostic on existing vihren reproduced
Linux's declared `NIX_LDFLAGS`: `-rpath $out/lib`, with out under the shell's
workspace outputs/ directory. The directory is absent and not a symlink;
NIX_ENFORCE_PURITY is unset. The earlier purity hypothesis is rejected.

The correction admits only paired `-rpath` for exact absolute `$out/lib` while
absent, binds `out` in the fingerprint, and checks post-build reusability as well
as the hash before recording success. Creating that directory or a dangling
symlink disables reuse. Mutable -L, -rpath-link, include/SDK paths and unknown
flags still disable caching; the purity guard remains unchanged. The RPATH
exception is not generalized because existing paths can supply indirect linker
inputs. Seven focused tests pass, including appearance during compilation.

Automatic approval review rejected a proposed parser-source/test transfer to
vihren because that specific payload lacked export authorization. No transfer
was retried or bypassed. Root directs native confirmation through the already
authorized hosted PR workflow. Local tiny-environment validation passed: seven focused tests (0.145s), both
real parser builds, tool-free native reuse and both 20-script grammar suites with
malformed/limit/span checks. Ultra review additionally required strict paired include/link operands and
rejection of RPATH lists or loader-variable expansion; these are implemented with
regressions. Final pinned rerun passes seven tests (0.150s), both real builds and
tool-free reuse. Ultra independently accepted the final source and reproduced all seven tests
in 0.155s. Linux acceptance remains pending its unchanged hosted no-tool reuse
gate. No
full package rerun was started locally.
