# PulseTensor Frontend

This frontend is a static, backend-free dApp for:

- `PulseTensorCore`
- `PulseTensorInferenceSettlement`

## Properties

- No centralized API server.
- No proprietary runtime dependency on private research tools.
- Reads and writes go directly from browser wallet + RPC to PulseChain contracts.
- Includes separate Core and Settlement consoles with monitor + action flows.
- Hostable anywhere static content is supported (local filesystem, Nginx, IPFS, GitHub Pages, Cloudflare Pages, S3, etc.).

## Run Locally

```bash
npm ci
npm run dev
```

Open the URL shown by Vite.

## Build Static Bundle

```bash
npm run build
```

Output is written to `dist/`.

Preview locally:

```bash
npm run preview
```

## Runtime Configuration

The app supports three configuration sources:

1. Built-in presets (PulseChain mainnet/testnet/local).
2. Browser-local saved config (`localStorage`).
3. URL query overrides (highest priority):
   - `chainId`
   - `chainName`
   - `rpc`
   - `explorer`
   - `core`
   - `settlement`

Example:

```text
?chainId=369&rpc=https://rpc.pulsechain.com&core=0xYourCoreAddress&settlement=0xYourSettlementAddress
```

Optional defaults can also be injected at build-time:

- `VITE_DEFAULT_CORE_ADDRESS`
- `VITE_DEFAULT_SETTLEMENT_ADDRESS`

## Deployment Notes

- Pin the generated `dist/` artifact hash if deploying to content-addressed storage (IPFS).
- Serve with immutable caching for content-hashed assets.
- Keep contract addresses user-visible and configurable to avoid hidden routing.
