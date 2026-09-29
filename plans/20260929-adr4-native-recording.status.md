# Translator-independent native recording: status

Created 2026-09-29. Status: DONE.
Task: [Translator-independent native recording](20260929-adr4-native-recording.task.md).
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

Native acquisition and replay are implemented in `conformance/native_record.py`
and `native_replay.py`. Live out-of-subset recording, fresh translation, metadata
fault detection and main-database context checks pass (3 tests); the existing
pipeline also passes (12 tests). No merge is authorized.
