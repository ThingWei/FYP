import os
from pathlib import Path

from fastapi import FastAPI

from .routers.recommendation import router as recommendation_router
from .routers.verification import router as verification_router
from .services.pricing import _artifact as pricing_artifact

app = FastAPI(title='RentHub AI Service', version='2.0.0')


@app.get('/health')
def health():
    price_bundle, price_path, price_error = pricing_artifact()
    artifacts = {
        'price_model': price_bundle is not None,
        'recommendation_model': Path(
            os.getenv('RECOMMENDATION_MODEL_PATH', 'models/recommendation_svd.pkl')
        ).is_file(),
        'item_detector': Path(os.getenv('YOLO_MODEL_PATH', 'models/item_yolo.pt')).is_file(),
        'image_risk_model': Path(
            os.getenv('IMAGE_RISK_MODEL_PATH', 'models/image_risk_efficientnet.pt')
        ).is_file(),
        'easyocr_models': Path(os.getenv('EASYOCR_MODEL_DIR', 'models/easyocr')).is_dir(),
    }
    return {
        'status': 'ok',
        'model_mode': 'artifact-backed',
        'artifacts': artifacts,
        'ready_artifact_count': sum(artifacts.values()),
        'required_artifact_count': len(artifacts),
        'price_model_status': {
            'compatible': price_bundle is not None,
            'path': str(price_path),
            'error': price_error,
        },
    }


app.include_router(verification_router)
app.include_router(recommendation_router)
