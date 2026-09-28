# Nix-owned runtime and offline packaging

Created: 2026-09-28. Status: DONE.

Nix must own the pinned Lean toolchain, parser, proof checker/library and complete
runtime builds. Remove Python native-loader dependency discovery and copied-ELF
relocation. Build-owned sandbox manifests must enumerate only the relevant Nix
closures; candidate code must not gain access to the entire store or caller data.

Offline archives must install the complete immutable runtime with its dependency
closure and GC roots. Preserve installation into a new path, Unicode/space paths,
no network requirement, no overwrite, poisoned-environment protection, archive
size guard and Nix import integrity checks. Do not disable signature checking or
silently add trusted keys. Native loader behavior and Lean proof acceptance must
remain valid after export/import.

Validation: native Nix runtime build; closure-manifest checks and real sandbox
checks; resource/input/installation regression tests; actual offline package
installation and all installed parser/verifier/Atuin acceptance cases. Update
active case/unit inventories when obsolete implementation-specific tests retire.

Relevant boundaries: build-support/{default,runtime,lean-toolchain}.nix,
packaging/{build_runtime,install,runtime_dependencies,relocate_elf}.py,
migration_check/{runtime,sandbox,source_closure}.py, justfile and CI runners.
