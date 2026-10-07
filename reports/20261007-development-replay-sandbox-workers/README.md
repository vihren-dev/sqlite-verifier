# Worker timeout checks without a process-list command

Audience: task reviewers.

The [receipt](receipt.json) binds the test sources and original payloads.
The complete `tests.sample` Nix target runs in the hardened macOS sandbox.
All 22 checks pass in 40.40 seconds, including the actual four-worker timeout
case. Its original JUnit and compressed build log are retained here.

Each blocked worker holds an exclusive file lock before it publishes its PID
marker. The parent checks that all four locks become available after the
configured process-group timeout. A running blocked worker still holds its
lock; a terminated worker releases it even if its PID remains as a zombie.
The check needs only Python's Unix file-lock API and does not invoke `ps`.
Crash and timeout fixtures are declared inputs of their actual `sample` suite.

All 13 focused native-worker and frontend checks pass. The real dependency
check confirms that changing the fixture invalidates only `sample`. Earlier
`harness` checks did not contain the worker test and are not worker acceptance.

The 120-second replay phase limit, 5-second driver limit and 3-second worker
bound remain unchanged. Production workers and prior performance receipts
are unchanged. This sandbox result does not establish the under-30-second
performance target. The retained standalone Linux measurement still misses it.
