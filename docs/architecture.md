# Architecture

RentHub uses module-oriented MVC. Flutter views observe Provider controllers; controllers depend on repository interfaces; live and mock repositories implement those interfaces. The Express API is the trust boundary and uses routes -> controllers -> services -> repositories/models. Integrations are adapters behind services. FastAPI and Ganache are never called directly by Flutter.

The ten business modules are user, listing, booking, payment, rental, communication, review, dispute, loyalty/referral, and admin. Cross-cutting authentication, validation, audit, errors, configuration, API clients, and event names live outside modules.

Advanced AI adapters initially return deterministic placeholder results. They preserve the intended request and response contracts so trained YOLOv8, EfficientNet, EasyOCR, spaCy, SVD/cosine, and XGBoost adapters can replace them without client changes.

