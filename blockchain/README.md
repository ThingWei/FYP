# RentHub local rental agreements

The Solidity contract is a local FYP prototype for physical-item rentals. It is
not a public-chain deployment, has not been externally audited, and must not hold
real funds. The API maps one Malaysian Ringgit cent to one local test-chain wei.

## Run

```text
npm install
npm test
npm run node:ganache
```

In `services/api/.env`, set `BLOCKCHAIN_MODE=ganache` and keep
`GANACHE_RPC_URL=http://localhost:8545`. Compile once with `npm run compile`; the
API loads the generated ABI/bytecode and deploys one agreement per approved
physical booking. It records deployment/signature hashes, completes on return,
cancels with the booking, and opens/resolves/dismisses disputes on-chain.

On Windows, `apps/renthub_flutter/run-renthub.ps1` performs the compile when
needed, starts Ganache before the API, verifies its JSON-RPC endpoint, and keeps
chain state under `blockchain/.data/ganache`. A separately started Ganache node
is detected and reused.

The first Ganache account acts as the prototype backend custodian and accounts
two and three act as the renter and Owner. Identity-to-wallet ownership and a
non-custodial signing experience remain out of scope for this local prototype.
