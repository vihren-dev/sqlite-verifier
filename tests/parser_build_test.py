"""The grammar adapter preserves syntax and rejects mismatched upstream tokens."""

from pathlib import Path

import pytest

from parser.generate import generate

pytestmark = [pytest.mark.unit, pytest.mark.parser]


def test_generator_preserves_rules_and_rejects_mismatched_tokens(tmp_path: Path) -> None:
    """Keep precedence, children and token maps; fail before output on empty or mismatched inventories."""
    header = "#define TK_ID 1\n#define TK_PLUS 2\n"
    grammar = "input ::= expr.\nexpr ::= ID PLUS ID. [PLUS]\n"
    target = tmp_path / "syntax.y"
    generate("%left PLUS.\n", grammar, header, header, target)
    result = target.read_text()
    assert "%left PLUS." in result and "ctx->root = A;" in result
    assert 'expr(A) ::= ID(v0) PLUS(v1) ID(v2). [PLUS]' in result
    assert 'branch(ctx, "expr", 3, (int[]){v0,v1,v2})' in result
    assert (tmp_path / "token_map.inc").read_text() == "case 1: return P_ID;\ncase 2: return P_PLUS;"
    assert (tmp_path / "token_names.inc").read_text() == 'case TK_ID: return "ID";\ncase TK_PLUS: return "PLUS";'
    for actual, native in ((header, header.replace("PLUS 2", "PLUS 3")), ("", "")):
        rejected = tmp_path / "rejected.y"
        with pytest.raises(ValueError, match="token inventories differ"):
            generate("", grammar, actual, native, rejected)
        assert not rejected.exists()
    with pytest.raises(ValueError, match="Unexpected upstream production"):
        generate("", "input ::= ID. trailing", header, header, tmp_path / "invalid.y")
