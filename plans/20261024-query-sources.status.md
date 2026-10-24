# Status: queries as sources
Created 2026-10-24. Status: OPEN. Part 1 DONE; CTEs and views remain.
Task: [task file](20261024-query-sources.task.md).
Specs: ADR 0019 D5/slice 4 and D3 metadata exception; ADR 0017 S6.
Inspected base: `vihren-dev/sqlite-verifier`, PR #239, commit `98a07bfe`.

## Owner decision and observations

On 2026-10-24 the owner selected: "Support nonrecursive CTEs only; reject actual
recursion and retain the exclusion of the RECURSIVE keyword." The ADR and task
record this scope. There is no outstanding CTE-scope decision.

The audit used pinned SQLite 3.51.0; acceptance uses the native/kernel checks
and measured predictions below, not lexical SQL counts.

## Progress
- 2026-10-24: specified D5 in three acceptance parts. Task review
  `20261024T122324Z-cf7aa9a6` passed with no findings. ALTER/rebuild work waits
  for views; FK laws must cover their catalog statements at integration.
- Carried the reviewed task and ADR amendment onto S4 part 1 `372e6c8f`/PR #240.
  Query-source syntax/resolution/evaluation/codecs belong to this task; S4 owns
  success/program laws. INSERT SELECT staging belongs to slice 5.
- 2026-10-24: carry commit `8a89208f` passed independent Claude review
  `20261024T130558Z-8a89208f`, with no findings. Before any model edit, the Nix
  prediction baseline was built at
  `/nix/store/qwfgz46d1pyd10xiypmka4kixvx38k2b-sqlite-verifier-predictions`.
  Its Nix verdict is
  `/nix/store/srv5lc3gnn1s9wzfjy1ilrzsb2ws0881-sqlite-verifier-verdict`:
  all existing claims pass; corpus v4 has 673 AGREE cases and corpus v5 has 2,946.
- The first implementation unit gives resolved sources an indexed-query payload,
  reuses `EvalContext.subqueries`, and distinguishes complete-row certainty from
  the first-column certainty of IN. Source rows retain the enclosing cells so
  an unmatched right/full row cannot erase them. `DerivedSourceExamples.lean`
  contains kernel checks for joins, uncertain membership, outer cells, parameters,
  counters and the clock.
- Nix check for this execution unit: `nix-build build-support/default.nix -A
  modelPackage` passed at
  `/nix/store/d8gfbj5myc9v0lpsqm0c5lmmpj6534bl-belay-sqlite-model-0.1.0`.
  The build checks the new `DerivedSourceExamples` kernel examples and existing
  query/S4 proof modules.
- Execution-unit review `20261024T132633Z-93767a4d` had no must finding and one
  should finding: test a source with a non-success ending and no expression fault.
  The added kernel example checks that this source is refused. Nix `modelPackage`
  passed at `/nix/store/pp68ghibam1vkp4y5cw5nlsfjb171d86-belay-sqlite-model-0.1.0`.
- Review `20261024T133405Z-15a252a8` passed with no findings.
- The metadata unit adds expression affinities for every source column and SQLite's
  compound affinity combination. D3's ORDER BY COLLATE rewrite now supplies IN with
  derived-column affinity/collation; scalar subqueries still supply no collation.
  The removed restriction is also removed from its registry, documentation and
  example, and the existing compound-collation mutant follows the new branch.
- Source metadata exposed an existing output-collation bug: a FULL JOIN USING
  output is a coalesce without collation, and a RIGHT JOIN output reads the right
  column's collation. The shared expression/star metadata now follows those
  operands. Generated USING equalities retain their existing left-column rule.
  `DerivedColumnExamples.lean` checks both joins, three-column metadata, absent
  affinity, compound type conflicts and D3 comparisons. The targeted Python checks
  are `restriction_registry_test.py` and `mutant_guards_test.py -k compound`.
- Nix `modelPackage` for this metadata unit passed at
  `/nix/store/zs2dfp63la9ib1cx7qskny4l9pvdq4b0-belay-sqlite-model-0.1.0`.
- Review `20261024T140053Z-649a3021` had no must finding and two should
  findings. Both metadata functions now list all expression constructors instead
  of using catch-all branches, so new syntax must explicitly choose its metadata.
  Nix `modelPackage` passed at
  `/nix/store/24qvzhb6dpmsh27pzgqyjwr921dkkqbp-belay-sqlite-model-0.1.0`.
- Review `20261024T140753Z-bc79e3e7` passed with no findings.
- The derived-source pipeline now connects SQL translation, the indexed syntax,
  name expansion, source/outer scopes and all-column metadata to the existing
  evaluator. Source bodies resolve in FROM order; scalar siblings retain written
  order. A derived source can read its enclosing query but not its sibling sources.
  Nested USING/NATURAL conditions refresh after derived-column metadata resolves.
  The kernel examples cover these rules, duplicate names, the lack of implicit
  rowid, aggregate sources and certain/uncertain LIMIT membership.
- Existing named-table proof APIs now require `reference.query = none` as well as
  their existing function-argument premise. Public callers and fixtures supply
  this premise. The new public `ClaimsDerived.lean` fixture and the changed syntax
  and source-span tests are selected by the existing Nix model/surface suites.
  Relevant checks: `syntax_queries_test.py`, `syntax_subqueries_test.py`,
  `syntax_compound_test.py`, `surface_claims_test.py`,
  `surface_translation_checks_test.py` and `restriction_registry_test.py`.
- Nix `modelPackage` for this pipeline unit passed at
  `/nix/store/wnxni6bvnfd3cisq5nndg95qspgbyh94-belay-sqlite-model-0.1.0`.
  It checks the new `DerivedResolutionExamples` and the existing model proof APIs.
- Corpus v53 is reserved for query-source evidence (v54 belongs to the FK task).
  The separate `query-sources-evidence` workspace starts from carry `8a89208f`.
  Corpus, claim and judge-lock changes remain separate from implementation.
- Pipeline review `20261024T144622Z-c64d8b50` passed with no findings.
- The native recorder now accepts a derived LIMIT when the outer query has no
  ordering or window. It records the returned rows without inferred tie groups;
  the model separately decides whether source membership is certain. Existing
  restrictions on nested windows in ranking probes and write sources remain.
  This changes acquisition scope, not SQLite's returned outcomes or the pinned
  oracle. The oracle lock covers `nix/sqlite.nix` and `nix/flake.lock`; this helper
  and its regression belong to the implementation. Corpus/claim/lock changes
  remain in the separate evidence workspace.
- The focused Nix harness check selected all seven ordering tests, including
  native replay of the three newly recorded nested-window forms, and passed at
  `/nix/store/z1vg76nq9n7by0lzb8gbmjm3rvl89c6j-sqlite-verifier-test-query-source-ordering-1`.
  This confirms the existing ranking/write guards and the new raw-observation
  path.
- Recording-fix review `20261024T150653Z-dda5b767` passed with no findings.
- The authored source inputs now cover 42 cases through the native recorder,
  translator, resolver and evaluator. Nix `query-source-coverage` passed at
  `/nix/store/804jb5hkkrpn3ahxd21x556aajwz13m2-sqlite-verifier-test-query-source-coverage-1`.
  It kernel-checks 38 agreements and four explicit `classifyCase = modelUnsupported`
  boundaries: uncertain compound representatives, uncertain LIMIT membership,
  uncertainty visible only in the second column, and fallible evaluation.
- The four focused mutants all changed their target verdicts in Nix at
  `/nix/store/qrcwvlzhklhii66vmw9g3yi6pigv8d8m-sqlite-verifier-test-query-source-mutants-1`.
  They check forbidden sibling binding, all-column affinity, collation and whole-row
  certainty. Each parameterized test builds one mutant at a time. The new coverage
  and mutant tests are registered in the model and scheduled mutant Nix suites;
  `mutant_guards_test.py` also checks their rule locations.
- Frozen Nix predictions after the pipeline unit are at
  `/nix/store/xar2y93h71ffx1ccrjvy906936hk4ahj-sqlite-verifier-predictions`.
  Compared with the pre-edit baseline, 76 records change: 32 become predictions
  (29 fully supported, three still unmodeled at execution), and 44 retain a
  restriction with a changed reason. No previously predicted record changes.
  Corpus v53 stays private
  and mutable until the CTE and view parts add their evidence; the implementation
  contains native input definitions and tests, with no frozen outcomes or claims.
- Test-unit review `20261024T151304Z-4adc09c3` found no must issue and one should
  issue: the `ROOT` docstring named the requirement inventory instead of its
  repository directory. The docstring now states the path's actual meaning.
- Doc correction review `20261024T151400Z-83f0c532` passed with no findings.
- The separate draft evidence is based on subject/status boundary `8b1b26ef`.
  It contains corpus v53, its writer and registration, 38 new mustAgree cases,
  29 measured additions to the v4/v5 claims, and their lock. The report under
  `reports/20261024-query-sources-part1/` classifies all 76 changed predictions.
- The Nix evidence verdict passed at
  `/nix/store/6h8hi4b2c0z3fkxjamwix6508l30dz9i-sqlite-verifier-verdict`:
  v4 has 675 agreements, v5 has 2,973, and v53 has 38 agreements plus four model
  restrictions. Every prior agreement and claim survives. There are no
  disagreements or harness errors. The combined predictions at
  `/nix/store/qjij3iya9bpd9mfl0mmln91wnyqcb80q-sqlite-verifier-predictions`
  add v53 and preserve all 53 previous corpus files byte-for-byte.
- The Nix writer round trip passed at
  `/nix/store/9dzarjyyg9iq1r1n029b04a7rbbw18ja-sqlite-verifier-test-query-source-writer-1`;
  complete validation of the actual v53 shard passed at
  `/nix/store/hxi4kmq91n1vpl13nsjbi9cnkj6qw8yq-sqlite-verifier-test-query-source-corpus-1`.
  The evidence remains unpublished and mutable for CTE/view additions.
- Evidence review `20261024T152537Z-873a1473` passed with no findings. The first
  full gate reached all source checks and found two stale RIGHT JOIN mutant
  targets after the enclosing-cell preservation change; no evaluator change was needed.
  The evidence report now links here for the current acceptance state.
- Report review `20261024T153132Z-753e0f3c` requested clearer pending-status
  wording. Its link now explicitly refers to the current part-1 acceptance state,
  without implying that the final gates have passed.
- Review `20261024T153240Z-88781fdd` had no must issue and repeated the request
  for a status line in the report. Rejected: the report gives verified Nix results
  and explicitly links to this file for current task acceptance. Duplicating the
  changing acceptance state there would become stale; it does not assert a pass.
- The first combined full gate found stale text in two existing RIGHT JOIN
  mutants after `joinRows` began retaining enclosing cells. Their targets now
  match the changed definition and preserve their original faults: dropping an
  unmatched right row or padding with the right source's width.
- The two affected mutants ran sequentially and were both detected in Nix at
  `/nix/store/k2a4zs0px4yywv760jyjlmzaxj29fs1s-sqlite-verifier-test-query-source-right-mutants-1`.
  The existing scheduled suite runs the new focused test; execution is unchanged.
- Correction review `20261024T153312Z-5291750b` passed with no findings. The
  acceptance descendant combines evidence `dc77491d` with subject `5291750b`;
  only the status log conflicted, and both checked histories are retained.
- Combined-boundary review `20261024T153541Z-08c47c2b` passed with no findings.
  Its full gate passed all 153 frozen tests and 55 corpus validations, then failed
  on a stale profile fixture expecting derived SELECT to be refused. The model-output and pipeline
  transport fixtures had the same stale expectation. All three now use EXPLAIN,
  which retains the intended frontend-refusal check as derived sources gain support.
- The focused Nix checks passed: the older-engine profile test at
  `/nix/store/9sv6jj19n33hr76wjry090k78ah88m17-sqlite-verifier-test-query-source-boundary-harness-1`,
  and both model-output/transport tests at
  `/nix/store/kj1l7gpva3ysjdlzlkvbw1bwnzcx5wgv-sqlite-verifier-test-query-source-boundary-model-1`.
  This changes test inputs only.
- Refusal-fixture review `20261024T154723Z-42812ff3` passed with no findings.
- Merge review `20261024T154823Z-0c0faa97` had one should finding about the
  status log. The wording now identifies the passing suites and failure in one gate.
- Part 1 passed acceptance at combined boundary `c8db1a54` after review of
  merge `0c0faa97`. Post-review `just test-full` passed all 854 Nix-selected tests:
  `/nix/store/m64rgzasy2aqvp6d421pk5yh0v4654b9-sqlite-verifier-test-reports`.
  Final `just verdict` passed at
  `/nix/store/6nazink0rsrzhv7458rs3vgfs63c48dg-sqlite-verifier-verdict`.
  Its predictions `/nix/store/q4qrigjpa82cg89ggzkvinbnvmgi7pq6-sqlite-verifier-predictions`
  are byte-identical across all 54 files to the earlier `qjij3iya9bpd9mfl0mmln91wnyqcb80q` artifact.
  Subject checkpoint `d87fbaa0` excludes frozen corpora, claims and the judge lock.
  Ordinary CTEs and views remain OPEN; v53 retains its separate owner-merge gate.
  The subject publication merge combines `16bd87a3` with accepted S4 query-law
  checkpoint `975f31eb`, including PR 241's source filter and no v53 evidence.
  Merge reviews `20261024T161528Z-63299f66`/`20261024T163932Z-359eb0c7` passed.
  The ADR records part-1 completion; review `20261024T164409Z-17f929bd` is clean.
- Subject publication source `17f929bd`: full 853 passed in ten suites, no
  failures/errors/skips, at `/nix/store/nfqd2rh03b7avhd5ifzk08rwbf9p38ab-sqlite-verifier-test-reports`.
  Verdict 4867 AGREE/2505 MODEL_UNSUPPORTED, no disagreements/harness errors:
  `/nix/store/sjs0cw7jyy2k5adr3rgw2jh6d1iybnii-sqlite-verifier-verdict`.
  All 53 files at `/nix/store/2kpi159rivfybjqkv2cw7vxh31qpdlbq-sqlite-verifier-predictions`
  match accepted `q4qrigjpa82cg89ggzkvinbnvmgi7pq6`, excluding its draft v53.
  The judge lock is unchanged. Nix integration passed 70 checks in 364.39s.
  Scheduled checks passed all 47 cases, no failures/errors/skips, at
  `/nix/store/s5vl7g5lx4ikp3ypmcjrig1jc5y26swz-sqlite-verifier-scheduled-check-reports`.
  All publication gates are terminal and passing; CTEs and views remain OPEN.
