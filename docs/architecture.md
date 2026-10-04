# Architecture

RentHub uses module-oriented MVC. Flutter views observe Provider controllers; controllers depend on repository interfaces; live and mock repositories implement those interfaces. The Express API is the trust boundary and uses routes -> controllers -> services -> repositories/models. Integrations are adapters behind services. FastAPI and Ganache are never called directly by Flutter.

The ten business modules are user, listing, booking, payment, rental, communication, review, dispute, loyalty/referral, and admin. Cross-cutting authentication, validation, audit, errors, configuration, API clients, and event names live outside modules.

Advanced AI adapters are artifact-backed and fail explicitly when compatible weights are unavailable. Pricing uses a versioned XGBoost bundle plus MongoDB-derived comparable evidence; recommendation uses SVD/cosine; verification uses YOLOv8, EfficientNet, EasyOCR and spaCy when their separately trained artifacts are installed. Flutter never supplies trusted market aggregates or calls these services directly.

Physical-product identity uses Flutter -> authenticated Express catalog routes -> MongoDB `product_catalog` cache -> Wikidata. Owners explicitly select a suggestion or choose manual entry. Express verifies canonical IDs before persisting them, then uses the verified identity only to select hierarchical pricing evidence; the catalog never supplies or adjusts a rental price. Provider failure falls back to stale cache and then manual entry.

