# Lean 4 mechanics for proving and running conformance tests against an executable model

Scope: kernel-checked evaluation of concrete test cases, fast compiled execution for bulk differential testing, and keeping the two consistent, for a Lean 4.33 (moving to 4.34.x) SQLite model with no Mathlib.

Method note: besides web sources, I read the Lean 4.33.0 and 4.34.1 toolchain sources installed locally (`~/.elan/toolchains/...`) and ran small benchmarks on this machine (Apple Silicon, `lean` on single files, Lean 4.34.1 unless stated). Those are labelled **[local experiment]**. They are small micro-benchmarks, not measurements of the real model. Source citations for toolchain files point at the matching path in the lean4 GitHub repo, and the tag matters.

## 1. What each proof-by-evaluation method trusts, and how it performs

### Takeaway
Keep `decide +kernel` (or `rfl`, which also goes through kernel defeq) as the only proof method for the "model passes test" theorems. It adds no axioms beyond what the model itself uses, and it reduces through well-founded recursion that the elaborator refuses to unfold. Since Lean 4.29, `native_decide` no longer uses `Lean.ofReduceBool`. It now adds one fresh auxiliary axiom per use, named like `thm._native.native_decide.ax_1_1`. That axiom is outside the product's allowed set and cannot be meaningfully replayed by Nanoda, so it is unusable for the proof suite. It is still a good fast pre-check.

### Cited Findings
- `decide` docstring (4.33): "`decide +kernel` uses kernel for reduction instead of the elaborator. It has two key properties: (1) since it uses the kernel, it ignores transparency and can unfold everything, and (2) it reduces the `Decidable` instance only once instead of twice." `decide +native` "uses the native code compiler (`#eval`) to evaluate the `Decidable` instance, admitting the result via an axiom… it depends on the correctness of the Lean compiler and all definitions with an `@[implemented_by]` attribute." — [lean4 src/Init/Tactics.lean @ v4.33.0](https://github.com/leanprover/lean4/blob/v4.33.0/src/Init/Tactics.lean)
- Documented limitation: "In the default mode or `+kernel` mode… `Decidable` instances defined by well-founded recursion might not work because evaluating them requires reducing proofs. Reduction can also get stuck on `Decidable` instances with `Eq.rec` terms. These can appear in instances defined using tactics (such as `rw` and `simp`). To avoid this, create such instances using definitions such as `decidable_of_iff` instead." — [same file](https://github.com/leanprover/lean4/blob/v4.33.0/src/Init/Tactics.lean)
- `+kernel` and `+native` cannot be combined (the tactic throws "Cannot simultaneously set both `+kernel` and `+native`"). — [lean4 src/Lean/Elab/Tactic/Decide.lean @ v4.33.0](https://github.com/leanprover/lean4/blob/v4.33.0/src/Lean/Elab/Tactic/Decide.lean)
- Lean 4.29.0 release notes: "native computation (`native_decide`, `bv_decide`) is represented in the logic as one axiom per computation, asserting the equality that was obtained from the native computation." — [Lean 4.29.0 release notes](https://lean-lang.org/doc/reference/latest/releases/v4.29.0/)
- In 4.33, `Lean.trustCompiler`, `Lean.reduceBool`, and `Lean.ofReduceBool` are all marked `@[deprecated "in-kernel native reduction is deprecated; assert native evaluations with axioms instead" (since := "2026-02-01")]`. The old docstring warns that using them means "you will probably not be able to check your development using external type checkers that do not implement this feature." — [lean4 src/Init/Core.lean @ v4.33.0](https://github.com/leanprover/lean4/blob/v4.33.0/src/Init/Core.lean)
- Implementation (`Lean.Meta.nativeEqTrue`): it compiles the closed `Bool` term as an auxiliary definition, runs it with `evalConst`, and if the result is `true` it adds an `axiomDecl` of type `e = true`. The module docstring says this is "the basis for `native_decide` and `bv_decide`". — [lean4 src/Lean/Meta/Native.lean @ v4.33.0](https://github.com/leanprover/lean4/blob/v4.33.0/src/Lean/Meta/Native.lean)
- **[local experiment, 4.34.1]** `theorem t1 : (List.range 1000).length = 1000 := by native_decide` followed by `#print axioms t1` gives `'t1' depends on axioms: [t1._native.native_decide.ax_1_1]`. A `decide +kernel` proof of a `List`/`Nat` fold depends on no axioms. A `String` equality proved by `decide +kernel` depends on `[propext]`.
- Nanoda-based trust chains that other projects run treat native_decide as unchecked. One project's plan says "native_decide theorems gain nothing here (Lean.trustCompiler is permitted-not-checked)". — [coproduct-opensource/nucleus issue #2605](https://github.com/coproduct-opensource/nucleus/issues/2605)
- The `decide` elaborator path special-cases unfolding of `Nat.decEq`, `String.decEq`, `List.hasDecEq`, `UInt8/16/32/64.decEq` and `.ofNat`, `Char.ofNat`, and `Fin.ofNat` so that it can reach constructors in match discriminants. — [lean4 src/Lean/Meta/WHNF.lean @ v4.33.0](https://github.com/leanprover/lean4/blob/v4.33.0/src/Lean/Meta/WHNF.lean)
- The 4.29 release also added a `cbv` (call-by-value) tactic and a `decide_cbv` finishing tactic that "applies `of_decide_eq_true` and then tries to discharge the remaining goal using `cbv`." — [Lean 4.29.0 release notes](https://lean-lang.org/doc/reference/latest/releases/v4.29.0/)
- **[local experiment, 4.34.1, wall time per single-file `lean` run with about 0.8 s baseline for an empty file]** Toy model: `Value` inductive with derived `DecidableEq`, tables as `List (List Value)`, database as `List (String × Table)`. Query: insert a row, then count rows where the first column is greater than k.
  - `decide +kernel` with 100 rows: about 0.01 s over baseline. 1000 rows: about 0.17 s. 5000 rows: about 1.2 s.
  - Same 1000-row query with plain `decide` (elaborator, then kernel re-check): about 0.48 s. With `rfl`: about 0.43 s. With `native_decide`: about 0.15 s.
  - Full structural equality of a 1001-row database (derived `DecidableEq`) with `decide +kernel`: about 1.3 s.
  - 500 small `decide +kernel` theorems in one file (20-row DB each): 7.6 s wall and about 840 MB max RSS. The same 500 checks as `#guard`: 2.3 s wall.

### Inferences
- The product policy allows only propext, Classical.choice, and Quot.sound. `native_decide` / `decide +native` / `bv_decide` fail that policy by construction, because each adds a fresh axiom. Use them only in non-proof pre-screens, e.g. a `#guard` or `#eval` harness. Add a CI check that fails if `#print axioms` output for any test theorem contains `_native`.
- `decide +kernel` is the right default because it avoids double evaluation and ignores `@[irreducible]`. Plain `decide` evaluates in `Meta.whnf` and then the kernel re-checks, so it pays about twice and also gets stuck on WF definitions. `rfl` on `evalCase c = expected` behaves similarly to `decide +kernel` in cost, but its failure messages are worse.
- Prefer stating each test as `checkCase c = true`, where `checkCase : Case → Bool` is computed with `==`/`BEq` or a hand-written `Bool` comparison, over a `Prop` equality of large structures. The `Decidable` instance is then trivial, and the kernel does the rest via `Bool` reduction. This form also matches `native_decide` and `#guard` exactly, so the kernel and compiled checks run the identical function.
- Beware `Decidable` instances built with tactics (`rw`/`simp` inside the instance). They leave `Eq.rec` terms that block reduction. Use `decidable_of_iff` or `Bool`-valued checks instead.

### Gaps
- I found no published per-test kernel cost numbers from Cedar, EVMYulLean, or LNSym, because none of them kernel-check their conformance suites (see section 5). The only numbers here are my micro-benchmarks.
- `cbv`/`decide_cbv` produce proofs that the kernel must still check. I did not measure whether they beat `decide +kernel` on this kind of workload.

## 2. Kernel-accelerated operations, and how to represent Value, Database, and REAL

### Takeaway
The kernel has GMP-backed `Nat` literals and fast paths for `Nat` add/sub/mul/div/mod/pow/gcd/beq/ble/land/lor/xor/shiftLeft/shiftRight. `Int`, `UInt64`, `Char`, and `String` reduce by unfolding to `Nat`/`BitVec`/`Fin`/`List` structures, so they are correct but cost more per operation. Kernel-friendly data structures are inductive lists and association lists. `Std.HashMap` gets stuck. `Std.TreeMap` works but is slower than association lists at the sizes tested. Since 4.3x, `Float` has a kernel-reducible bit-level model for + − × ÷, sqrt, comparisons, and int conversions. `Float.toString` and transcendental functions remain opaque.

### Cited Findings
- Reference manual on Nat: in the kernel there are "special `Nat` literal values that use a widely-trusted, efficient arbitrary-precision integer library (usually GMP)". Basic functions are "overridden in both the kernel and the compiler to efficiently evaluate using the arbitrary-precision arithmetic library". Also: "Using Lean's built-in arithmetic operators, rather than redefining them, is essential." — [Lean reference: Natural Numbers](https://lean-lang.org/doc/reference/latest/Basic-Types/Natural-Numbers/)
- The elaborator-side Nat fast paths (`reduceNat?`) are `Nat.succ, add, sub, mul, div, mod, pow, gcd, beq, ble, land, lor, xor, shiftLeft, shiftRight`. — [lean4 src/Lean/Meta/WHNF.lean @ v4.33.0](https://github.com/leanprover/lean4/blob/v4.33.0/src/Lean/Meta/WHNF.lean). The kernel's C++ list is similar, per the reference manual's list of add/sub/mul/div/mod/pow/beq/ble/decEq/gcd ([Natural Numbers](https://lean-lang.org/doc/reference/latest/Basic-Types/Natural-Numbers/)). I did not read the kernel C++ source.
- Lean 4.34.0 "bounds the size of `Nat` numerals the kernel computes at 128 MB". The same release fixed three kernel soundness issues found by adversarial testing, and redefined `Bool.and`, `Bool.or`, and `Bool.not` "using `Bool.rec` for faster kernel reduction". It also demoted `String.toList` "from implicit to semireducible". — [Lean 4.34.0 release notes](https://lean-lang.org/doc/reference/latest/releases/v4.34.0/)
- `String` is now `structure String where ofByteArray :: toByteArray : ByteArray; isValidUTF8 : …`. `String.decEq` matches through `ByteArray` down to the underlying list and compares that. — [lean4 src/Init/Prelude.lean @ v4.34.1](https://github.com/leanprover/lean4/blob/v4.34.1/src/Init/Prelude.lean)
- Kernel replay pitfall: "Lean kernel replay rejects any theorem whose proof reduces a string literal". A string literal is an atomic `Expr.lit (.strVal …)`, but reducing it needs `Char.ofNat`, `String.ofList`, and other helpers that `Lean.Replay` does not add when replaying into an empty environment. The failure shows as "unknown constant 'Char.ofNat'" in comparator on v4.34.0/v4.35.0-rc1. `lean4checker` and nanoda accept the same proofs. Status: open. — [leanprover/comparator issue #93](https://github.com/leanprover/comparator/issues/93)
- **[local experiment, 4.34.1]** `Std.HashMap String Nat` lookup with `decide +kernel` fails: "did not reduce to `isTrue` or `isFalse`", stuck in `match hm.get? "b"`. `Std.TreeMap` insert of 300 keys plus a lookup succeeds in about 1.3 s over baseline. The 1000-row association-list query in section 1 took about 0.17 s.
- Reference manual: "Functions marked `partial` are treated as opaque constants by the kernel and are neither unfolded nor reduced." WF-recursive functions "are frequently slow to compute with because they require reducing proof terms that are often very large." — [Lean reference: Recursive Definitions](https://lean-lang.org/doc/reference/latest/Definitions/Recursive-Definitions/)
- **[local experiment, 4.34.1]** WF definition `wfLen` (with `termination_by l.length`) on a 2000-element list:
  - `decide +kernel` succeeds in about 0.15 s. A structurally recursive version took about 0.6 s.
  - Plain `decide` on 200 elements fails: "reduction got stuck", because WF definitions are irreducible for the elaborator.
  - A WF `gcd` whose `decreasing_by` uses `omega` is proved by `decide +kernel`, with axioms `[propext, Quot.sound]` that come from the termination proof.
- **Float in 4.33.0 and 4.34.1** (toolchain source): "From the point of view of Lean's logic, `Float` is equivalent to `Float.Model`… which is itself a subtype of `UInt64`. Some of the operations on `Float` are defined in terms of their `Float.Model` counterparts, while others are opaque to Lean's kernel."
  - Model-backed (`def` with `@[extern]`): `add`, `sub`, `mul`, `div`, `neg`, `lt`, `le`, `beq`, `ofBits`, `toBits`, `toUInt8..64`, `isNaN`, `isFinite`, `isInf`, `UIntN.toFloat`, `sqrt`, `abs`.
  - Still `opaque`: `toString`, `frExp`, `sin`…`atanh`, `exp`, `log*`, `pow`, `cbrt`, `ceil`, `floor`, `round`, `scaleB`.
  - The model comment says "a `NaN` must be exactly a chosen canonical `NaN`".
  - Source: [lean4 src/Init/Data/Float/Float.lean @ v4.33.0](https://github.com/leanprover/lean4/blob/v4.33.0/src/Init/Data/Float/Float.lean) and [Float/Model/Float.lean](https://github.com/leanprover/lean4/blob/v4.33.0/src/Init/Data/Float/Model/Float.lean)
- **[local experiment, 4.33.0 and 4.34.1]** `((2.0 : Float) + 2.0 == 4.0) = true` and `(1.5 : Float).toBits = 0x3FF8000000000000` are both proved by `decide +kernel`, with axioms `[propext, Classical.choice, Quot.sound]`. A fold doing 200 `Float` additions and 200 divisions was proved by `decide +kernel` in about 5 s, which is roughly 10 ms per float operation.

### Inferences
- **Database representation:** replace `String → Option Table` with a first-order structure, e.g. `List (TableName × Table)` kept sorted, or in insertion order to match `sqlite_schema`. A function-typed database cannot be compared by `decide`, and it builds up nested closures that the kernel re-reduces on every lookup. Add a lookup function over the list and prove, once, lemmas that relate it to the old function view if needed. The kernel is fine with lists of about 10³–10⁴ rows. Avoid `Std.HashMap` in anything that must be kernel-evaluated. `Std.TreeMap` works but costs more than lists at test sizes (small tables).
- **Names:** `String` table/column names are fine for kernel `decide`. Two reasons to consider `List UInt8` (or an interned `Nat` id) for names in the kernel-checked path:
  1. Comparator's `Lean.Replay` currently fails on proofs that reduce string literals. lean4checker and nanoda are unaffected, so this matters mainly if the team also uses `comparator`.
  2. Kernel string comparison has to peel through `String → ByteArray → Array → List UInt8 → BitVec/Fin` layers.

  The model already stores TEXT as `List UInt8`, which is the kernel-friendly choice. Nanoda replay should be tested early on a theorem that reduces a string literal.
- **REAL:** keeping `real (bits : UInt64)` is right. In 4.33+ the model could use `Float.ofBits`/`Float.add`/etc. and get kernel-reducible IEEE arithmetic from core, at about 10 ms per operation in the kernel. Caveats:
  1. This ties the model's semantics to Lean's `Float.Model`, including its canonical-NaN convention. Compiled code uses hardware doubles via `@[extern]`, so NaN payloads and signs can differ between kernel and compiled runs. SQLite converts NaN results to NULL, so the model should normalise NaNs itself.
  2. SQLite's REAL→TEXT (`%!.15g`, with a round-trip check that falls back to 17 digits in newer SQLite) and TEXT→REAL (`sqlite3AtoF`) are not available as reducible functions (`Float.toString` is opaque and has a different format anyway). They must be written in Lean over `Nat`/`Int`, e.g. an exact decimal expansion with correct rounding using GMP-backed `Nat` arithmetic. GMP makes big-integer exact algorithms cheap in the kernel.
- **Integers:** `Int` arithmetic reduces via `Nat` fast paths plus constructor case splits, which is fine. 64-bit overflow checks (SQLite INTEGER overflows to REAL) should be done on `Int` with explicit bounds, not on `Int64`. The `Int64`/`UInt64` wrappers add `BitVec`/`Fin` unfolding layers.
- **Recursion:** WF definitions are not a blocker for `decide +kernel` in 4.34, but they are a blocker for plain `decide`, `simp`, and `rfl` at default transparency. Keep evaluators structurally recursive, or fuel-based with a `Nat` fuel argument, wherever practical. Never use `partial` in the model: it is opaque to the kernel, so the test theorems cannot go through it. If a compiled fast path is wanted, use `@[implemented_by]` or `@[csimp]` on a reducible reference definition, and remember that the kernel proof then exercises the reference definition, not the fast one.

### Gaps
- I did not confirm from the kernel C++ source exactly which `Nat`/`String` operations the kernel (not the elaborator) accelerates in 4.33/4.34. For example, whether `Nat.log2` or string-literal `String.decEq` has a kernel fast path.
- I found no release note pinpointing when `Float` became kernel-reducible. It is present in both 4.33.0 and 4.34.1 sources.
- I did not verify whether nanoda handles the `Float.Model` definitions efficiently.

## 3. Scaling to thousands of test theorems; which guarantee each option gives

### Takeaway
Per-theorem kernel cost for small SQL cases is tens of milliseconds, but each theorem also pays elaboration and memory overhead. My micro-benchmark measured about 14 ms wall per trivial theorem and 840 MB for 500 theorems in one file. Shard generated theorems into many modules of a few hundred each so that Lake builds them in parallel and caches them. Run the full generated corpus through the compiled model (`lake exe` / `#guard`), and kernel-prove a curated regression subset, or all of them in a slower nightly job. There is no sound way to get kernel-level assurance for compiled results short of a verified compiler.

### Cited Findings
- **[local experiment, 4.34.1]** 500 `decide +kernel` theorems in one file: 7.6 s wall (user 4.95 s, sys 13.8 s, which suggests heavy allocation or parallel-elaboration overhead), with about 840 MB max RSS. The same checks as `#guard` took 2.3 s.
- Lean 4.34.0 fixed an exponential blowup in `instantiateMVars` on proof terms: "One problematic case dropped from 41GB to 1.2 seconds." — [Lean 4.34.0 release notes](https://lean-lang.org/doc/reference/latest/releases/v4.34.0/)
- Lean 4.29.0: Lake now hard-links build artifacts from the local cache before falling back to copying. — [Lean 4.29.0 release notes](https://lean-lang.org/doc/reference/latest/releases/v4.29.0/)
- `native_decide` docstring: "because it is compiled, this can be significantly more efficient than using `decide`, and for very large computations this is one way to run external programs and trust the result." — [lean4 src/Init/Tactics.lean @ v4.33.0](https://github.com/leanprover/lean4/blob/v4.33.0/src/Init/Tactics.lean)
- The 4.34.1 toolchain ships a `leanchecker` binary alongside `lean`/`lake`. Run from this repo it tried to load oleans for `SqliteVerifier`, so it is the bundled lean4checker that re-checks compiled `.olean` environments. **[local observation]**

### Inferences
- **Layout:** put one generated module per SQL test file, or per shard of about 100–300 cases, all importing a single `Model` module. Lake builds modules in parallel and only rebuilds changed shards. Put the model in its own library so edits to the test generator don't invalidate it. Every change to the model does invalidate all test modules, which is the main recurring cost.
- **Case data as Lean terms:** emit each case's initial DB and statements as a separate `def` (or `abbrev`) and state the theorem as `checkCase caseN = true`. This keeps elaboration cheap: the terms are already in normal form and the kernel caches the unfolded `def`.
- **What each option guarantees:**
  - `decide +kernel` theorem per case: the kernel, and later Nanoda independently, checked that the *model definition* produces the expected observations. Trust is the kernel plus the three standard axioms.
  - Compiled `#guard` / `lake exe` over all cases: the *compiled code* produced the expected output. Trust adds the Lean compiler, the runtime, all `@[extern]`/`@[implemented_by]` substitutions, and for `Float` the C library. This is good evidence but not a proof about the model.
  - `native_decide`: the same trust as the compiled run, packaged as a per-theorem axiom. It gives no advantage over a `#guard` harness and violates the product policy.
  - "Prove once that `evalCompiled = evalSpec`": this only makes sense if the compiled path uses different Lean definitions (`@[implemented_by]`/`@[csimp]` fast versions). A `@[csimp]` lemma proves the fast Lean definition equals the reference one, but it still relies on the compiler to compile the fast one correctly. It closes the Lean-level gap between two definitions and leaves the compiler-trust gap open. Without a verified Lean compiler, no theorem makes compiled results kernel-grade.
- **Recommended tiering:**
  1. All generated cases (10³–10⁴ or more): run the compiled model via a `lake exe` harness, in seconds.
  2. A curated regression subset (hundreds to low thousands): `decide +kernel` theorems in sharded modules, built in CI.
  3. Optionally, the full kernel suite nightly, followed by Nanoda replay.

  Because kernel and compiled runs evaluate the same `Bool` function over the same case data, a disagreement between them flags an `@[extern]`/`implemented_by` inconsistency, e.g. in `Float` or `String` primitives.

### Gaps
- I found no published scaling figures such as "N thousand `decide` theorems take X minutes" from Cedar, LeanSAT/bv_decide, Aesop, or Verso. The per-theorem numbers above come only from my micro-benchmark.
- I did not measure Lake parallel speedup on sharded test modules, or Nanoda replay time on such proofs.

## 4. Differential-testing plumbing: FFI, JSON/protobuf, Plausible, and the Cedar template

### Takeaway
Cedar is the closest template. Its Lean model is compiled to a library and linked into Rust, inputs are serialized with Protobuf, cargo-fuzz generates millions of inputs per target, and the compiled Lean model ran faster than the Rust production code per call. For SQLite, the simplest path is a Lean `lake exe` that reads cases (JSON lines) from the Python harness, which also runs real SQLite. Direct `@[extern]` calls to libsqlite3 from Lean work but add C glue and add SQLite to the trusted build. Plausible is usable for Lean-side generic property tests, e.g. with derived `Arbitrary` for `Value`, but it is not a SQL-aware generator.

### Cited Findings
- Cedar DRT: "we randomly generate millions of inputs—access requests, entities, and policies—and send them to both the Lean model and the corresponding Rust production implementation". Each target is fuzzed with "4096 CPU units (4 vCPUs) and 8GB memory… for 6 hours". "During differential testing, the median execution time for the Lean authorizer is 6 microseconds, compared to 10 microseconds for Rust." The Lean code is 1,673 lines of spec and 5,714 lines of proofs. The team found 21 bugs: 4 during proofs and 17 through DRT and property-based testing. — [How We Built Cedar: A Verification-Guided Approach (arXiv 2407.01688)](https://arxiv.org/html/2407.01688)
- cedar-spec layout: `cedar-lean` (model and proofs), `cedar-drt` (fuzzing and DRT), and `cedar-policy-generators` (input generation with the Rust `arbitrary` crate). Tests run with `cargo fuzz run -s none <target>`. The build scripts are `source cedar-drt/set_env_vars.sh` and `cedar-drt/build_lean_lib.sh`. — [cedar-spec README](https://github.com/cedar-policy/cedar-spec/blob/main/README.md). A minimised corpus from cargo-fuzz is kept for CI. — [cedar-spec](https://github.com/cedar-policy/cedar-spec)
- cedar-lean-ffi: "This FFI makes use of Cedar's Protobuf feature to convert Cedar types in Rust to the corresponding type within the Lean formalization". Linking needs the Lean shared library at runtime (errors like "libleanshared.so: cannot open shared object file" otherwise). — [cedar-spec/cedar-lean-ffi](https://github.com/cedar-policy/cedar-spec/tree/main/cedar-lean-ffi)
- Plausible, maintained by leanprover-community: supports `deriving Arbitrary` and `deriving instance Arbitrary for …`, custom `SampleableExt` generators, `Shrinkable` for shrinking, a `plausible` tactic, and `#eval Testable.check`. — [leanprover-community/plausible](https://github.com/leanprover-community/plausible)

### Inferences
- **Recommended harness:** Python generates cases (hypothesis/grammar fuzzers or SQLite's own test corpus) and runs real SQLite through the `sqlite3` module or the C API. It streams the same cases, already parsed to the model's AST, as JSON lines to a long-lived `lake exe model-runner` and compares observations. This avoids FFI build complexity, keeps the SQL parser in one place (Python), and lets the kernel-proved subset reuse the exact serialized cases. Cedar's numbers suggest the compiled Lean model will not be the bottleneck.
- **Use FFI only if** per-case process and JSON overhead matters, or for in-process fuzzing (libFuzzer). Two ways:
  - Lean `@[extern "c_fn"]` with a small C shim around `sqlite3_exec`.
  - Cedar's direction: export Lean functions with `@[export]` and call them from C/Rust/Python (ctypes), which requires `lean_initialize_runtime_module` and linking `libleanshared`.
- **Plausible's role:** use it for generic model properties on small random inputs (section 6), where no SQLite oracle is needed. It is not a replacement for SQL-level differential fuzzing.

### Gaps
- I did not verify cedar-lean-ffi's exact `@[export]` function signatures or its runtime-initialisation code.
- I found no current Lean library binding to sqlite3.
- Plausible's current release cadence and compatibility with 4.33/4.34 were not checked. Its repository showed about 146 commits.

## 5. Prior Lean projects validated against conformance suites

### Takeaway
Every project I checked (EVMYulLean, LNSym, Cedar) runs its conformance or differential tests as *compiled executables*, not kernel proofs. Kernel-proving each conformance case would put this SQLite project in largely uncharted territory at scale, which argues for the tiered approach in section 3.

### Cited Findings
- Nethermind EVMYulLean passes "99.99% (22,330/22,332) of these Cancun execution tests". — [Nethermind blog](https://www.nethermind.io/blog/a-trustworthy-formal-model-of-evm-yul-in-lean). The tests run as a compiled Lake test driver, `lake test -- <NUM_THREADS>`, with multi-threaded execution. — [NethermindEth/EVMYulLean](https://github.com/NethermindEth/EVMYulLean)
- LNSym: "Since Lean programs are executable, the specifications achieve a high degree of trust through thorough conformance testing". Running `make` builds the proofs and runs conformance testing, which "will be skipped" on non-AArch64 machines, i.e. it co-simulates against real hardware. The default is `NUM_TESTS=20` random tests per instruction class. — [LNSym README](https://github.com/leanprover/LNSym/blob/main/README.md); [Amazon Science blog](https://www.amazon.science/blog/how-the-lean-language-brings-math-to-coding-and-coding-to-math)
- Cedar: DRT against the compiled Lean model, with millions of inputs per target (section 4). — [arXiv 2407.01688](https://arxiv.org/html/2407.01688)

### Inferences
- The industry pattern is: the executable model is validated by compiled differential or conformance testing, and generic theorems are proved about the model. Theorems of the form "model passes test N" are rare. This project's kernel-checked test theorems are an additional assurance layer. They are worth keeping for a curated set, e.g. cases that pin down subtle semantics or were once regressions, rather than for every fuzz case.

### Gaps
- I did not find details on how WebAssembly-in-Lean, the Sail-to-Lean RISC-V model, Veil, or SampCert run test suites. They were not researched within the tool budget.
- I did not confirm whether EVMYulLean's test runner uses `native_decide` anywhere.

## 6. Generic properties to prove once instead of testing

### Takeaway
Properties that quantify over all databases or statements should be proved as theorems about the model. They are cheap once, and they avoid per-case kernel cost. Structural recursion and first-order data (lists, not functions or HashMaps) make these proofs tractable.

### Cited Findings
- Cedar used property-based testing for "properties we have yet to prove in Lean" as a staging step before proofs. — [arXiv 2407.01688](https://arxiv.org/html/2407.01688)

### Inferences
Candidate once-only theorems for the SQLite model:
- **Determinism:** follows definitionally if the model is a function `exec : DB → Stmt → Result × DB`. State this explicitly only if the model uses relations.
- **Transactions:** `ROLLBACK` restores the snapshot taken at `BEGIN`, and failing statements under default conflict handling leave the DB unchanged (statement atomicity).
- **`ALTER TABLE ADD COLUMN`:** preserves the row count and existing column values, and fills the default in the new column.
- **Renaming:** `RENAME TABLE`/`RENAME COLUMN` preserve data.
- **SELECT is read-only:** it does not change the database (except for `sqlite_sequence`, where relevant).
- **Constraint invariant:** `INSERT` into a table with a UNIQUE/PK constraint preserves the invariant "no duplicate keys".
- **Type affinity is idempotent:** applying affinity twice equals applying it once.
- **Comparison is a total preorder:** comparison and collation used for ORDER BY form a total preorder, which is needed for sorting correctness.
- **Conversions round-trip:** e.g. integer→text→integer round-trips within the 64-bit range.

Use Plausible to smoke-test these before investing in proofs.

### Gaps
- I found no source specific to proving such properties about SQL models in Lean. This list is based on reasoning about the model, not on literature.
