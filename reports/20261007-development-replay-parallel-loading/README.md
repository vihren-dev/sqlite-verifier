# Bounded parallel shard loading

Created 2026-10-07. Audience: team and reviewers.
Task: [T04c](../../plans/20261006-development-replay-headroom.task.md).

The loading-only feasibility run validates the same 109 frozen v5 shards
and returns the same 4,376 ordered records. Serial validation takes
12.911504042 seconds; four spawned processes take 7.974502375 seconds,
including process setup and transport. Serial runs first. Cache residency
is unknown, and the optional host memory query was denied by the sandbox.
Source hashes are observed after execution, not before import. This is a
component diagnostic, not whole-loader or replay acceptance. It performs
no native replay or model execution. Frozen bytes match before and after.
Original helper, results, streams and observations are compressed without
changing their original bytes. The receipt binds both hashes.

The library loader keeps its serial default and supports a caller-owned
standard executor. The development helper uses four spawned loading
processes and finishes them before native replay. Each worker runs the
existing complete shard validator. The parent retains global names,
counts, profiles, acquisition and fidelity checks before selection.
Read-ahead errors wait behind earlier payload results. Size-limit refusals
retain their class, measured size and limit across process transport.

Nine real thread/spawn tests pass. The broader bounded suite passes all
128 checks in 7.75 seconds against the existing conformance runtime. Its
first invocation used nonexistent `build/conformance`: 127 passed, but one
routing fixture failed at setup. That original XML remains a failed run.
The corrected result does not erase it.

Actual hardened macOS Nix targets pass 129 harness and 22 sample checks
without failures, errors or skips. The sample suite includes the full
fresh development CLI and worker timeout cleanup. Its 30.213-second suite
duration is not the task's replay timing target. Standalone acceptance on
both platforms remains required. Original XML, logs and output identities
are retained. Independent feature review remains required.
