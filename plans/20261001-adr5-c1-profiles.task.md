# ADR 0005 C1: verified execution profiles

Created 2026-10-01. Status: IN PROGRESS.
Status: [progress](20261001-adr5-c1-profiles.status.md).
Spec: [ADR 0005 §3.2](../docs/adr-0005-conformance-corpus-scale.md#32-execution-profiles).

## Observable outcomes

Recording and native replay share a named, versioned profile identifying the
engine version, source ID, complete compile options, behavioral connection
settings, transaction conventions, external clock inputs and other-writer
assumptions. The profile is carried in corpus manifests and native evidence.
Connections establish and verify the profile before executing case SQL; an
unestablishable profile or replay under a different profile is refused.
Existing frozen evidence and its default profile remain readable and replayable.

A generic profile supports foreign keys on and immediate transactions. Every
statement's stored clock value reaches SQLite through its native time source,
including triggers, defaults and supplementary SELECT probes. Recording at one
wall time and replaying at another produces identical observations. This adds
test infrastructure, not production model semantics.

Documentation explains how to measure SQLite version, source ID and compile
options from each running workload driver. Unmeasured engine gaps are stated
explicitly. Workload names, SQL, data and measurement results stay external.

## Behavioral verification

Native tests check setting readback and foreign-key cascades, explicit BEGIN
IMMEDIATE sequences, engine/compile-option/settings/profile mismatch refusal,
clock-dependent SELECT and writes with trigger/default clock reads, and replay
after wall time changes with identical typed outputs and state. Probes see the
statement's clock. Existing frozen corpora replay under their old profile.
Tests and native statements have bounded timeouts.

## Tricky points and sources

`native_library.py` pins the engine and declares C signatures;
`native_connection.py` opens/configures connections; `native_record.py` creates
writer and committed-state reader connections and currently denies clock SQL.
`native_statements.py` owns statement boundaries and supplementary probes.
`corpus.py` and `native_replay.py` route fresh native replay and model admission.
SQLite reads 'now' from VFS callbacks: SQL rewriting or storing timestamps alone
does not control defaults and triggers. Callback lifetimes and connection/VFS
cleanup must remain explicit. Profiles must not silently broaden the model's
admitted execution conditions. The workload's engine measurement may require
another pinned build; do not infer compatibility from a driver package version.
