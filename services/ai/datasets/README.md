# KYC dataset provenance

Only manifests are tracked. Raw datasets belong under
`services/ai/.data/datasets/`, which is ignored by the repository-wide
`**/.data/` rule. Do not commit real MyKad images or other personal identity
documents.

The manifests intentionally report zero selected records until the applicable
licence/access conditions have been reviewed and data has actually been
downloaded. Update counts, subsets, labels, provenance, and grouped split counts
before training. Malaysian validation must use synthetic MyKad-like samples or
explicitly consented, securely handled samples.

For `train_document_risk.py`, create a local CSV containing `path`, `label`, and
`base_document_id`. All originals and manipulated derivatives of one document
must share the same `base_document_id`.
