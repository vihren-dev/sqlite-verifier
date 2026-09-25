# Business preservation contract

Created: 2026-09-25. Status: ACTIVE.

## Required outcome

The Atuin example verifies preservation of the pre-migration business model for every admitted starting database. History has no shell field. The approved contract does not anticipate the next schema or require SQLx catalog correctness. The proposed interpretation reads the old model from resulting storage; the theorem establishes equality of old business histories before and after. Starting schema, model, interpretation and assumptions remain protected inputs.

The supplied migration is the upstream ALTER payload only. SQLx bookkeeping and wrapper behavior are explicitly trusted and outside the example. The schema describes the application tables. No full new-model correctness or future application compatibility is claimed. The current list equality and success proof remain: this task does not introduce unordered collection semantics or permit destructive failures.

## Observable validation

The public CLI verifies the exact payload and protected contract. A different nullable added column can also be proved against the unchanged approved files, demonstrating the contract does not anticipate shell. Reused proofs for changed inputs, readers that drop records or erase commands, changed protected schema/model/decoder, and unfinished proofs are rejected. Concrete empty and populated witnesses and decoder checks remain. The pinned native SQLite check independently confirms existing application rows are unchanged. Relevant schema generation, kernel gate, staging, CLI, coverage and documentation checks pass with timeouts. Packaging is unchanged; no archive rebuild is required for this source/example change.

## Constraints and relevant code

SqliteVerifier/Contract.lean provides the general theorem and outcome coverage; preserve those flexible primitives. A small preservation convenience may reuse them. examples/atuin/approved contains the protected closure; candidate files may depend on generated SqlInputs, while approved files see only generated SchemaInputs. Tests must distinguish proof rejection from timeout and cannot treat a failed proof as a witnessed refutation. Update the baseline hashes only after the intended new contract is complete.

A new interpretation establishes recoverability from resulting storage, not automatic agreement with application reads. It cannot access a proof-only original database. Keep decoder-definedness and nonempty admitted-state evidence. Remove catalog, checksum and exact-next-schema obligations from the example, not generic literal DML or failure semantics from the core.
