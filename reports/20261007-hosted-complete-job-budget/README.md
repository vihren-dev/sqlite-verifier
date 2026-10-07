# Hosted complete-job deadline evidence

PR #48 head `9e91e525`, run `37600117584`, Darwin job `112722154338`
completed cancelled after 1824 seconds. This matches the configured
30-minute hosted job guard. No replacement run exists at this head. The
original console log reports 42 bundle passes in 376.21 seconds, followed by
cancellation during the complete recipe. No full Darwin pass is claimed.

The original job metadata and decoded console bytes are retained without
changes; gzip is only archival transport. Counts are console-derived, not
from locally downloaded hosted XML. `old-guard-oracle.json` records the actual
phase orchestration rejecting the original 30-minute guard. The unchanged
sequential limits require 3620 seconds in Darwin build mode, before setup and
artifact retention. The 75-minute guard covers those limits and a five-minute
allowance. Every individual test and command deadline remains unchanged.

`sha256.json` binds the retained payloads. This report is evidence for the
aggregate deadline repair; fresh hosted acceptance remains required.
