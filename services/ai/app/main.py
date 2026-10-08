import os
from pathlib import Path

from fastapi import FastAPI

from .routers.recommendation import router as recommendation_router
from .routers.verification import router as verification_router
from .services.pricing import _artifact as pricing_artifact
from .services.mykad_field_risk import availability as mykad_field_availability
from .services.image_intelligence import DOCUMENT_FRAME_CONTRACT
from .services.item_verification import CONTRACT as ITEM_CONTRACT, models_status

app = FastAPI(title='RentHub AI Service', version='2.0.0')


@app.get('/health')
def health():
    price_bundle, price_path, price_error = pricing_artifact()
    field_status = mykad_field_availability()
    _, _, item_status = models_status()
    artifacts = {
        'price_model': price_bundle is not None,
        'recommendation_model': Path(
            os.getenv('RECOMMENDATION_MODEL_PATH', 'models/recommendation_svd.pkl')
        ).is_file(),
        'item_detector': item_status['detectorAvailable'],
        'image_risk_model': item_status['riskClassifierAvailable'],
        'document_detector': Path(
            os.getenv('DOCUMENT_YOLO_MODEL_PATH', 'models/document_yolo.pt')
        ).is_file(),
        'document_risk_model': Path(
            os.getenv(
                'DOCUMENT_RISK_MODEL_PATH',
                'models/document_risk_efficientnet.pt',
            )
        ).is_file(),
        'easyocr_models': Path(os.getenv('EASYOCR_MODEL_DIR', 'models/easyocr')).is_dir(),
        'mykad_field_detector': field_status['detectorPresent'],
        'mykad_field_risk_model': field_status['classifierPresent'],
    }
    return {
        'status': 'ok',
        'document_frame_contract': DOCUMENT_FRAME_CONTRACT,
        'item_verification_contract': ITEM_CONTRACT,
        'item_verification_status': item_status,
        'model_mode': 'artifact-backed',
        'artifacts': artifacts,
        'ready_artifact_count': sum(artifacts.values()),
        'required_artifact_count': len(artifacts),
        'mykad_field_risk_status': field_status,
        'price_model_status': {
            'compatible': price_bundle is not None,
            'path': str(price_path),
            'error': price_error,
        },
    }


app.include_router(verification_router)
app.include_router(recommendation_router)
