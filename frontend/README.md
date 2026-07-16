# PulseTensor Frontend

This frontend is a static, backend-free dApp for:

- `PulseTensorCore`
- `PulseTensorInferenceSettlement`
- `PulseTensorExactInferenceSettlementV1`

## Properties

- No centralized API server.
- No proprietary runtime dependency on private research tools.
- Reads and writes go directly from browser wallet + RPC to PulseChain contracts.
- Includes separate Core, optimistic Settlement, and manifest-gated Exact ZK Marketplace consoles.
- Performs full deployment-anchor and evidence review through the browsing RPC, then uses action-specific injected-wallet
  preflights: settlement identity for claim/refund, Core/config admission for creation, and task-config/verifier
  availability for proof settlement.
- Hostable anywhere static content is served over HTTP(S) (a local web server, Nginx, IPFS, GitHub Pages, Cloudflare Pages, S3, etc.). Browsers generally do not run the ES-module bundle correctly when `index.html` is opened directly with `file://`.

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

## Automated Community Distribution

From repo root:

```bash
make ui-release
```

This creates a release kit under `runs/frontend_release/` with:

- `frontend_dist.sha256.txt` (sorted per-file checksums)
- `frontend_dist.tree.sha256` (single hash over checksum manifest)
- `frontend_dist.tar.gz` (deterministic tarball)
- `frontend_dist.tar.gz.sha256`
- `frontend_release_receipt.json`

The release takes one private, validated snapshot of `dist/`; the checksum manifest and tarball are both produced from
that snapshot, never from separate live-tree reads. For a fresh build, the receipt binds the Git commit and clean/dirty
state, a stable-before/after frontend source digest, release/assurance tooling, lock/config digests, the four validated
public build inputs frozen before Vite runs, packaging/build tools, and every release hash. Its status remains
`candidate-release-kit`: the receipt is neither a signature nor a CI attestation, and hashes do not replace independent
review. The tarball stores directories as `0755` and regular files as `0644`, uses ustar with epoch-zero metadata, and
uses gzip without a filename or timestamp. Its bytes are reproducible for the same snapshot and recorded tar/gzip
toolchain; the timestamped receipt itself is intentionally not byte-reproducible.

The output path must not already exist. The script atomically claims it as current-user mode `0700`, locks it while
writing, and exclusively creates each mode-`0644` artifact without overwrite. Partial output is retained for diagnosis;
choose a new `--out-dir` (or archive and remove the old default directory) for each attempt. `--skip-build` is recorded
as `prebuilt-dist`, with build inputs, build source, and build toolchain explicitly unknown. Current packaging values are
not mislabeled as provenance for an earlier build.

Publish to IPFS (if `ipfs` CLI is installed):

```bash
make ui-ipfs
```

This additionally writes:

- `frontend_ipfs_publish_receipt.json`
- `frontend_ipfs_publish_receipt.txt`

IPFS publication extracts and manifest-verifies the release tarball, then publishes that derived snapshot rather than
rereading live `frontend/dist`. Returned CIDs are independently decoded as canonical CIDv1 with the expected codec and
SHA-256 multihash. The script reads the tarball back by CID and verifies its SHA-256, retrieves the directory by CID and
verifies the complete file manifest, and records those checks. This validates the local Kubo round trip; it is not an
availability, authenticity, independent-pin, or remote-gateway guarantee.

The release gate rejects root-relative generated assets so the bundle remains portable across mirrors. Wallet use is
deliberately blocked on shared `/ipfs/<CID>/` and `/ipns/...` path-gateway origins: unrelated content shares one browser
origin there. `make ui-ipfs` emits a CID-subdomain URL instead. Use that isolated origin, a dedicated host, or a local
build for wallet interaction.

## Runtime Configuration

The app supports three configuration sources:

1. Built-in presets (PulseChain mainnet/testnet/local).
2. Browser-local saved public preset + contract addresses (`localStorage`). Custom RPC routes are deliberately not
   persisted because provider credentials can appear in paths or query strings.
3. A built-in public preset selected by the optional `preset` URL query parameter (highest priority).

Example:

```text
?preset=pulse-testnet
```

RPC URLs and contract addresses are intentionally not accepted through URL parameters because URLs reach browser
history and hosting/gateway logs and are commonly used for phishing-style routing. Custom values can be entered for the
current session; custom RPC routes are not persisted by this dApp. If a wallet does not already know a custom chain, add
it manually in the wallet: the dApp refuses to copy the custom RPC route into persistent wallet settings.

Optional defaults can also be injected at build-time:

- `VITE_DEFAULT_CORE_ADDRESS`
- `VITE_DEFAULT_SETTLEMENT_ADDRESS`
- `VITE_EXACT_MANIFEST_URL`
- `VITE_EXACT_MANIFEST_SHA256`

Every `VITE_*` value is public. The exact manifest digest is an integrity/review root, never a secret and never a
substitute for independent review. Without both a manifest URL and its reviewed raw-byte SHA-256, exact value writes
remain blocked. The fresh-release path validates these values before building: Core and settlement must be nonzero
20-byte addresses set together; manifest URL and digest must be set together; the digest must be 32-byte hexadecimal;
and the URL must be credential-free HTTPS (localhost HTTP is permitted) without query, fragment, backslash, control
characters, or secret-like tokens. The captured values are then explicitly frozen in the Vite build environment.

## Exact Marketplace Manifest

The schema is bundled at `public/exact-inference-manifest.schema.json`. Prepare a canonical candidate and digest
receipt without exposing a signer or RPC credential:

```bash
INPUT=./candidate.json \
OUTPUT=./exact-manifest.canonical.json \
RECEIPT=./exact-manifest.receipt.json \
make ui-exact-manifest
```

The tool validates the strict V1 shape (exactly one reviewed verifier config and credential-free HTTPS/IPFS URI plus
SHA-256 for every evidence artifact), canonicalizes the JSON, writes new files with mode `0600`, and prints the SHA-256
expected by the UI. It does not endorse the deployment or inspect the chain. The UI independently checks the manifest
against the selected chain and repeats the check through the wallet before signing. See
[`docs/exact_inference_marketplace.md`](../docs/exact_inference_marketplace.md).

## Deployment Notes

- Pin the generated `dist/` artifact hash if deploying to content-addressed storage (IPFS).
- Serve with immutable caching for content-hashed assets.
- Keep contract addresses user-visible and configurable to avoid hidden routing.
- Serve the CSP as an HTTP response header when the host supports headers, adding `frame-ancestors 'none'`. CSP meta tags cannot enforce `frame-ancestors`; the bundle's bootstrap independently refuses to initialize the dApp inside a frame.
- Use a CID-subdomain IPFS gateway or a dedicated origin. Shared path gateways are suitable only for downloading and
  independently verifying release bytes; the wallet-capable bootstrap refuses to run on them.

## IPFS, Privacy, and Secrets

IPFS distributes static bytes; it is not a private application backend, durable database, job queue, RPC service, or proof-generation service. A CID identifies content but does not guarantee that anyone will keep serving it. `make ui-ipfs` pins to the local Kubo node used for publication. Operators should keep that node available and arrange independent pins before announcing a release.

Assume every file sent to IPFS is public and may remain retrievable. Do not publish private prompts, model inputs, proof witnesses, wallet metadata, private keys, seed phrases, API tokens, or authenticated RPC URLs. A public HTTP gateway can observe the requester IP address, CID, path, timing, and query string, and an ordinary browser does not independently verify gateway responses. Verify the published CID and release hashes through independent channels; use a locally controlled IPFS node when that trust and metadata exposure are unacceptable. Direct peer-to-peer IPFS retrieval also exposes network metadata and is not an anonymity system.

All `VITE_*` values are compiled into public browser assets. Browser storage is readable by code executing on the same origin and may be visible to extensions, so neither build variables nor `localStorage` may contain secrets. In particular, never bundle OpenAI/provider keys, pinning-service tokens, or private RPC credentials. The release validator blocks invalid and common secret-bearing forms, but no pattern detector can prove that arbitrary text is non-secret. Keep service credentials in an off-chain provider/prover process or an operator-controlled release environment. RPC operators can observe account-linked reads, IP addresses, and transaction broadcasts; users seeking less metadata leakage should use an RPC endpoint they control and avoid putting sensitive values in URL configuration.
