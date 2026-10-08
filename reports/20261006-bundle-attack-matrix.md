# Bundle checker attack parity

This record is for reviewers. `tests/kernel_gate_test.py` and
`tests/bundle_attack_test.py` select the same 12 proof-attack cases from
`tests/kernel_attack_cases.py`. Each case receives a private copy of the same
compiled protected fixtures. A test selection does not change another case.

| Existing kernel case | Bundle test or boundary | Direct checker exit |
| --- | --- | --- |
| `test_missing_sysroot` | `test_missing_sysroot`: remove `LEAN_SYSROOT` | 1 |
| `test_relative_library_path` | `test_relative_library_path`: library `.` | 1 |
| `test_proof_attack[valid]` | Actual pinned export of the honest proof | 0 |
| `test_proof_attack[initializer_ignored]` | Actual pinned export; checker output must not contain initializer marker | 0 |
| `test_proof_attack[forged_kernel_body]` | Honest target with handcrafted `True.intro` body; kernel replay rejects it | 1 |
| `test_proof_attack[wrong_theorem]` | Actual pinned export of theorem `True` | 1 |
| `test_proof_attack[sorry]` | Actual pinned export; audit identifies `sorryAx` | 1 |
| `test_proof_attack[transitive_axiom]` | Actual pinned export; audit identifies transitive `forbidden` axiom | 1 |
| `test_proof_attack[changed_protected_contract]` | Handcrafted changed `Requirements.contract` record | 1 |
| `test_proof_attack[changed_protected_SQL]` | Handcrafted changed `Generated.script` record | 1 |
| `test_proof_attack[changed_protected_schema]` | Handcrafted changed `Generated.startSchema` record | 1 |
| `test_proof_attack[changed_protected_profile]` | Handcrafted changed `Generated.profile` record | 1 |
| `test_proof_attack[unsafe_proof]` | Honest target/body with an explicit unsafe definition record | 1 |
| `test_proof_attack[partial_proof]` | Honest target/body with an explicit partial definition record | 1 |
| `test_approved_source_substitutes_schema` | Same approved-source mutation; bundle compiled before mutation | 1 |
| `test_forged_convenience_target` | Same candidate `Generated.expected := True`, actual pinned export | 1 |
| `test_changed_sealed_profile` | Compiled-`SqlInputs` substitution does not apply directly; changed exported profile test described below | 1 |
| `test_checked_refutation` | `test_refutation[checked_refutation]`: actual pinned negative export | 2 |
| `test_unfinished_refutation` | `test_refutation[unfinished_refutation]`: actual pinned negative `sorry` export | 1 |

The old changed-profile case changes trusted `SqlInputs` to `sqlite346`, then
removes the profile argument from the convenience target. That target uses the
default `sqlite351`. The old checker reconstructs its target from the compiled
`SqlInputs` and rejects the mismatch. The bundle checker does not compile that
module: it constructs the profile from the frontend's structural request. For
the real `sqlite351` request, the old candidate's default target is correct and
its unused `sqlite346` declaration need not be exported. The compiled-module
substitution is therefore specific to the old boundary. The applicable bundle
attack submits `Generated.profile` with its genuine execution-profile type and
the `sqlite346` constructor against the actual `sqlite351` request; the checker
rejects the changed protected record by name.

Unsafe/partial records are handwritten because export can omit those constants.
Protected records are handwritten because preparation imports the protected
definitions before compiling the candidate. The forged body is handwritten so
its valid NDJSON reaches kernel replay without relying on `debug.skipKernelTC`
or export behavior. The pinned parser at lean4export commit
`076e8e57707e813375e8f9da8bf989799ace9680` supports these definition safety flags.
All original export records and hostile bytes remain in each test's directory.

Four additional handwritten header cases cover a missing version, another
version, an invalid imports type and an attempt to import candidate `Proofs` as
a trusted module. That last module exists in the private candidate directory,
but trusted header imports resolve only from the sysroot and verifier library.
All four are rejected with exit 1. Preparation still executes Lean source; the
checker test does not claim that preparation is sandboxed.

On the cached reviewed T02 Darwin runtime, all 23 bundle cases passed in
29.08 seconds with a 150-second suite bound. The 19 unchanged old cases passed
in 31.96 seconds with a 120-second bound. Child compiles/exports have 30-second
bounds; checker calls have 60-second bounds. These are security/acceptance tests,
not performance trials. Both existing public CLI paths retain `VIOLATED`/1 for
a checked refutation; direct checker exit 2 remains distinct.
