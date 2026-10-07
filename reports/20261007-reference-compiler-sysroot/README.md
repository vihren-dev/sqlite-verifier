# Selected compiler sysroot correction

Created 2026-10-07. Audience: team and reviewers.
Task: [T18b](../../plans/20261006-checked-api-reference.task.md).

CI `37663864057` builds and retains both native API references at head
`773827a1`. Their original ZIP hashes match the workflow artifact digests.
Each inventory checks all 259 authored items. The link records name 21
modules, 323 public declarations, 1,167 HTML pages and 829,618 valid links.
Their source revision is the actual CI merge commit `485f1eb8`. Extracted
original inventory and link records are retained. Full ZIPs remain in the
build directory and GitHub artifacts; they are not committed.

The later Linux source checks fail nine real inventory cases. They also
pass 399 tests and 35 subtests and skip two optional reviewer tools.
Original decoded job bytes, source XML and the matching report ZIP are
retained. That failure is not counted as ordinary acceptance.

The explicit compiler is valid. The helper's `findSysroot` call instead
starts ambient `lean`, which exits 255. The pinned Lean implementation
uses `LEAN_SYSROOT` when supplied. The wrapper now queries the selected
compiler's prefix and binds that environment value for its helper calls.
It does not change the compiler, dependency pins or inventory policy.

All 12 affected local checks pass in 39.61 seconds under a 120-second
limit. The existing positive check also passes in 3.63 seconds with a
failing ambient `lean` and no inherited sysroot, under a 90-second limit.
These runs use the existing exact runtime and start no Nix build. The
receipt preserves JUnit durations separately from console durations and
binds the original bytes. Corrected hosted acceptance remains required.
