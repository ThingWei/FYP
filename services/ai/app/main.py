from fastapi import FastAPI

from .routers.recommendation import router as recommendation_router
from .routers.verification import router as verification_router

app = FastAPI(title='RentHub AI Service', version='2.0.0')


@app.get('/health')
def health():
    return {'status': 'ok', 'model_mode': 'artifact-backed'}


app.include_router(verification_router)
app.include_router(recommendation_router)
