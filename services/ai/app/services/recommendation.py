import os
from functools import lru_cache
from pathlib import Path

from ..schemas import ItemRecommendationRequest, Recommendation, UserInteraction


CONTENT_WEIGHT = 0.6
COLLABORATIVE_WEIGHT = 0.4
INTERACTION_PRECEDENCE = {
    'saved': 1,
    'booking': 2,
    'completed_rental': 3,
    'published_review': 4,
    'synthetic_preference': 1,
}


def _clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


@lru_cache(maxsize=1)
def _collaborative_model():
    artifact = Path(
        os.getenv('RECOMMENDATION_MODEL_PATH', 'models/recommendation_svd.pkl'),
    )
    if not artifact.is_file():
        return None
    try:
        from surprise import dump

        _, model = dump.load(str(artifact))
        if not hasattr(model, 'predict') or not hasattr(model, 'trainset'):
            return None
        return model
    # A stale/corrupt pickle or dependency-version mismatch must degrade to the
    # live/content paths rather than taking down discovery.  This boundary does
    # not hide request or scoring defects because it wraps artifact loading only.
    except Exception:
        return None


def _canonical_interactions(
    interactions: list[UserInteraction],
) -> list[UserInteraction]:
    unique: dict[tuple[str, str], UserInteraction] = {}
    for interaction in interactions:
        key = (interaction.user_id, interaction.item_id)
        existing = unique.get(key)
        if existing is None:
            unique[key] = interaction
            continue
        next_precedence = INTERACTION_PRECEDENCE[interaction.interaction_type]
        existing_precedence = INTERACTION_PRECEDENCE[existing.interaction_type]
        next_time = interaction.observed_at.timestamp() if interaction.observed_at else 0
        existing_time = existing.observed_at.timestamp() if existing.observed_at else 0
        if (
            next_precedence > existing_precedence
            or next_precedence == existing_precedence and next_time > existing_time
        ):
            unique[key] = interaction
    return list(unique.values())


def _live_collaborative_model(interactions: list[UserInteraction]):
    if (
        len(interactions) < 10
        or len({item.user_id for item in interactions}) < 2
        or len({item.item_id for item in interactions}) < 2
    ):
        return None
    try:
        import pandas as pd
        from surprise import Dataset, Reader, SVD
    except ImportError:
        return None
    frame = pd.DataFrame([
        {
            'user_id': item.user_id,
            'item_id': item.item_id,
            'rating': item.rating,
        }
        for item in interactions
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
        return model.trainset.knows_user(
            model.trainset.to_inner_uid(user_id),
        ) and model.trainset.knows_item(model.trainset.to_inner_iid(item_id))
    except ValueError:
        return False


def _reason(*, has_history: bool, has_content_profile: bool, collaborative: bool):
    if collaborative:
        return 'Personalized from your marketplace activity and similar listings'
    if has_content_profile:
        return 'Similar to listings you saved, booked, completed, or reviewed'
    if has_history:
        return 'Popular active listings related to your current marketplace context'
    return 'Popular and highly rated active marketplace listings'


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
            ' '.join(filter(None, [
                candidate.title,
                candidate.category,
                candidate.subcategory,
                candidate.brand,
                candidate.product_model,
                candidate.description,
                candidate.location,
                candidate.condition,
            ]))
            for candidate in candidates
        ]
        matrix = TfidfVectorizer(
            stop_words='english',
            ngram_range=(1, 2),
        ).fit_transform(documents)
        canonical = _canonical_interactions(request.interactions)
        user_interactions = {
            item.item_id: item
            for item in canonical
            if item.user_id == request.user_id
        }
        profile_indexes = [
            index
            for index, item in enumerate(candidates)
            if item.item_id in user_interactions
        ]
        if profile_indexes:
            weights = [[
                user_interactions[candidates[index].item_id].rating / 5
            ] for index in profile_indexes]
            # scipy returns ``numpy.matrix`` for sparse means.  Newer
            # scikit-learn versions intentionally reject that legacy type, so
            # expose the profile as a regular two-dimensional ndarray.
            profile = matrix[profile_indexes].multiply(weights).mean(axis=0).A
            content_scores = cosine_similarity(profile, matrix).flatten().tolist()
        else:
            maximum_popularity = max(
                (item.popularity for item in candidates),
                default=1,
            ) or 1
            content_scores = [
                _clamp(
                    (item.rating / 5) * 0.7
                    + (item.popularity / maximum_popularity) * 0.3,
                )
                for item in candidates
            ]

        artifact_model = _collaborative_model()
        live_model = _live_collaborative_model(canonical)
        has_history = bool(user_interactions)
        output = []
        for index, candidate in enumerate(candidates):
            collaborative_personalized = False
            if artifact_model is not None and _model_knows(
                artifact_model,
                request.user_id,
                candidate.item_id,
            ):
                collaborative = _clamp(
                    (
                        float(
                            artifact_model.predict(
                                request.user_id,
                                candidate.item_id,
                            ).est,
                        )
                        - 1
                    ) / 4,
                )
                adapter = 'hybrid-svd-cosine-v1'
                collaborative_personalized = True
            elif live_model is not None and _model_knows(
                live_model,
                request.user_id,
                candidate.item_id,
            ):
                collaborative = _clamp(
                    (
                        float(
                            live_model.predict(
                                request.user_id,
                                candidate.item_id,
                            ).est,
                        )
                        - 1
                    ) / 4,
                )
                adapter = 'hybrid-live-svd-cosine-v1'
                collaborative_personalized = True
            else:
                collaborative = _clamp(candidate.rating / 5)
                adapter = 'content-cosine-with-popularity-fallback-v1'
            content = _clamp(float(content_scores[index]))
            score = _clamp(
                CONTENT_WEIGHT * content
                + COLLABORATIVE_WEIGHT * collaborative,
            )
            output.append(Recommendation(
                item_id=candidate.item_id,
                score=round(score, 4),
                content_score=round(content, 4),
                collaborative_score=round(collaborative, 4),
                reason=_reason(
                    has_history=has_history,
                    has_content_profile=bool(profile_indexes),
                    collaborative=collaborative_personalized,
                ),
                adapter=adapter,
            ))
        return sorted(output, key=lambda item: item.score, reverse=True)[:request.limit]
