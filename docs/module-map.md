# Module map

| Module | Flutter | API collection | Primary responsibility |
|---|---|---|---|
| User | `modules/user` | `/api/v1/users` | identity, roles, KYC, trust |
| Listing | `modules/listing` | `/api/v1/listings` | catalog, search, item verification, pricing |
| Booking | `modules/booking` | `/api/v1/bookings` | requests, dates, policies |
| Payment | `modules/payment` | `/api/v1/payments` | simulated transactions |
| Rental | `modules/rental` | `/api/v1/rentals` | lifecycle, returns, agreements |
| Communication | `modules/communication` | `/api/v1/messages` | chat and notifications |
| Review | `modules/review` | `/api/v1/reviews` | ratings and review trends |
| Dispute | `modules/dispute` | `/api/v1/disputes` | evidence and resolution |
| Loyalty | `modules/loyalty` | `/api/v1/rewards` | points and referrals |
| Admin | `modules/admin` | `/api/v1/admin` | analytics, risk, moderation and audit |

Each API module is composed by `createModule`, which provides distinct model, repository, service, controller, validation, and router objects. Modules can replace any generated layer with specialized behavior as the feature grows.

