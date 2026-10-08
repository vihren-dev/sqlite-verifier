"""The existing proof attacks are selected independently by both kernel acceptance suites."""

import pytest

# Source, required diagnostic and acceptance expectation preserve the current gate inventory.
PROOF_ATTACKS = [
    pytest.param("{valid}", "", True, id="valid"),
    pytest.param('{valid}\ninitialize IO.eprintln "CANDIDATE_INITIALIZER_RAN"\n', "", True, id="initializer_ignored"),
    pytest.param("import Lean\nimport Generated\nset_option debug.skipKernelTC true in\n"
                 "run_elab Lean.addDecl (.thmDecl { name := `Proofs.migrationCorrect, levelParams := [], "
                 "type := Lean.mkConst `Generated.expected, value := Lean.mkConst `True.intro })",
                 "while replaying", False, id="forged_kernel_body"),
    pytest.param("import Generated\ntheorem Proofs.migrationCorrect : True := trivial", "reconstructed", False, id="wrong_theorem"),
    pytest.param("import Generated\ntheorem Proofs.migrationCorrect : Generated.expected := by sorry", "sorryAx", False, id="sorry"),
    pytest.param("import Generated\naxiom forbidden : Generated.expected\ndef helper := forbidden\n"
                 "theorem Proofs.migrationCorrect : Generated.expected := helper", "forbidden", False, id="transitive_axiom"),
    *[pytest.param(f"import Lean\ndef {name} : Nat := 0\ntheorem Proofs.migrationCorrect : True := trivial",
                   name, False, id=f"changed_protected_{label}", marks=pytest.mark.approval)
      for label, name in [("contract", "Requirements.contract"), ("SQL", "Generated.script"),
                          ("schema", "Generated.startSchema"), ("profile", "Generated.profile")]],
    pytest.param("import Generated\nunsafe def Proofs.migrationCorrect : True := True.intro",
                 "Proofs.migrationCorrect", False, id="unsafe_proof"),
    # An explicit partial constant avoids elaboration into an ordinary opaque wrapper.
    # Lean.Replay omits partial constants; the required-proof lookup must then reject it.
    pytest.param("import Lean\nimport Generated\nrun_elab Lean.addDecl (.defnDecl { "
                 "name := `Proofs.migrationCorrect, levelParams := [], type := Lean.mkConst `True, "
                 "value := Lean.mkConst `True.intro, hints := .opaque, safety := .partial })",
                 "missing required declaration: Proofs.migrationCorrect", False, id="partial_proof"),
]
