import os
from functools import lru_cache
from pathlib import Path

from ..schemas import ItemRecommendationRequest, Recommendation


def _clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


@lru_cache(maxsize=1)
def _collaborative_model():
    artifact = Path(os.getenv('RECOMMENDATION_MODEL_PATH', 'models/recommendation_svd.pkl'))
    if not artifact.is_file():
        return None
    from surprise import dump
    _, model = dump.load(str(artifact))
    return model


def _live_collaborative_model(request: ItemRecommendationRequest):
    unique = {
        (interaction.user_id, interaction.item_id): interaction.rating
        for interaction in request.interactions
    }
    if (
        len(unique) < 10
        or len({key[0] for key in unique}) < 2
        or len({key[1] for key in unique}) < 2
    ):
        return None
    try:
        import pandas as pd
        from surprise import Dataset, Reader, SVD
    except ImportError:
        return None
    frame = pd.DataFrame([
        {'user_id': key[0], 'item_id': key[1], 'rating': rating}
        for key, rating in unique.items()
    ])
    trainset = Dataset.load_from_df(
        frame[['user_id', 'item_id', 'rating']],
        Reader(rating_scale=(1, 5)),
    ).build_full_trainset()
    model = SVD(n_factors=40, n_epochs=20, random_state=42)
    model.fit(trainset)
    return model


def _model_knows(model, user_id: str, item_id: str) -> bool:
    try:
        return model.trainset.knows_user(model.trainset.to_inner_uid(user_id)) and model.trainset.knows_item(
            model.trainset.to_inner_iid(item_id)
        )
    except ValueError:
        return False


class HybridRecommendationService:
    def recommend(self, request: ItemRecommendationRequest) -> list[Recommendation]:
        candidates = [candidate for candidate in request.candidates if candidate.available]
        if not candidates:
            return []
        try:
            from sklearn.feature_extraction.text import TfidfVectorizer
            from sklearn.metrics.pairwise import cosine_similarity
        except ImportError as error:
            raise RuntimeError(f'scikit-learn is required: {error}') from error

        documents = [
            ' '.join([
                candidate.title,
                candidate.category,
                candidate.description,
                candidate.location,
                candidate.condition,
            ])
            for candidate in candidates
        ]
        matrix = TfidfVectorizer(stop_words='english', ngram_range=(1, 2)).fit_transform(documents)
        interactions = {
            item.item_id: item
            for item in request.interactions
            if item.user_id == request.user_id
        }
        profile_indexes = [
            index for index, item in enumerate(candidates) if item.item_id in interactions
        ]
        if profile_indexes:
            weights = [[interactions[candidates[index].item_id].rating / 5] for index in profile_indexes]
            profile = matrix[profile_indexes].multiply(weights).mean(axis=0)
            content_scores = cosine_similarity(profile, matrix).flatten().tolist()
        else:
            maximum_popularity = max((item.popularity for item in candidates), default=1) or 1
            content_scores = [
                _clamp((item.rating / 5) * 0.7 + (item.popularity / maximum_popularity) * 0.3)
                for item in candidates
            ]

        artifact_model = _collaborative_model()
        live_model = _live_collaborative_model(request)
        output = []
        for index, candidate in enumerate(candidates):
            if artifact_model is not None and _model_knows(
                artifact_model, request.user_id, candidate.item_id
            ):
                collaborative = _clamp(
                    (float(artifact_model.predict(request.user_id, candidate.item_id).est) - 1) / 4
                )
                adapter = 'hybrid-svd-cosine-v1'
            elif live_model is not None and _model_knows(
                live_model, request.user_id, candidate.item_id
            ):
                collaborative = _clamp(
                    (float(live_model.predict(request.user_id, candidate.item_id).est) - 1) / 4
                )
                adapter = 'hybrid-live-svd-cosine-v1'
            else:
                collaborative = _clamp(candidate.rating / 5)
                adapter = 'content-cosine-with-popularity-fallback-v1'
            content = _clamp(float(content_scores[index]))
            score = _clamp(0.6 * content + 0.4 * collaborative)
            reason = (
                'Similar to your saved, booked, or highly rated listings'
                if profile_indexes and content >= 0.35
                else 'Strong rating and marketplace activity for your context'
            )
            output.append(Recommendation(
                item_id=candidate.item_id,
                score=round(score, 4),
                content_score=round(content, 4),
                collaborative_score=round(collaborative, 4),
                reason=reason,
                adapter=adapter,
            ))
        return sorted(output, key=lambda item: item.score, reverse=True)[:request.limit]
