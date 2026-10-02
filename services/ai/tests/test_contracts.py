from fastapi.testclient import TestClient
from app.main import app
from app.services.pricing import _artifact
client = TestClient(app)
def test_health(): assert client.get('/health').json()['status'] == 'ok'
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
    payload = {'item_profile': {'category':'Devices'}, 'similar_active_average':40, 'historical_completed_average':35, 'supply_demand_ratio':1, 'seasonal_day_factor':1, 'rental_duration_days':3, 'owner_trust_score':80}
    response = client.post('/recommend/price', json=payload)
    assert response.status_code == 200
    result = response.json()
    assert result['available'] is True
    assert result['suggested_daily_price'] > 0
    assert result['lower_bound'] <= result['suggested_daily_price'] <= result['upper_bound']
    assert result['evaluation']['dataset'] == 'deterministic-synthetic-v1'
    assert result['evaluation']['mae'] > 0

