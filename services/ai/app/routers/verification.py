from fastapi import APIRouter

from ..schemas import (
    DocumentFrameRequest,
    DocumentFrameResponse,
    VerificationRequest,
    VerificationResponse,
)
from ..services.adapters import ImageIntelligenceService

router = APIRouter(prefix='/verify', tags=['verification'])
service = ImageIntelligenceService()


@router.post('/document', response_model=VerificationResponse)
def verify_document(request: VerificationRequest):
    return service.verify_document(request)


@router.post('/document-frame', response_model=DocumentFrameResponse)
def verify_document_frame(request: DocumentFrameRequest):
    return service.inspect_document_frame(request)


@router.post('/item', response_model=VerificationResponse)
def verify_item(request: VerificationRequest):
    return service.verify_item(request)
