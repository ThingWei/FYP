from fastapi import APIRouter
from ..schemas import VerificationRequest, VerificationResponse
from ..services.adapters import PlaceholderVerificationAdapter
router = APIRouter(prefix='/verify', tags=['verification'])
@router.post('/document', response_model=VerificationResponse)
def verify_document(request: VerificationRequest): return PlaceholderVerificationAdapter('document').verify(request)
@router.post('/item', response_model=VerificationResponse)
def verify_item(request: VerificationRequest): return PlaceholderVerificationAdapter('item').verify(request)

