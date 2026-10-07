# Requested mutation correction and full model gates

The reviewed correction is `9e3b44193981bae46dc9fdeedc66eca3f255f419`.
It replaces a deleted docstring boundary with the primitive `def step` declaration
and the final `end SqliteVerifier` in `Execution.lean`. The transition must remain
the final declaration in that namespace. Production Lean, protected baselines
and every frozen corpus byte are unchanged by this correction.

The actual error-seeking generator and all four production mutants now pass:
five targeted cases on Darwin in 10.56 seconds and Linux in 18.85 seconds.
The four additional source cases establish independence from docstring changes
and rejection of missing code boundaries. Both documentation review findings
are fixed; the final required independent review has no findings.

Linux's complete Nix model gate passed at that exact reviewed source: 322 cases,
with one existing skip for the separate pinned Tcl upstream target, in 328.30
seconds. The successful output is
`/nix/store/azynb6qjm59j0xjqn4h07rdrkc6arlak-sqlite-verifier-test-model-1`.
All 881 tracked regular-file hashes and the instruction symlink were checked
before and after execution in `/var/tmp/sqlite-verifier-mutation.tql5Ir/source`.
The public source/archive and exact executed helper are bound in `linux-source.json`.
`linux.json` records actual runtime/output identities and both original XML hashes.

Darwin's complete gate failed at the preceding documentation checkpoint
`83edc417eea4ff74da8f67aebbc0d43a0fc7b1c6`. Its executable mutation-module AST
is identical to the final correction; the later change only names the code
boundaries in the docstring. The raw log ends during frozen-v5 partition validation
with `boost::bad_format_string: format-string is ill-formed`. It has 315 completed
pass progress lines and one existing skip, but no pytest summary or successful
JUnit receipt. These progress lines are not complete suite acceptance.
`darwin-failure.json` retains the source/derivation, failure and exact log hash.
Its 422.825-second interval is file creation through final write on the wall clock;
no monotonic process-start measurement was captured.

The initial runs retained the 420-second suite and 900-second outer bounds.
No case, denominator, full binding or protected-baseline check was removed.
Darwin dependent reruns stopped for the separately authorized Nix/timeout
diagnostic. The owner then authorized exactly one final-source validation using
the model-only 600-second recipe independently reviewed at
`7101799dd3043fa3d475ca94ffb3c321c0b4d327`.

That final Darwin validation passed 322 cases and the same existing skip in
484.74 seconds. The complete invocation took 487.2766 seconds on a monotonic
clock. All 32 ordered model test files and 318 selected immutable source files
match final source `9e3b4419`. Its output is
`/nix/store/m0l8bxww097w76m4c81k4g7gmdjp3kya-sqlite-verifier-test-model-1`.
`darwin-invocation.json` retains the exact install phase, file order and every
selected source hash; `darwin.json` binds the original XML and actual process.
The private override and timed caller are retained byte-for-byte.

This validates the full model natively on both hosts under the stated recipes.
PR48 still configures 420 seconds; the separate timeout-task source is not merged
into this branch. Its configured CI gate, protected-baseline gate and final R8
owner approval remain open, so T05 is not DONE. No release or issue closure occurs.

`raw-receipts.json.gz` contains the exact original log, XML and source-verification
text, with separate SHA-256 values. `sha256.json` binds the metadata, helper and
compressed raw payload. Prior T03/T02/T05 receipts and helper bytes are unchanged.
