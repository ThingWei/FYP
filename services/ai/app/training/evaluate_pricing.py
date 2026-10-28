"""Forward-time, non-deploying pricing evaluation on reviewed local exports.

Comparable features are rebuilt by RentHub's shared Express evidence code using
only training-side history. No model, database or production metrics are written.
"""

import argparse
import hashlib
import json
import subprocess
import os
from pathlib import Path

import numpy as np
import pandas as pd

from .pricing_dataset import FEATURES, PROVENANCE_COLUMNS, REQUIRED_COLUMNS, validate_dataset
from .train_tabular_models import _baseline_predict, _metric_block, _pipeline, _sample_weights

ROOT = Path(__file__).resolve().parents[2]
WORKER = ROOT.parent / 'api/src/scripts/pricingEvaluationFeatures.js'
TARGETS = ('active_asking', 'external_asking_price', 'accepted_booking', 'completed_rental')


def load_observations(path):
    payload = json.loads(path.read_text(encoding='utf-8-sig'))
    rows = payload if isinstance(payload, list) else payload.get('rows', [])
    if not isinstance(rows, list) or len(rows) > 10000:
        raise ValueError('Expected at most 10000 observations')
    frame = pd.DataFrame(rows)
    coverage = payload.get('catalogCoverage', []) if isinstance(payload, dict) else []
    if not isinstance(coverage, list) or len(coverage) > 100 or any(
            not isinstance(domain, dict) or any(not isinstance(domain.get(key), str) or
                not domain[key].strip() or len(domain[key]) > 100 for key in ('category', 'subcategory'))
            for domain in coverage):
        raise ValueError('Invalid catalogue coverage metadata')
    if len({(d['category'], d['subcategory']) for d in coverage}) != len(coverage):
        raise ValueError('Duplicate catalogue coverage metadata')
    frame.attrs['catalog_coverage'] = coverage
    for column in REQUIRED_COLUMNS:
        if column not in frame:
            frame[column] = None
    if frame.empty:
        return frame
    validate_dataset(frame)  # Reject malformed provenance/targets/dates/duplicates, not silent cleanup.
    if frame[['category', 'subcategory', 'group_id']].isna().any().any():
        raise ValueError('Missing product grouping/category metadata')
    # Unknown values must not become zero, and input features cannot carry infinities.
    for name, minimum, maximum, whole in [('item_age_years', 0, 100, False),
                                          ('rental_duration_days', 1, 365, True)]:
        values = pd.to_numeric(frame[name], errors='coerce')
        supplied = frame[name].notna()
        invalid = supplied & (~np.isfinite(values) | (values < minimum) | (values > maximum))
        if whole:
            invalid |= supplied & (values != values.round())
        if invalid.any() or (whole and not supplied.all()):
            raise ValueError('Invalid pricing input feature')
        frame[name] = values
    return frame


def forward_split(frame, cutoff=None):
    observed = pd.to_datetime(frame.observed_at, utc=True, format='mixed')
    available = pd.to_datetime(frame.get('available_at', pd.Series(None, index=frame.index)),
                               utc=True, format='mixed', errors='coerce')
    external = frame.source_type == 'external_asking_price'
    # Missing acquisition/review time for an external quote is unknown, not assumed old.
    available = available.where(available.notna(), observed.where(~external))
    known = pd.concat([observed, available], axis=1).max(axis=1)
    known = known.where(~external | available.notna())
    timeline = sorted(known.dropna().unique())
    if cutoff is None:
        if len(timeline) < 2:
            return frame.iloc[:0].copy(), frame.iloc[:0].copy(), None
        cutoff = pd.Timestamp(timeline[min(len(timeline) - 1, int(len(timeline) * .7))])
    else:
        cutoff = pd.to_datetime(cutoff, utc=True)
    train = frame.loc[(known < cutoff) & (observed < cutoff)].copy()
    test = frame.loc[(observed >= cutoff) & known.notna()].copy()
    return train, test, cutoff.isoformat()


def forward_features(targets, history):
    columns = list(dict.fromkeys(FEATURES + PROVENANCE_COLUMNS +
                                ['observed_at', 'group_id', 'source_type', 'target_source', 'daily_price', 'location']))
    def records(frame):
        selected = frame[[c for c in columns if c in frame]].copy()
        # Historical owner aggregates in exports were built outside this fold.
        for name in ('owner_trust_score', 'owner_average_rating', 'owner_completed_rentals'):
            selected[name] = None
        return selected.astype(object).where(pd.notna(selected), None).to_dict('records')
    result = subprocess.run(['node', str(WORKER)],
        input=json.dumps({'targets': records(targets), 'history': records(history)}, allow_nan=False),
        capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise ValueError('Offline shared comparable-feature preparation unavailable')
    values = json.loads(result.stdout)
    if len(values) != len(targets):
        raise ValueError('Invalid comparable-feature response')
    rebuilt = targets.copy().reset_index(drop=True)
    for name in values[0] if values else []:
        rebuilt[name] = [row[name] for row in values]
    rebuilt['owner_trust_score'] = None
    return rebuilt


def cohort_metrics(test, predicted, baseline):
    report = {}
    for target in TARGETS:
        mask = (test.target_source == target).to_numpy()
        actual = test.loc[mask, 'daily_price']
        report[target] = ({'status': 'evaluated', 'samples': int(mask.sum()),
                           'candidate': _metric_block(actual, predicted[mask]),
                           'categoryMedianBaseline': _metric_block(actual, baseline[mask])}
                          if mask.any() else {'status': 'no_holdout', 'samples': 0,
                                              'candidate': None, 'categoryMedianBaseline': None})
    return report


def evaluate(path, *, cutoff=None, seed=42, pipeline_factory=_pipeline, mode='deployed', artifact_path=None):
    if mode not in ('deployed', 'candidate'):
        raise ValueError('Choose deployed or candidate evaluation explicitly')
    frame = load_observations(path)
    report = {'mode': 'evaluation_only', 'artifactWritten': False, 'seed': seed,
              'inputSha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'splitStrategy': 'global_forward_time_fixed_training_history',
              'status': 'insufficient_data', 'candidate': None, 'categoryMedianBaseline': None,
              'evaluationByTargetSource': {t: {'status': 'not_evaluated', 'samples': 0,
                                               'candidate': None, 'categoryMedianBaseline': None} for t in TARGETS},
              'limitations': ['Asking prices are not achieved rental prices',
                  'Small cohorts cannot validate market-wide accuracy',
                  'Current listing metadata is not a historical booking-profile snapshot',
                  'Chronological evaluation may include previously seen product identities',
                  'Owner history aggregates are excluded because fold-local history is unavailable',
                  'No live artifact comparison or automatic deployment is performed']}
    if frame.empty:
        report.update(inputRows=0, trainRows=0, testRows=0, modelMode=mode,
                      evidenceReadiness=evidence_readiness(frame, frame.attrs.get('catalog_coverage', [])))
        return frozen_evaluation(report, frame, frame, artifact_path) if mode == 'deployed' else report
    independent = frame.get('independent_evidence', pd.Series(False, index=frame.index)).eq(True)
    origin = frame.get('price_origin', pd.Series('unknown', index=frame.index))
    eligible = frame.loc[independent & ((frame.source_type.eq('external_asking_price') & origin.eq('external_reference')) |
        (frame.source_type.eq('real') & origin.eq('owner_entered') &
         ~frame.get('payment_simulated', pd.Series(False, index=frame.index)).eq(True)))].copy()
    report['evidenceReadiness'] = evidence_readiness(eligible, frame.attrs.get('catalog_coverage', []))
    report.update(inputRows=len(frame), excludedDemoSyntheticRows=len(frame) - len(eligible))
    report.update(modelMode=mode, excludedProvenanceRows=len(frame) - len(eligible),
                  excludedSourceCounts=frame.loc[~frame.index.isin(eligible.index)].source_type.value_counts().to_dict())
    train, test, split_at = forward_split(eligible, cutoff)
    report.update(trainRows=len(train), testRows=len(test), cutoff=split_at,
                  excludedLateOrUnknownRows=len(eligible) - len(train) - len(test),
                  trainingSources=train.source_type.value_counts().to_dict(),
                  holdoutTargets=test.target_source.value_counts().to_dict(),
                  seenHoldoutProductGroups=len(set(train.group_id) & set(test.group_id)))
    if mode == 'deployed':
        return frozen_evaluation(report, train, test, artifact_path)
    if len(train) < 20 or len(test) < 5:
        report['reason'] = 'Needs at least 20 earlier training rows and 5 later holdout rows; this is a technical minimum only'
        return report
    train_features, test_features = forward_features(train, train), forward_features(test, train)
    model = pipeline_factory(seed)
    model.fit(train_features[FEATURES], train_features.daily_price,
              model__sample_weight=_sample_weights(train_features))
    predicted = np.asarray(model.predict(test_features[FEATURES]))
    if not np.isfinite(predicted).all():
        raise ValueError('Candidate returned non-finite predictions')
    baseline = _baseline_predict(train_features, test_features)
    report.update(status='evaluated', candidate=_metric_block(test_features.daily_price, predicted),
                  categoryMedianBaseline=_metric_block(test_features.daily_price, baseline),
                  evaluationByTargetSource=cohort_metrics(test_features, predicted, baseline),
                  holdoutEvidenceTiers=test_features.active_comparable_tier.value_counts().to_dict())
    return report


def evidence_readiness(frame, coverage):
    """Aggregate gaps only; cohort size/field presence is never training permission."""
    expected = [(d['category'], d['subcategory']) for d in coverage]
    observed = list(frame[['category', 'subcategory']].drop_duplicates().itertuples(index=False, name=None)) if len(frame) else []
    domains = list(dict.fromkeys(expected + observed))
    rows = []
    for category, subcategory in domains:
        cohort = frame.loc[frame.category.eq(category) & frame.subcategory.eq(subcategory)] if len(frame) else frame
        count = len(cohort)
        conditions = cohort.get('condition', pd.Series(dtype=object)).isin(['Fair', 'Good', 'Very good', 'Excellent', 'Like New'])
        ages = pd.to_numeric(cohort.get('item_age_years', pd.Series(dtype=float)), errors='coerce')
        targets = cohort.get('target_source', pd.Series(dtype=object))
        origins = cohort.get('source_type', pd.Series(dtype=object))
        rows.append({'category': category, 'subcategory': subcategory, 'eligibleRows': count,
            'distinctProductGroups': int(cohort.group_id.nunique()) if count else 0,
            'askingPriceRows': int(targets.isin(['active_asking', 'external_asking_price']).sum()),
            'acceptedBookingRows': int((origins.eq('real') & targets.eq('accepted_booking')).sum()),
            'verifiedCompletedRentalRows': int((origins.eq('real') & targets.eq('completed_rental')).sum()),
            'withCondition': int(conditions.sum()), 'withItemAge': int(ages.notna().sum()),
            'withBothConditionAndItemAge': int((conditions & ages.notna()).sum()),
            'distinctKnownAges': int(ages.nunique()),
            'status': 'missing_evidence' if not count else 'evidence_requires_evaluation'})
    missing = sum(r['eligibleRows'] == 0 for r in rows)
    completed = sum(r['verifiedCompletedRentalRows'] for r in rows)
    gaps = []
    if not coverage:
        gaps.append('expected_catalogue_coverage_unknown_in_legacy_export')
    if missing:
        gaps.append('missing_subcategory_evidence')
    if not completed:
        gaps.append('no_verified_completed_rental_evidence')
    if sum(r['withCondition'] for r in rows) < len(frame):
        gaps.append('condition_values_missing_or_unknown')
    if sum(r['withItemAge'] for r in rows) < len(frame):
        gaps.append('item_age_values_missing_or_unknown')
    return {'expectedSubcategories': len(expected) if coverage else None, 'reportedSubcategories': len(rows),
        'subcategoriesWithEvidence': sum(r['eligibleRows'] > 0 for r in rows),
        'missingSubcategories': missing, 'verifiedCompletedRentalRows': completed, 'dataGaps': gaps,
        'candidateTrainingDecision': 'not_justified_by_current_data' if gaps else 'requires_separate_review',
        'automaticTrainingAllowed': False, 'rows': rows,
        'limitation': 'Field completeness and row counts do not establish independence, accuracy or learned age/condition effects.'}


def safe_metrics(actual, predicted):
    if not len(actual):
        return None
    values = _metric_block(actual, predicted)
    if len(actual) < 2 or np.var(actual) == 0:
        values['r2'] = None
    return values


def frozen_evaluation(report, history, targets, artifact_path=None):
    import joblib
    artifact = Path(artifact_path or os.getenv('PRICE_MODEL_PATH', str(ROOT / 'models/price_xgboost.joblib')))
    before = hashlib.sha256(artifact.read_bytes()).hexdigest()
    bundle = joblib.load(artifact)
    if bundle.get('schema_version') != 'renthub-price-v2' or bundle.get('feature_schema', {}).get('ordered') != FEATURES:
        raise ValueError('Deployed artifact feature schema mismatch')
    trained = pd.to_datetime(bundle.get('trained_at'), utc=True, errors='coerce')
    report.update(artifactSha256=before, modelVersion=bundle.get('model_version'),
                  artifactUnchanged=hashlib.sha256(artifact.read_bytes()).hexdigest() == before, deployedModel=None,
                  artifactWritten=False, candidate=None, trainingOverlapVerification='unknown_no_row_manifest',
                  accuracyClaim='diagnostic_only_not_independently_validated',
                  evaluationByCategory={}, evaluationBySubcategory={},
                  predictionCoverage={'eligibleTargets': len(targets), 'predictedTargets': 0, 'abstainedTargets': len(targets)})
    report['limitations'] = [note for note in report['limitations'] if 'No live artifact comparison' not in note]
    report['limitations'].append('The deployed artifact lacks a row-level training manifest; training overlap is unverified')
    if pd.isna(trained):
        report['reason'] = 'Artifact training time is unknown; safe historical evaluation is unsupported'
        return report
    dates = pd.to_datetime(targets.observed_at, utc=True, format='mixed') if len(targets) else pd.Series(dtype='datetime64[ns, UTC]')
    targets = targets.loc[dates > trained].copy()
    report['excludedPreTrainingTargets'] = int(len(dates) - len(targets))
    report['predictionCoverage'] = {'eligibleTargets': len(targets), 'predictedTargets': 0,
                                    'abstainedTargets': len(targets)}
    for field, key in [('target_source', 'evaluationByTargetSource'), ('category', 'evaluationByCategory'),
                       ('subcategory', 'evaluationBySubcategory')]:
        for value in targets[field].unique():
            count = int((targets[field] == value).sum())
            report[key][str(value)] = {'status': 'insufficient_data', 'samples': 0,
                'holdoutSamples': count, 'predictedTargets': 0, 'abstainedTargets': count,
                'deployedModel': None, 'categoryMedianBaseline': None}
    if history.empty or targets.empty:
        report['reason'] = 'No usable earlier history and post-training holdout; no candidate was fitted'
        return report
    features = forward_features(targets, history)
    mask = (features.comparable_active_count.fillna(0) + features.historical_rental_count.fillna(0)) > 0
    assessed = features.loc[mask].copy()
    report['predictionCoverage'] = {'eligibleTargets': len(targets), 'predictedTargets': len(assessed),
                                    'abstainedTargets': len(targets) - len(assessed)}
    if assessed.empty:
        report['reason'] = 'Holdout lacks compatible prior evidence; production would offer manual pricing'
        return report
    predicted = np.array([float(bundle.get('category_models', {}).get(row.category, bundle['global_model'])
                         .predict(pd.DataFrame([row[FEATURES]], columns=FEATURES))[0])
                          for _, row in assessed.iterrows()])
    if not np.isfinite(predicted).all():
        raise ValueError('Frozen artifact returned non-finite predictions')
    baseline = _baseline_predict(history, assessed)
    actual = assessed.daily_price.to_numpy()
    report.update(status='diagnostic_evaluation', deployedModel=safe_metrics(actual, predicted),
                  categoryMedianBaseline=safe_metrics(actual, baseline))
    for field, key in [('target_source', 'evaluationByTargetSource'), ('category', 'evaluationByCategory'),
                       ('subcategory', 'evaluationBySubcategory')]:
        for value in assessed[field].unique():
            select = (assessed[field] == value).to_numpy()
            holdout_count = int((targets[field] == value).sum())
            report[key][str(value)] = {'status': 'diagnostic_only', 'samples': int(select.sum()),
                                      'holdoutSamples': holdout_count, 'predictedTargets': int(select.sum()),
                                      'abstainedTargets': holdout_count - int(select.sum()),
                                      'deployedModel': safe_metrics(actual[select], predicted[select]),
                                      'categoryMedianBaseline': safe_metrics(actual[select], baseline[select])}
    report['artifactUnchanged'] = hashlib.sha256(artifact.read_bytes()).hexdigest() == before
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--real-export', required=True, type=Path)
    parser.add_argument('--cutoff', help='Optional ISO timestamp; default is the 70%% timeline point')
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--mode', choices=('deployed', 'candidate'), default='deployed',
                        help='Default evaluates the frozen artifact; candidate explicitly fits only in memory')
    parser.add_argument('--report', type=Path, help='Optional NEW report under .data; never production metrics')
    args = parser.parse_args()
    if args.report and (not args.report.resolve().is_relative_to((ROOT / '.data').resolve()) or args.report.exists()):
        parser.error('Use a new report path under services/ai/.data')
    try:
        report = evaluate(args.real_export, cutoff=args.cutoff, seed=args.seed, mode=args.mode)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            with args.report.open('x', encoding='utf-8') as stream:
                json.dump(report, stream, indent=2, allow_nan=False)
    except (ValueError, OSError, subprocess.SubprocessError):
        parser.error('Pricing evaluation failed; check local input, chronology and Node availability. No artifact was written')
    print(json.dumps(report, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()
