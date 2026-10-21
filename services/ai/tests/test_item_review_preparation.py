import hashlib
import json

import pytest

from app.training import prepare_item_review as review
from test_item_risk_preparation import dataset


def test_review_pack_contains_only_metadata_and_honest_22_domain_coverage(tmp_path):
    config = dataset(tmp_path / 'source')
    before = {p: hashlib.sha256(p.read_bytes()).hexdigest()
              for p in config.parent.rglob('*') if p.is_file()}
    output = tmp_path / 'review'
    report = review.prepare(config, output)
    assert report['sourceGroups'] == 24 and report['plannedImages'] == 96
    assert report['generatedImages'] == 0 and not report['trained']
    assert not report['sourcePermissionAcknowledgedByCaller']
    assert not report['inferencePerformed']
    assert report['independentlyReviewedCases'] == 0
    assert json.loads((output / 'reviewed_cases.json').read_text()) == []
    slots = json.loads((output / 'collection_template.json').read_text())
    assert len(slots) == 198
    assert len({(s['category'], s['subcategory']) for s in slots}) == 22
    assert all(s['path'] is None and not s['boxes'] and not s['reviewed'] and
               not s['permissionConfirmed'] and s['label'] is None for s in slots)
    assert sum(s['expectation'] == 'target_present' for s in slots) == 88
    assert sum(s['expectation'] == 'detail_only' for s in slots) == 44
    assert sum(s['expectation'] == 'target_absent' for s in slots) == 66
    coverage = json.loads((output / 'coverage.json').read_text())
    assert len(coverage) == 22
    books = [row for row in coverage if row['category'] == 'books']
    assert next(r for r in books if r['subcategory'] == 'other books')['sourceAnnotatedTestCases'] == 8
    assert all(r['sourceAnnotatedTestCases'] == 0 for r in books if r['subcategory'] != 'other books')
    assert all(r['independentlyReviewedCases'] == 0 for r in coverage)
    assert all(r['reviewStatus'] == 'source_annotation_only_not_independent_review'
               for r in json.loads((output / 'source_test_annotations.json').read_text()))
    assert all(p.suffix in ('.json', '.md') for p in output.rglob('*'))
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() == digest for p, digest in before.items())
    assert 'attribution' in (output / 'README.md').read_text()


def test_review_preserves_existing_drafts_and_rejects_bad_limits(tmp_path):
    config = dataset(tmp_path / 'source')
    output = tmp_path / 'review'
    output.mkdir()
    draft = output / 'reviewed_cases.json'
    draft.write_text('[{"private_draft": true}]')
    with pytest.raises(ValueError, match='never overwritten'):
        review.prepare(config, output)
    assert draft.read_text() == '[{"private_draft": true}]'
    with pytest.raises(ValueError, match='1-100'):
        review.prepare(config, tmp_path / 'invalid', per_class=101)
    assert not (tmp_path / 'invalid').exists()


def test_cli_rejects_public_output_before_reading_sources(tmp_path, monkeypatch):
    monkeypatch.setattr('sys.argv', ['prepare_item_review', 'missing.yaml', '--output', str(tmp_path)])
    with pytest.raises(SystemExit):
        review.main()
