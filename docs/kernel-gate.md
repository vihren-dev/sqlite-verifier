# Trusted kernel gate

Build with `lake build migration-proof-checker`. The parent driver calls:

```sh
LEAN_SYSROOT=/absolute/pinned/lean \
  .lake/build/bin/migration-proof-checker \
  /absolute/library /absolute/trusted-stage /absolute/candidate-stage
```

All four paths must be existing absolute directories. The driver supplies the
pinned Lean 4.33.0 installation, controls the environment, and seals the library
and approved stage before compiling candidate files. The gate ignores `LEAN_PATH`.
It searches the pinned Lean standard library, packaged `SqliteVerifier` library,
approved stage, then candidate stage, in that order.

The trusted stage contains approved `Requirements` and `Interpretation` modules
and their approved dependencies. Separately generated `SqlInputs.lean` imports
only the pinned library and defines `Generated.startSchema`, `Generated.nextSchema`,
and `Generated.script`. The frontend's parsing and literal generation belong to
the trusted boundary. Candidate `NextInterpretation`, `Generated`, and `Proofs`
modules never become approved by being compiled or copied into a sealed directory.

The gate imports only declaration data, with no plugins, extension loading, or
candidate initializer execution. It compares complete declaration records on all
name collisions, including bodies, safety flags, constructor/recursor fields and
universe parameters; Lean expression comparison uses alpha equivalence. It
kernel-replays approved-stage additions against the pinned library, then candidate
additions against that result. Lookup uses the kernel environment so replayed
constants cannot disappear behind elaborator visibility maps.

The expected proposition is constructed directly as
`SqliteVerifier.VerificationConditions`, applied to `Requirements.LogicalState`,
the three protected SQL constants, `Interpretation.admitted`,
`Requirements.contract`, `Interpretation.current`, `NextInterpretation.next`, and
`NextInterpretation.failures`. The logical state's concrete universe is inferred
by the kernel. Input constants and `Proofs.migrationCorrect` must be closed,
without uninstantiated universe parameters. The candidate's `Generated.expected`
is an authoring convenience and is never the gate's acceptance target.

The proof's actual body and the expected target's dependencies are traversed
without imported axiom caches. Relevant unsafe/partial declarations, `sorryAx`,
and all axioms except `propext`, `Classical.choice`, and `Quot.sound` are rejected.
The kernel checks the proof body and checks its inferred type is definitionally
equal to the reconstructed proposition. Exit zero means these checks succeeded;
no printed sentinel or compiler exit status substitutes for them.

Run `python3 tests/kernel_gate_test.py` after building the formal library and
checker. `KERNEL_GATE_LIBRARY` can select an immutable library build for component
testing. Compiler/checker subprocesses have 30-second limits. Tests include an
actual empty-script model proof, wrong and unfinished proofs, transitive axioms,
protected declaration substitutions, unsafe proofs, a forged kernel body, a
forged expected alias, and a harmless initializer marker that must not execute.
The fixture is a gate regression, not a SQL frontend acceptance or pilot example.

The parent driver owns time/resource limits, compilation sandboxing, source
approval, artifact sealing and the complete verifier result. This component does
not establish parsing fidelity, SQLite conformance, or a complete Step 1 product.
