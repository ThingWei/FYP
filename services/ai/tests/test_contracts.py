import os

from fastapi.testclient import TestClient
from app.main import app
from app.services.pricing import _artifact
client = TestClient(app)


def price_payload():
    return {
        'schema_version': 'renthub-price-v2',
        'item_profile': {
            'category': 'Devices', 'subcategory': 'Cameras',
            'condition': 'Excellent', 'brand': 'Sony',
            'product_model': 'Alpha A7', 'state': 'Kuala Lumpur',
            'item_age_years': 2,
        },
        'market_evidence': {
            'comparable_active_count': 8, 'comparable_active_median': 85,
            'comparable_active_mean': 87, 'comparable_active_iqr': 12,
            'historical_rental_count': 12, 'historical_rental_median': 82,
            'historical_rental_mean': 83, 'historical_rental_iqr': 9,
            'market_freshness_days': 5, 'demand_supply_ratio': 1.5,
        },
        'rental_duration_days': 3, 'owner_trust_score': 80,
        'owner_average_rating': 4.5, 'owner_completed_rentals': 20,
        'prediction_month': 10,
    }


def test_health(): assert client.get('/health').json()['status'] == 'ok'


def test_price_request_rejects_incompatible_schema_version():
    payload = price_payload()
    payload['schema_version'] = 'renthub-price-v1'
    response = client.post('/recommend/price', json=payload)
    assert response.status_code == 422
def test_document_contract():
    response = client.post('/verify/document', json={'image_url': 'fixture://identity.jpg', 'expected_type': 'mykad'})
    assert response.status_code == 200
    assert response.json()['outcome'] == 'unavailable'
    assert response.json()['confidence'] == 0
def test_item_requires_three_decodable_images():
    response = client.post('/verify/item', json={'images': [], 'expected_category': 'Devices'})
    assert response.status_code == 200
    assert response.json()['outcome'] == 'rejected'
def test_price_contract():
    _artifact.cache_clear()
    payload = price_payload()
    response = client.post('/recommend/price', json=payload)
    assert response.status_code == 200
    result = response.json()
    assert result['available'] is True
    assert result['suggested_daily_price'] > 0
    assert result['lower_bound'] <= result['suggested_daily_price'] <= result['upper_bound']
    assert result['currency'] == 'MYR'
    assert result['model_source'] in {'global_xgboost', 'category_xgboost'}
    assert result['confidence_label'] in {'low', 'medium', 'high'}
    assert result['evaluation']['globalModel']['mae'] > 0


def test_price_contract_handles_supported_categories_and_unknown_values():
    for category in ['Books', 'Clothing', 'Devices', 'Equipment', 'Vehicles']:
        payload = price_payload()
        payload['item_profile']['category'] = category
        response = client.post('/recommend/price', json=payload)
        assert response.status_code == 200
        result = response.json()
        assert result['available'] is True
        assert result['suggested_daily_price'] > 0
        assert result['lower_bound'] <= result['suggested_daily_price'] <= result['upper_bound']

    unknown = price_payload()
    unknown['item_profile'].update({
        'category': 'Musical Instruments',
        'brand': '',
        'product_model': '',
    })
    result = client.post('/recommend/price', json=unknown).json()
    assert result['available'] is True
    assert result['model_source'] == 'global_xgboost'
    assert any('not represented' in warning for warning in result['warnings'])


def test_price_confidence_decreases_when_market_evidence_is_sparse():
    strong = client.post('/recommend/price', json=price_payload()).json()
    sparse_payload = price_payload()
    sparse_payload['market_evidence'] = {}
    sparse = client.post('/recommend/price', json=sparse_payload).json()
    assert sparse['confidence'] < strong['confidence']
    assert any('No matching completed-rental' in warning for warning in sparse['warnings'])


def test_price_missing_artifact_is_explicit(tmp_path):
    previous = os.environ.get('PRICE_MODEL_PATH')
    os.environ['PRICE_MODEL_PATH'] = str(tmp_path / 'missing.joblib')
    _artifact.cache_clear()
    try:
        response = client.post('/recommend/price', json={
            'item_profile': {'category': 'Books'},
            'market_evidence': {},
            'rental_duration_days': 1,
            'owner_trust_score': 50,
        })
        assert response.status_code == 200
        result = response.json()
        assert result['available'] is False
        assert result['model_source'] == 'unavailable'
        assert result['suggested_daily_price'] is None
    finally:
        if previous is None:
            os.environ.pop('PRICE_MODEL_PATH', None)
        else:
            os.environ['PRICE_MODEL_PATH'] = previous
        _artifact.cache_clear()


def test_price_rejects_invalid_duration():
    response = client.post('/recommend/price', json={
        'item_profile': {'category': 'Devices'},
        'rental_duration_days': 0,
        'owner_trust_score': 50,
    })
    assert response.status_code == 422

