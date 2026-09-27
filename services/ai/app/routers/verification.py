from fastapi import APIRouter

from ..schemas import VerificationRequest, VerificationResponse
from ..services.adapters import ImageIntelligenceService

router = APIRouter(prefix='/verify', tags=['verification'])
service = ImageIntelligenceService()


@router.post('/document', response_model=VerificationResponse)
def verify_document(request: VerificationRequest):
    return service.verify_document(request)


@router.post('/item', response_model=VerificationResponse)
def verify_item(request: VerificationRequest):
    return service.verify_item(request)
