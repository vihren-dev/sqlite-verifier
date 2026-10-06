# Full native replay storage evidence

The [Linux receipt](linux/receipt.json) records serial measurements on the idle
`vihren` host with public source revision `698cc4d4` and the retained
[measurement helper](measure.py). The [snapshot record](snapshot.json) binds
the transferred public archive. The [byte inventory](sha256.json) binds this
helper and the retained execution files.

Both storage directories were private directories created for this run.
`findmnt` reported ext4 for `/var/tmp/sqlite-verifier-storage.xkLtmU/disk` and
tmpfs for `/dev/shm/sqlite-verifier-storage.LJYdpN`. The receipt records their
actual mount, device, capacity, host memory and load conditions. The existing
10 GiB resource guard passed. No concurrent timing workload ran on the host.

Three representatives were selected before timing: the shortest authored setup
and the longest upstream setups from two different sources, with names used
to break ties. Each child had a 60-second bound. The retained input and both
complete fresh records are in `linux/case-N*.json.gz`.

| Frozen case | Setup commands | ext4 native seconds | tmpfs native seconds |
| --- | ---: | ---: | ---: |
| `add-default-storage-classes` | 1 | 0.2231 | 0.0192 |
| `e_expr:e_expr-1.cat.like.7:346` | 1,008 | 0.0306 | 0.0260 |
| `trigger2:trigger2-9.99:107` | 314 | 10.7872 | 0.0853 |

All six fresh initial states and traces equal their frozen observations. Each
complete fresh record equals its counterpart on the other filesystem. Profiles
and native source identities also match the retained inputs. The actual
ordinary-file `case.db` paths are recorded; each fixture was removed after use.

The expression setup consists of 1,008 commands that start with `SELECT`.
The trigger prefix includes commands that start with `CREATE`, `DROP`, `INSERT`,
`UPDATE` and `DELETE`. Neither setup changes `synchronous` or `journal_mode`.
Only the selected filesystem changed between each pair. The approximately
126-fold difference for the trigger prefix, compared with little difference
for the read-only expression prefix, locates the large cost in file-backed
write/setup work. This is an inference from the controlled comparisons, not
a measurement of individual flush syscalls. The run applies no recorder
optimization, in-memory database substitution or PRAGMA change. It establishes
neither ext4 full-run performance nor crash durability.

The [full report](linux/full.json) passed all 4,376 fresh native comparisons on
ordinary files under the declared tmpfs root. It audited all 4,376 actual
fixture paths. Native replay took **42.518 seconds**; the whole corpus command
took **91.125 seconds**, including loading, input binding and classification.
The unchanged command bound was 420 seconds. Source, corpus, recorded inputs,
runtime and native-library bindings are equal before and after the run.
The model still reports 4,376 `MODEL_UNSUPPORTED`; native replay does not add
model support.

The [historical execution record](../20261005-adr5-review-execution/README.md)
retains both ext4 full-run timeouts (420 and 900 seconds), its passing ordinary
ext4 sample, the earlier three-case comparison, and its 98.13-second tmpfs
native phase. None was replaced. These single-run times vary with host
conditions; this task does not claim an algorithmic speed improvement.

The fresh native phase, the whole corpus command, the development sample and
the full Nix model suite have separate bounds. A reported hosted Darwin model
suite timeout at 600 seconds is separate from this completed Linux 420-second
native command. This evidence does not resolve that suite or establish the
development sample's later 30-second target.

Local verification reloaded the ordinary frozen corpus, checked all case names
and digests, compared every retained paired native observation and complete
fresh record, and verified the execution source hashes against current files.
The Linux measurement helper always uses explicit storage roots and keeps
new receipts separate from frozen evidence.
Run `python3 reports/20261006-native-replay-storage/validate.py --source-root
/path/to/original-source` to repeat these retained-byte and observation checks.
The original execution source is identified in `snapshot.json`; later source
revisions require that original snapshot for the source-binding check.
