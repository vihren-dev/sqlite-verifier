# Resumed mixed-root correction

The owner authorizes resuming the correction and tests after the two-round
review stop. The helper now combines differently cased package names only
when all original roots containing that package ignore letter case. When
original roots disagree, the package family retains its original paths and
search order, including when the directory spellings match. Thus a candidate
on a case-insensitive volume cannot change the casing recognized by a trusted
root on a case-sensitive volume.

Six deterministic cases supply explicit original-root case modes independently
of the test host. Each runs in both root orders. Equivalent roots expose alias
links and retain the first root's bytes; either mixed configuration retains
the original search paths. Matching and different spellings are both covered.
The required regression-coverage finding is recorded as fixed.

The final fresh macOS runtime passes all 24 affected documentation, import-path,
real compiler and exporter checks. The lowercase caller passes preparation,
export and kernel replay. The authoritative receipt is
`final-native-checks.xml.gz`; the matching runtime and helper hashes are in
`source.json`. Earlier receipts remain intermediate checks and are not rebound
to the final helper. Physical mixed-volume native testing is not claimed.

The final test command has a 600-second outer limit. Original logs and XML are
retained, with `sha256.json` binding each file. Full integrated acceptance,
independent correction review and final owner trust review remain required.
