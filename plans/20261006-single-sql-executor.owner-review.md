# SQL executor and protected schema review

Created 2026-10-06. Status: APPROVED on 2026-10-07.
Task: [observable outcomes](20261006-single-sql-executor.task.md).
Execution: [status and acceptance](20261006-single-sql-executor.status.md).

## Review decisions

The library uses only `runSqlFrom` and `runSql`. The removed extension executor,
duplicate relation and bridge have no source callers or compiled compatibility
module. `ProfileExecutes` remains the contract relation. SQL computation helpers
require a support proof for every admitted starting database; callers can still
construct the primitive verification fields directly. Schema preservation and
prefix composition require an explicit CREATE/ADD guard and idle starting state.
They do not certify arbitrary writes or transaction prefixes.

The exact primitive `step` body and the complete existing Contract target
formulas remain unchanged. The review concerns the changed import/proof structure
and the newly protected source bindings, not approval of a new SQL subset.

Both invoice policies now read `Generated.startSchema` from sealed `SchemaInputs`.
Their proposed baselines bind these exact source hashes:

| Input | Ordinary invoice | Allowed failure |
| --- | --- | --- |
| `Interpretation.lean` | `3d8e2c8210bd32e6348769df208f52aa893df8e92c46f2ed834ac9e7f9644bd2` | same |
| `Requirements.lean` | `4bee30115f2aa8a7b4494a523011c1ce5fdf3eb8b2cbb142e9c5c750a6d7c4b3` | `1ab35759e951b4252e6cc391a4f58064b60e62c2af0791dcf01e7b92bfcd7e0a` |
| `schema.sql` | `70f3ef1458be467b401d433e2fc5c3a8aec43ed0b1f89d7069f3f5d2bfd290d3` | same |

Requirements and schema SQL bytes are unchanged. The interpretation uses the
generated equivalent schema instead of a duplicate literal. The owner approved
PR #48 at reviewed head `45ac63b2e07d6677c12187adafa1cdc96dc155d6` in the
implementation chat on 2026-10-07. Approval includes the exact proposed baseline
contents above and the verification-target file. The target-owned protected
baseline check stays unchanged and rejects this deliberate drift. Integration
requires the recorded maintainer exception for that owner-reviewed change;
the failed check is not a pass.

## Evidence and remaining gates

Checked migration `26fbe6fc` and correction `0eb80129` have source, ordinary,
compiler, focused native/model and real Nix input-identity checks. The correction
has independent review with no findings. The earlier R8 owner marker is deferred
to this review, without approval.
Schema checkpoint `1432aec5` and native evidence checkpoint `9bee3dd0` each
passed required independent review with no findings. Every implementation
should finding is fixed. Payload and exact XML/helper/source hashes were checked
locally after receipt transfer.

Current bundles are checked against their actual inputs/library and repeated
preparation produces identical bytes. Immutable T03/T02 fixed-model/input byte
receipts are retained. Their hashes do not become new goldens for changed inputs.

The generated-schema feature passed 336 source checks, 184 ordinary checks and
42 actual installed Darwin checks, including every protected invoice example,
schema tampering before invalid proof code, current bundles and retired API
refusal. Its installed archive SHA-256 is
`c684a76b3bc53d16f34d3556d3a92c86badac3f61238e88bd28089dd4190d16c`.
Native Linux acceptance also passed: 184 ordinary, 83 infrastructure, 11 focused
native/model-law and 42 actual installed cases, without failures or skips. Its
source suite passed 334 cases and 28 subtests; two optional reviewer-CLI checks
skipped because those CLIs are absent. All tracked source bytes stayed unchanged.
The actual Linux archive SHA-256 is
`137c9bc90fad00a2f92748d95b8b18f52be4e922bbb367fceca20a289165335f`.
Both native receipt sets are retained in
`reports/20261006-single-sql-executor/`. Draft PR48 is published for review. Its
first hosted run failed the mutation harness on both platforms because extraction
still depended on a deleted docstring. The requested correction now has clean independent review, five targeted checks
on each host and complete native model validation: 322 passed and one existing
Tcl-capture skip per host. Linux used the unchanged 420-second budget (328.30
seconds); Darwin used the separately reviewed 600-second validation recipe
(484.74 seconds). PR48 still configures 420 seconds; the timeout-task source is
not merged here. The earlier Darwin configured-budget failure, exact invocation,
file order, source hashes and original XML/logs remain retained in `full-model/`.
Both hosted native checks now pass, and PR #49 delivers the timeout correction.
Final R8 owner approval is recorded above. Publication integration, the expected
baseline exception, merge and release remain open. This packet records approval;
the task is not DONE.
