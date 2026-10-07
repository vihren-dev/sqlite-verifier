# Application-key acceptance on delivered main

Created 2026-10-08. Audience: team.
Task: [T15](../../plans/20261006-application-key-preservation.task.md).

The owner approves PR #53 and requests main integration before normal merge.
This integration includes delivered API-reference main `a38d0001`. All reviewed
feature code bytes are unchanged except the public barrel, whose imports
include both parents and whose checked walkthrough comes from main. The
three original journals retain their order and repeated rows in 319 rows.

The exact combined runtime builds as
`/nix/store/hyyvqd49sbkd2cxjjmdc6m76ns9dh5m8-sqlite-verifier-runtime-1`.
All 281 authored public items have checked documentation, with zero missing
or unclassified items. Ordinary source checks pass 412 tests and 35 subtests,
with 95 deselections. All seven ordinary macOS Nix suites pass 313 checks.
Actual infrastructure checks pass 95 tests, with 928 deselections.

A fresh content-verified offline archive passes 24 common installed checks.
The same actual installation passes the three additional application-key CLI,
bundle and repeatability checks. The installation resolves its compiled library
under `/nix/store/nvxxjmicm78vn7sc3aii0hjsikl94msj-sqlite-verifier-runtime-1`.
The original archive remains in the workspace's `dist/`; its exact size and
SHA-256 are retained. Original XML, inventory, console logs, identities and
parent journals are bound by `manifest.json`.

Independent integration review, fresh hosted Linux checks and normal merge
remain required. Earlier acceptance stays bound to its original source and
runtime. No performance claim or task completion is added. T15 is IN PROGRESS.
