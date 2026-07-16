# PulseTensor Frontend Decentralization Model

## Objective

Provide a permissionless interface model similar to other decentralized exchange frontends: any party can host the UI, and users can run it locally without trusted backend services.

## Architecture

- **Static SPA only** under `frontend/`.
- **No server middleware** for order flow, routing, signatures, or custody.
- **Direct contract interaction** via wallet + RPC.
- **Configurable routing** from visible UI controls; local storage retains only public presets/contract addresses, and
  URL routing accepts only exact built-in preset IDs.
- **Dual protocol surfaces** in one interface: Core + Inference Settlement.
- **Fail-closed transaction UX** with chain mismatch checks before write calls.
- **Relative production assets** for mirror portability, plus a wallet bootstrap that refuses shared IPFS/IPNS path
  origins and requires CID-subdomain, dedicated-origin, or local execution.
- **Top-level-only bootstrap**: a framed copy displays a warning and does not initialize wallet-capable application code.

## Trust Surface

- Users only trust:
  - Deployed smart contract bytecode and governance model.
  - Their selected RPC endpoint.
  - The frontend artifact hash they choose to run.
- Operators hosting mirrors cannot alter on-chain execution rules.

Static hosting does not remove trust from the browser delivery path. An HTTP gateway can withhold content, log requests, or return bytes that an ordinary browser does not independently validate. Users should obtain the expected CID and release hash through an independent channel. When response headers are available, mirrors should serve the repository CSP and add `Content-Security-Policy: frame-ancestors 'none'`; `frame-ancestors` cannot be enforced by an HTML meta tag.

## Operational Recommendations

- Publish deterministic frontend build artifacts and hash.
- Encourage community mirrors and local builds.
- Keep default contract addresses explicit, never hidden in remote config.
- Never recommend a shared `/ipfs/<CID>/` path URL for a wallet dApp. Different CIDs share that gateway origin and can
  interfere with browser storage/opener state. Use CID-subdomain gateway URLs or a dedicated origin.
- Prefer immutable/static hosting and content-addressed distribution where possible.
- Run `bash scripts/check_frontend_dist_portable.sh` before publishing a prebuilt `dist/`; the release and hash scripts run it automatically.

## What IPFS Does Not Provide

- A CID is content addressing, not a durability promise. Content disappears when no reachable node retains it. The publication script's `--pin=true` affects the publishing node only; use multiple independent pins and periodically test retrieval.
- IPFS content is public. Do not place private prompts, inference inputs, proof witnesses, wallet secrets, provider credentials, or personal data in frontend artifacts or task documents unless public disclosure is intentional.
- Public gateways learn requester metadata such as IP address, CID, path, timing, and URL query parameters. A self-hosted gateway reduces third-party gateway exposure; direct IPFS peers still learn network metadata. Neither mode supplies anonymity.
- IPFS is not a dynamic backend, RPC, scheduler, model host, or ZK prover. Marketplace providers and provers run off-chain and interact with the contracts; only public, content-addressed artifacts belong on IPFS.
- Availability should be monitored from independent networks. A successful publish command proves neither long-term pinning nor gateway availability.

## Secret Boundary

The frontend is a public artifact. Every `VITE_*` build variable is embedded into its JavaScript, and same-origin code or browser extensions can read browser storage. API keys, private/authenticated RPC URLs, pinning tokens, private keys, and seed phrases must never be bundled or stored in `localStorage`. Put provider and pinning credentials only in an operator-controlled off-chain process or CI secret store, and keep them out of release receipts and command output. Fresh releases validate and freeze the four supported public inputs before Vite runs, rejecting zero/malformed addresses, unpaired manifest data, URL credentials/query/fragment, and common secret-like forms. This is a guardrail, not a proof that arbitrary operator-provided text is non-secret.

RPC access is also a privacy boundary: an operator can correlate IP addresses, account-specific reads, and broadcasts.
Prefer a user-controlled RPC when that correlation matters. RPC/contract URL overrides are rejected because query
parameters are retained in browser history and can reach hosting/gateway logs. The page uses `Referrer-Policy:
no-referrer` to reduce onward leakage, not to make the original request private.

## Distribution Automation

- `make ui-release` builds, validates, and snapshots `dist/` once. The manifest and deterministic tarball are derived
  solely from that private snapshot; reproducibility is scoped to identical snapshot bytes and the recorded tar/gzip
  toolchain. The timestamped candidate receipt is not itself deterministic.
- `make ui-ipfs` publishes a manifest-verified extraction of that tarball, not a later read of live `frontend/dist`.
  It independently decodes returned CIDv1 values, verifies the expected SHA-256 multihash/codec, reads the tarball back
  by CID, and retrieves and manifest-verifies the directory before writing a candidate publication receipt.
- Release scripts reject output that already exists, symlinked paths, unsafe ownership/modes, source or dist symlinks,
  special files, backslashes, and control characters in artifact names. They atomically claim a current-user `0700`
  output directory, lock it, exclusively create `0644` artifacts without overwrite, normalize snapshot directories and
  files to `0755`/`0644`, and retain partial output for review. Use a new output path for every attempt.
- `frontend_release_receipt.json` binds the commit/tree state, defined frontend source digest, complete release and
  assurance tooling digest, dependency/config hashes, normalized archive policy, and artifact hashes. A fresh build
  records validated inputs captured and frozen before the build and verifies that source/tooling did not change during
  it. A `prebuilt-dist` receipt deliberately records build inputs/source/toolchain as unknown rather than substituting
  current packaging data.
- `assurance_context` is explicitly caller-reported context and `assurance_context_is_attestation` is false. The CI
  workflow sets it only after `make verify-ui`, but authenticity still requires the uploaded artifact/commit or a
  separate signed provenance mechanism.
- Community operators can verify:
  - file-level checksums (`frontend_dist.sha256.txt`)
  - tree hash (`frontend_dist.tree.sha256`)
  - published CIDs (`frontend_ipfs_publish_receipt.json`)
