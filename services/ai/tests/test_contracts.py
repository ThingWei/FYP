from fastapi.testclient import TestClient
from app.main import app
client = TestClient(app)
def test_health(): assert client.get('/health').json()['status'] == 'ok'
def test_document_contract():
    response = client.post('/verify/document', json={'image_url': 'fixture://identity.jpg', 'expected_type': 'mykad'})
    assert response.status_code == 200 and response.json()['confidence'] >= 0
def test_price_contract():
    payload = {'item_profile': {'category':'devices'}, 'similar_active_average':40, 'historical_completed_average':35, 'supply_demand_ratio':1, 'seasonal_day_factor':1, 'rental_duration_days':3, 'owner_trust_score':80}
    assert client.post('/recommend/price', json=payload).status_code == 200

