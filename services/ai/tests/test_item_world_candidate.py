"""Candidate policy and compatibility tests; not real-photo model evaluation."""
import hashlib
from pathlib import Path
from types import SimpleNamespace

import pytest

from app.services import item_world as world, item_verification as items
from app.training.prepare_item_world import output_path, prepare
from app.training.evaluate_item_recognition import with_world_candidate


def test_baseline_hash_and_prompts_remain_compatible_with_the_active_artifact():
    assert len(world.PROMPTS) == 66  # Two book prompts map to one canonical label.
    assert len({label for _, label in world.PROMPTS}) == 65
    assert world.prompts_for() == world.PROMPTS
    import json
    assert world.vocabulary_hash() == hashlib.sha256(json.dumps(world.PROMPTS, separators=(',', ':')).encode()).hexdigest()
    assert world.prompts_for(world.EXPANDED_PROFILE)[:len(world.PROMPTS)] == world.PROMPTS
    assert world.vocabulary_hash(world.EXPANDED_PROFILE) != world.vocabulary_hash()
    with pytest.raises(ValueError, match='Unknown'):
        world.prompts_for('arbitrary_unreviewed_profile')


def test_expanded_candidate_uses_concrete_targets_and_keeps_competing_context():
    prompts = world.prompts_for(world.EXPANDED_PROFILE)
    labels = [label for _, label in prompts]
    from collections import Counter
    assert {label: count for label, count in Counter(labels).items() if count > 1} == {'book': 2}
    assert {'computer monitor', 'mouse', 'keyboard', 'vr headset', 'camping tent', 'tripod',
            'mobility scooter', 'hanfu', 'raincoat', 'screen', 'paper', 'illustration'} <= set(labels)
    assert not {'power tool', 'formal wear', 'traditional costume'} & set(labels)
    detector = SimpleNamespace(names=labels)
    rows = items.coverage_matrix([(detector, world.SOURCE, 'candidate')])
    missing = [kind['productType'] for row in rows for kind in row['productTypes'] if not kind['matchingLabels']]
    assert sorted(missing) == ['formal_wear', 'power_tool', 'traditional_costume']
    assert all(not row['allProductsCovered'] for row in rows)


def test_expanded_preparation_requires_separate_output_before_loading_or_downloading():
    with pytest.raises(ValueError, match='isolated candidate'):
        prepare(profile=world.EXPANDED_PROFILE)


def test_candidate_outputs_cannot_replace_active_artifacts_or_existing_work(tmp_path, monkeypatch):
    monkeypatch.setattr(world, 'ROOT', tmp_path)
    active = tmp_path / 'models/item_world_offline.pt'
    monkeypatch.setattr(world, 'artifact_path', lambda: active)
    with pytest.raises(ValueError, match='separate output'):
        output_path(active)
    with pytest.raises(ValueError, match='separate output'):
        output_path(tmp_path / 'outside.pt')
    candidate = tmp_path / '.data/candidates/round-1/model.pt'
    assert output_path(candidate) == candidate
    candidate.parent.mkdir(parents=True)
    for occupied in [candidate, candidate.with_suffix('.report.json'), candidate.with_name('model.pending.pt')]:
        occupied.write_bytes(b'prior work')
        with pytest.raises(ValueError, match='already exists'):
            output_path(candidate)
        assert occupied.read_bytes() == b'prior work'
        occupied.unlink()


def test_evaluation_candidate_swaps_world_only_and_does_not_change_runtime(monkeypatch, tmp_path):
    monkeypatch.setattr(world, 'ROOT', tmp_path)
    candidate = tmp_path / '.data/candidates/round-1/model.pt'
    candidate.parent.mkdir(parents=True)
    candidate.touch()
    model = object()
    monkeypatch.setattr(world, 'load_world', lambda *_: model)
    original = [(object(), 'configured_item_model', 'custom.pt'), (object(), world.SOURCE, 'old.pt')]
    active = world.artifact_path()
    result = with_world_candidate(original, candidate)
    assert result == [original[0], (model, world.SOURCE, 'model.pt')]
    assert len(original) == 2 and original[1][2] == 'old.pt'
    assert world.artifact_path() == active
    with pytest.raises(ValueError, match='separate candidate'):
        with_world_candidate(original, tmp_path / 'unrelated.pt')


def test_optional_prepared_candidate_loads_with_no_network_or_runtime_prompt_encoding(monkeypatch):
    path = world.ROOT / '.data/candidates/item-world-expanded-v2/model.pt'
    if not path.is_file():
        pytest.skip('Prepared candidate is local and intentionally not committed')
    import requests
    import urllib.request
    import numpy as np
    import sys
    def forbidden(*_, **__):
        pytest.fail('Candidate inference must not download or encode prompts')
    monkeypatch.setattr(requests.sessions.Session, 'request', forbidden)
    monkeypatch.setattr(urllib.request, 'urlopen', forbidden)
    monkeypatch.setitem(sys.modules, 'clip', None)
    model = world.load_world(path, path.stat().st_mtime_ns)
    assert model.ckpt['renthub_item_world']['profile'] == world.EXPANDED_PROFILE
    assert len(model.names) == len(world.EXPANDED_PROMPTS)
    monkeypatch.setattr(model, 'set_classes', forbidden)
    result = model.predict(np.full((320, 320, 3), 128, dtype=np.uint8),
                           conf=items.THRESHOLD, verbose=False, device='cpu', max_det=20)
    assert len(result) == 1
    assert len(result[0].boxes) == 0


def test_optional_candidate_rejects_unknown_profile_or_mismatched_hash(monkeypatch):
    path = world.ROOT / '.data/candidates/item-world-expanded-v2/model.pt'
    if not path.is_file():
        pytest.skip('Prepared candidate is local and intentionally not committed')
    import ultralytics
    model = world.load_world(path, path.stat().st_mtime_ns)
    original = model.ckpt['renthub_item_world']
    monkeypatch.setattr(ultralytics, 'YOLOWorld', lambda _: model)
    try:
        for offset, metadata in enumerate([
            {**original, 'profile': 'unreviewed_profile'},
            {**original, 'vocabularyHash': 'incorrect'},
        ], start=1):
            model.ckpt['renthub_item_world'] = metadata
            with pytest.raises(ValueError):
                world.load_world(path, path.stat().st_mtime_ns + offset)
    finally:
        model.ckpt['renthub_item_world'] = original
