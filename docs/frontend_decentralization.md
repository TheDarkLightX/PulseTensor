# PulseTensor Frontend Decentralization Model

## Objective

Provide a permissionless interface model similar to other decentralized exchange frontends: any party can host the UI, and users can run it locally without trusted backend services.

## Architecture

- **Static SPA only** under `frontend/`.
- **No server middleware** for order flow, routing, signatures, or custody.
- **Direct contract interaction** via wallet + RPC.
- **Configurable routing** (chain ID, RPC URL, explorer URL, contract address) from UI, local storage, and URL parameters.
- **Dual protocol surfaces** in one interface: Core + Inference Settlement.
- **Fail-closed transaction UX** with chain mismatch checks before write calls.

## Trust Surface

- Users only trust:
  - Deployed smart contract bytecode and governance model.
  - Their selected RPC endpoint.
  - The frontend artifact hash they choose to run.
- Operators hosting mirrors cannot alter on-chain execution rules.

## Operational Recommendations

- Publish deterministic frontend build artifacts and hash.
- Encourage community mirrors and local builds.
- Keep default contract addresses explicit, never hidden in remote config.
- Prefer immutable/static hosting and content-addressed distribution where possible.
