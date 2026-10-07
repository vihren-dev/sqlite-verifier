# Lean 4.34.1 release evidence

The owner approved PR #43 on 2026-10-07. Its reviewed integration passed both
hosted native checks and protected baselines, then merged normally as
`bc9e2dce58f755b608cf00e545162257b81ab51a`.

[Stable v0.1.2](https://github.com/vihren-dev/sqlite-verifier/releases/tag/v0.1.2)
was published at `2026-10-07T08:23:49Z` from that exact commit. The tag was
unused before publication and remains unchanged. This release contains the
upgraded patched exporter. The later exporter and executor changes in PRs #47
and #48 are outside its snapshot.

[Release workflow 37591468199](https://github.com/vihren-dev/sqlite-verifier/actions/runs/37591468199)
completed successfully. Linux job `112693715520` and Darwin job `112693715743`
passed the complete package and actual archive-installation checks. Publication
job `112699862906` checked both archive checksum files before creating the
stable release. Its retained decoded log includes both `tar.gz: OK` results.

| Published native archive | Bytes | SHA-256 |
| --- | ---: | --- |
| `sqlite-verifier-aarch64-darwin.tar.gz` | 1125750944 | `d7feb85ccd2fa8eb2083328f544ea980897c622a9bb4bc95159185a8e22eaf4b` |
| `sqlite-verifier-x86_64-linux.tar.gz` | 949180419 | `f9096dca9349df801aa8f53246e0bbfda2a8adef934a2c4882dd884ee4c3c2c9` |

The downloaded public checksum files match GitHub's digest for each uploaded
archive. Each checksum file also matches its own asset digest. All four assets
are uploaded; the release is neither a draft nor a prerelease. The remote tag
was checked with `git ls-remote` and matches the reviewed commit above.
The archives were not downloaded again during this metadata verification.
The publication job checked their actual bytes before upload, and both native
package jobs checked their extracted installation.

`verified-release.json` records the release, immutable tag, workflow, asset
identities, URLs, sizes, archive digests and verification scope. The two public
API responses and decoded publication log are retained without changes.
`retained-sha256.json` binds all six retained files. The existing source,
installed, model and exporter-baseline receipts remain unchanged. Earlier
hosted model timeouts remain failures.

T03's implementation, final owner review, native and hosted acceptance, and
release publication are complete. Its dated task and status files are DONE.
