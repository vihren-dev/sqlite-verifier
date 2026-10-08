# Preserve mixed-root sibling capability

The resumed review identified a capability that must be retained: roots with
the same package spelling still need a merged view to expose caller sibling
modules, including across different filesystem case modes. Restored that
existing exact-spelling rule. Different spellings combine only when every
original root containing the package ignores letter case. Otherwise those
spellings keep their original search paths. The docstring now states both rules.

The corrected fresh macOS runtime passes 13 focused checks: ten import-path
checks and actual preparation, export and kernel replay for all three caller
namespace cases. The deterministic tests cover six mode/spelling combinations
in both root orders. Matching spellings retain sibling access and first-root
bytes; different spellings on mixed roots retain original paths. Physical
mixed-volume native testing is not claimed.

The original logs and XML remain compressed without changes. `source.json`
binds the helper, tests and actual runtime, and `sha256.json` binds each file.
The test command has a 300-second outer limit. Earlier 24-test receipts remain
bound to the intermediate helper and do not certify this final correction.
Full integrated acceptance, independent correction review and final owner
review remain pending. The trust-review finding is deferred to the owner's
requested final integrated PR #56 review.
