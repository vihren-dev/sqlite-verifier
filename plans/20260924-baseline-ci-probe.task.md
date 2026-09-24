# Hosted baseline protection probe

Created: 2026-09-24. Status: IN PROGRESS.

The target-owned workflow must accept an unchanged approved tree and reject
candidate changes even when the candidate rewrites its baseline and checker.
Evidence is the real hosted check result for both candidate commits. This
throwaway PR is never merged; it executes no candidate code in the privileged
baseline workflow. Main remains untouched by the deliberately invalid fixtures.
