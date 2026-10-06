# Current SQL executor acceptance

The source checkpoint is `1432aec5aec5d43896bd389d8ba7f50be6c06c1b`, after the
reviewed execution migration and exhaustive-guard correction. This checkpoint
changes the current proof APIs and approved invoice interpretation bindings.
It does not change the verification target fields, primitive schema transition,
native observations or frozen v1–v5 corpus bytes and denominators.

`darwin.json` identifies the built runtime and content-verified offline archive.
Its installed-current-export properties retain exact input hashes, every compiled
library-file hash, executables, trusted import headers, bundle length/digest and
two actual checker reports for each success, refutation and Atuin case. The
eight original XML receipts are stored byte-for-byte as UTF-8 strings in
`darwin-junit.json.gz`, with their separate SHA-256 values. Source XML includes
28 subtests in addition to 336 ordinary pytest cases.

`linux-snapshot.json` identifies the reviewed public Git-object archive, every
one of its 872 regular tracked source files and the single instruction-file
symlink. `linux-driver.sh` is the exact executed helper. Both archive and helper
SHA values, and all tracked source bytes, were verified before execution in a
fresh task-specific Linux directory. Previous task directories remain retained.
The helper completed successfully. `linux.json` identifies the actual native
runtime and content-verified offline archive. `linux-junit.json.gz` retains ten
original XML receipts, with their separate hashes. It records 184 ordinary,
83 infrastructure, 11 focused native/model-law and 42 actual installed cases,
all without failures or skips. Source checks passed 334 cases and 28 subtests;
two optional reviewer-CLI presence checks skipped because Codex and Claude were
absent. Every required runtime case executed. The post-run source report confirms
all 872 regular tracked files and the instruction symlink stayed unchanged.

These are current-input runtime checks. The original T03/T02 exporter receipts
remain immutable fixed-model/input byte checkpoints and can be reconstructed
from their exact source revisions through Nix. They are not new expected bytes
for this intentionally changed checkpoint.

No cold performance measurement or speed comparison is made. The separate T13
environment feedback holds the full model gate; it was not run here. Final owner
review of the verification-target file and proposed protected baselines remains
pending. Passing compilation or these runtime checks does not supply that approval.
