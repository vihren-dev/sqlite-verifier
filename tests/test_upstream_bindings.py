"""Check the shortcut in `conformance.upstream_bindings.named_slots`.

Corpus loading skips the tokenizer for a command without `$`, `:` or `@`. These
tests compare the result with the tokenizer result for each command, so the
shortcut cannot hide a named parameter.
"""

import pytest

from conformance.query_window import tokens
from conformance import upstream_bindings
from conformance.upstream_bindings import named_slots

pytestmark = [pytest.mark.unit, pytest.mark.conformance]

COMMANDS = [
    "",
    "CREATE TABLE t(a INTEGER PRIMARY KEY, b TEXT)",
    "INSERT INTO t VALUES(1, 'no parameters here')",
    "SELECT ?1, ?, ?2",
    "SELECT $x, :y, @z, $x",
    "SELECT 'a $quoted :name' -- $comment\n, \"@ident\"",
    "SELECT 1 /* :in comment */",
    "SELECT $ns::var(index), ::, $a::b",
    "SELECT :1, @2, $",
    "UPDATE t SET b = $value WHERE a = :key",
]


def tokenizer_slots(command: str) -> list[str]:
    """Give the names from the tokenizer alone, as `named_slots` did before the shortcut."""
    return list(dict.fromkeys(token.text for token in tokens(command) if len(token.text) > 1
                              and token.text != "::" and token.text.startswith(("$", ":", "@"))))


@pytest.mark.parametrize("command", COMMANDS)
def test_shortcut_gives_the_tokenizer_result(command: str) -> None:
    """Commands with and without the three prefix characters give the tokenizer result."""
    assert named_slots(command) == tokenizer_slots(command)


def test_commands_without_prefix_characters_have_no_names() -> None:
    """The shortcut applies only when the command has none of the three characters."""
    assert named_slots("SELECT a FROM t WHERE b = 'x'") == []
    assert named_slots("SELECT a FROM t WHERE b = $x") == ["$x"]


def test_commands_without_prefix_characters_skip_the_tokenizer(monkeypatch: pytest.MonkeyPatch) -> None:
    """Corpus loading relies on the shortcut: such a command must not reach the tokenizer."""
    def refuse(command: str) -> list[object]:
        """Fail the test when the shortcut does not apply."""
        raise AssertionError(f"tokenizer called for {command!r}")

    monkeypatch.setattr(upstream_bindings, "tokens", refuse)
    assert named_slots("CREATE TABLE t(a, b DEFAULT 'x')") == []
