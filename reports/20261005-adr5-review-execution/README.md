# V5 platform execution evidence

These receipts record actual execution against public source commit
`fe116b8744c7825529ec8eee21c33f15684a0694` and the unchanged v5 corpus.
[Byte inventory](sha256.json) binds the retained helper, source snapshot and
receipts; each successful receipt also binds its report and verifies unchanged
source, runtime, native libraries and input identities before and after execution.

The macOS ARM64 routes passed:

- [Full native replay](darwin/native.json): all 4,376 cases, 128.27 seconds.
- [Development sample](darwin/sample.json): 184 cases, 37.21 seconds for fresh
  loading, native replay and classification, within the unchanged 60-second bound.
- [Full progress](darwin/progress.json): 4,376 MODEL_UNSUPPORTED, zero disagreements
  or harness errors, and all 3,500 requirement rows retained.

The [Darwin helper](darwin/validate.py) retains the executed commands and checks;
the [source snapshot](darwin/snapshot.json) retains the 722 tracked file digests.
The linked reports remain in the parent reports directory.

The first [Linux full-native receipt](linux-native-420-timeout/native.json)
records exit 124 after 420.16 seconds, with no completed success report.
[Post-timeout bindings](linux-native-420-timeout/post-timeout-source-check.json)
confirm unchanged inputs. This is an incomplete measurement, not a disagreement
or a passing native gate. Later attempts must retain separate receipts.

Both-platform completion, the full isolated model suite and external workload
baselines remain pending. These observations do not extend the semantic model.
