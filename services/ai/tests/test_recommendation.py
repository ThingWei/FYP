import json

import pytest

from app.schemas import ItemRecommendationRequest, UserInteraction
from app.services.recommendation import (
    CONTENT_WEIGHT,
    COLLABORATIVE_WEIGHT,
    HybridRecommendationService,
    _canonical_interactions,
    _collaborative_model,
)
from app.training.recommendation_dataset import prepare_recommendation_dataset
from app.training.train_recommendation import (
    temporal_user_split,
    train_recommendation_artifact,
)


def candidate(
    item_id,
    title,
    category,
    *,
    subcategory='',
    brand='',
    product_model='',
    rating=4,
    popularity=1,
    available=True,
):
    return {
        'item_id': item_id,
        'title': title,
        'category': category,
        'subcategory': subcategory,
        'brand': brand,
        'product_model': product_model,
        'description': title,
        'location': 'Kuala Lumpur',
        'condition': 'Excellent',
        'price': 50,
        'rating': rating,
        'popularity': popularity,
        'available': available,
    }


@pytest.fixture(autouse=True)
def missing_artifact(monkeypatch, tmp_path):
    monkeypatch.setenv(
        'RECOMMENDATION_MODEL_PATH',
        str(tmp_path / 'missing-recommendation.pkl'),
    )
    _collaborative_model.cache_clear()
    yield
    _collaborative_model.cache_clear()


def test_content_profile_ranks_a_new_camera_above_unrelated_bicycle():
    request = ItemRecommendationRequest.model_validate({
        'user_id': 'u-camera',
        'candidates': [
            candidate(
                'l-camera-saved', 'Canon EOS camera kit', 'Devices',
                subcategory='Cameras', brand='Canon', product_model='EOS R50',
            ),
            candidate(
                'l-camera-new', 'Canon mirrorless camera', 'Devices',
                subcategory='Cameras', brand='Canon', product_model='EOS R6',
            ),
            candidate(
                'l-bicycle', 'Giant mountain bicycle', 'Vehicles',
                subcategory='Bicycles', brand='Giant', product_model='Talon 2',
            ),
        ],
        'interactions': [{
            'user_id': 'u-camera',
            'item_id': 'l-camera-saved',
            'rating': 4.5,
            'interaction_type': 'completed_rental',
        }],
    })

    results = {
        item.item_id: item
        for item in HybridRecommendationService().recommend(request)
    }
    assert results['l-camera-new'].content_score > results['l-bicycle'].content_score
    assert 'saved, booked, completed, or reviewed' in results['l-camera-new'].reason


def test_new_user_uses_truthful_popularity_fallback_and_60_40_score():
    request = ItemRecommendationRequest.model_validate({
        'user_id': 'new-user',
        'candidates': [candidate(
            'l-book', 'The Hobbit', 'Books', rating=5, popularity=8,
        )],
    })
    result = HybridRecommendationService().recommend(request)[0]
    expected = (
        CONTENT_WEIGHT * result.content_score
        + COLLABORATIVE_WEIGHT * result.collaborative_score
    )
    assert result.score == pytest.approx(expected, abs=0.0002)
    assert result.adapter == 'content-cosine-with-popularity-fallback-v1'
    assert result.reason == 'Popular and highly rated active marketplace listings'
    assert 'history' not in result.reason.lower()


def test_corrupt_artifact_degrades_to_truthful_fallback(monkeypatch, tmp_path):
    artifact = tmp_path / 'corrupt.pkl'
    artifact.write_bytes(b'not a Surprise artifact')
    monkeypatch.setenv('RECOMMENDATION_MODEL_PATH', str(artifact))
    _collaborative_model.cache_clear()
    request = ItemRecommendationRequest.model_validate({
        'user_id': 'known-user',
        'candidates': [candidate('l-camera', 'Camera', 'Devices')],
        'interactions': [{
            'user_id': 'known-user',
            'item_id': 'l-camera',
            'rating': 3.5,
            'interaction_type': 'saved',
        }],
    })
    result = HybridRecommendationService().recommend(request)[0]
    assert result.adapter == 'content-cosine-with-popularity-fallback-v1'
    assert result.reason == (
        'Similar to listings you saved, booked, completed, or reviewed'
    )


def test_unavailable_listing_is_excluded_without_crashing_sparse_marketplace():
    request = ItemRecommendationRequest.model_validate({
        'user_id': 'new-user',
        'candidates': [
            candidate('l-active', 'Active drill', 'Equipment'),
            candidate(
                'l-inactive', 'Inactive drill', 'Equipment', available=False,
            ),
        ],
    })
    results = HybridRecommendationService().recommend(request)
    assert [item.item_id for item in results] == ['l-active']


def test_duplicate_interaction_uses_documented_confidence_precedence():
    canonical = _canonical_interactions([
        UserInteraction(
            user_id='u-1', item_id='l-1', rating=3.5,
            interaction_type='saved',
        ),
        UserInteraction(
            user_id='u-1', item_id='l-1', rating=4.5,
            interaction_type='completed_rental',
        ),
        UserInteraction(
            user_id='u-1', item_id='l-1', rating=2,
            interaction_type='published_review',
        ),
    ])
    assert len(canonical) == 1
    assert canonical[0].interaction_type == 'published_review'
    assert canonical[0].rating == 2


def test_live_svd_adapter_is_used_when_marketplace_interactions_are_sufficient():
    interactions = []
    for user in ['u-live', 'u-peer']:
        for index in range(5):
            interactions.append({
                'user_id': user,
                'item_id': f'l-{index}',
                'rating': 5 if index < 3 else 3,
                'interaction_type': 'booking',
            })
    request = ItemRecommendationRequest.model_validate({
        'user_id': 'u-live',
        'candidates': [
            candidate(f'l-{index}', f'Camera {index}', 'Devices')
            for index in range(5)
        ],
        'interactions': interactions,
    })
    results = HybridRecommendationService().recommend(request)
    assert results
    assert all(item.adapter == 'hybrid-live-svd-cosine-v1' for item in results)
    assert all('marketplace activity' in item.reason for item in results)


def test_saved_artifact_adapter_is_loaded_and_used(monkeypatch, tmp_path):
    train_recommendation_artifact(
        real_export=None,
        models_dir=tmp_path / 'models',
        metrics_dir=tmp_path / 'metrics',
        data_dir=tmp_path / 'data',
        synthetic_users=8,
        synthetic_items=12,
        synthetic_interactions_per_user=8,
    )
    monkeypatch.setenv(
        'RECOMMENDATION_MODEL_PATH',
        str(tmp_path / 'models' / 'recommendation_svd.pkl'),
    )
    _collaborative_model.cache_clear()
    request = ItemRecommendationRequest.model_validate({
        'user_id': 'synthetic-u-0',
        'candidates': [candidate(
            'synthetic-l-0', 'Camera body', 'Devices',
            subcategory='Cameras',
        )],
        'interactions': [{
            'user_id': 'synthetic-u-0',
            'item_id': 'synthetic-l-0',
            'rating': 4.5,
            'interaction_type': 'completed_rental',
        }],
    })
    result = HybridRecommendationService().recommend(request)[0]
    assert result.adapter == 'hybrid-svd-cosine-v1'
    assert 'marketplace activity' in result.reason


def test_content_fallback_accepts_all_renthub_marketplace_categories():
    request = ItemRecommendationRequest.model_validate({
        'user_id': 'new-user',
        'candidates': [
            candidate('device', 'Camera', 'Devices'),
            candidate('vehicle', 'Bicycle', 'Vehicles'),
            candidate('equipment', 'Power drill', 'Equipment'),
            candidate('book', 'Novel', 'Books'),
            candidate('clothing', 'Evening dress', 'Clothing'),
            candidate('service', 'Photography package', 'Services'),
        ],
    })
    results = HybridRecommendationService().recommend(request)
    assert {result.item_id for result in results} == {
        'device', 'vehicle', 'equipment', 'book', 'clothing', 'service',
    }
    assert all(
        result.adapter == 'content-cosine-with-popularity-fallback-v1'
        for result in results
    )


def test_dataset_labels_real_demo_and_synthetic_counts_separately(tmp_path):
    export = tmp_path / 'interactions.json'
    export.write_text(json.dumps({'rows': [
        {
            'userId': 'hashed-a', 'listingId': 'l-camera',
            'interactionType': 'saved', 'rating': 3.5,
            'observedAt': '2026-01-01T00:00:00Z',
            'sourceType': 'marketplace',
        },
        {
            'userId': 'hashed-b', 'listingId': 'l-bike',
            'interactionType': 'completed_rental', 'rating': 4.5,
            'observedAt': '2026-01-02T00:00:00Z',
            'sourceType': 'demo_seed',
        },
    ]}), encoding='utf-8')
    frame, summary = prepare_recommendation_dataset(
        export,
        synthetic_users=2,
        synthetic_items=6,
        synthetic_interactions_per_user=3,
    )
    assert len(frame) == 8
    assert summary['realMarketplaceInteractions'] == 1
    assert summary['demoSeedInteractions'] == 1
    assert summary['syntheticInteractions'] == 6


def test_temporal_split_has_no_user_listing_leakage():
    frame, _ = prepare_recommendation_dataset(
        None,
        synthetic_users=8,
        synthetic_items=20,
        synthetic_interactions_per_user=8,
    )
    train, test = temporal_user_split(frame)
    assert set(zip(train.user_id, train.item_id)).isdisjoint(
        set(zip(test.user_id, test.item_id)),
    )
    for user_id in test.user_id.unique():
        assert train.loc[train.user_id == user_id, 'observed_at'].max() <= (
            test.loc[test.user_id == user_id, 'observed_at'].min()
        )


def test_training_saves_reloadable_artifact_and_honest_ranking_metrics(tmp_path):
    metrics = train_recommendation_artifact(
        real_export=None,
        models_dir=tmp_path / 'models',
        metrics_dir=tmp_path / 'metrics',
        data_dir=tmp_path / 'data',
        synthetic_users=12,
        synthetic_items=24,
        synthetic_interactions_per_user=10,
    )
    assert (tmp_path / 'models' / 'recommendation_svd.pkl').is_file()
    assert metrics['rmse'] > 0
    assert metrics['mae'] > 0
    assert metrics['precisionAt5'] is not None
    assert metrics['recallAt5'] is not None
    assert metrics['provenance']['realMarketplaceInteractions'] == 0
    assert metrics['provenance']['syntheticInteractions'] == 120
