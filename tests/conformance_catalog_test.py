"""Whole-family selection must account for the pinned archive and declared non-goals."""

import os
from pathlib import Path
import shutil

import pytest

from conformance.upstream_catalog import catalog_patterns, file_exclusion_reasons, validate_source_files

pytestmark = [pytest.mark.integration, pytest.mark.conformance]


@pytest.fixture
def upstream() -> Path:
    """The upstream Nix target supplies the exact source archive used by its real Tcl fixture."""
    return Path(os.environ['CONFORMANCE_UPSTREAM'])


def test_catalog_accounts_for_all_pinned_feature_families(upstream: Path) -> None:
    """Every declared family member is included, with file-level exclusions still visible."""
    validate_source_files(upstream)
    names = catalog_patterns()
    assert len(names) == len(set(names)) == 171
    assert {'fkey8.test', 'selectH.test', 'triggerG.test', 'aggorderby.test', 'date5.test',
            'json502.test', 'cast.test', 'trans3.test', 'insert5.test', 'update2.test', 'delete4.test'} <= set(names)
    assert file_exclusion_reasons('fkey_malloc.test') == ['allocation fault injection']
    assert file_exclusion_reasons('delete_db.test') == ['file-level database deletion']
    assert file_exclusion_reasons('fkey8.test') == []


@pytest.mark.parametrize('damage', ['missing', 'extra'])
def test_changed_family_membership_is_refused(upstream: Path, tmp_path: Path, damage: str) -> None:
    """A newly omitted or added family source cannot silently change the selection denominator."""
    copied = tmp_path / 'upstream'
    (copied / 'test').mkdir(parents=True)
    for filename in catalog_patterns():
        shutil.copyfile(upstream / 'test' / filename, copied / 'test' / filename)
    if damage == 'missing':
        (copied / 'test/fkey8.test').unlink()
    else:
        (copied / 'test/selectZ.test').write_text('# unexpected source\n')
    with pytest.raises(ValueError, match='pinned feature families'):
        validate_source_files(copied)
