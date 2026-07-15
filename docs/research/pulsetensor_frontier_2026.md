# PulseTensor Frontier Plan, July 2026

## Executive finding

PulseTensor should not try to beat Bittensor by cloning Dynamic TAO and launching another speculative token. Its credible path beyond Bittensor is an **assurance-first, demand-funded market for AI work** on PulseChain:

1. sell a concrete PulseChain service before subsidizing a general network,
2. attach typed evidence and explicit assumptions to every payable work receipt,
3. formally verify the escrow, conservation, authorization, nullifier, refund, and payout kernel,
4. use cryptographic, statistical, and game-theoretic evidence appropriate to each task instead of claiming that all AI output has one kind of proof, and
5. finance development from paid usage, design partners, and a disclosed treasury budget before considering a PulseTensor token.

The first wedge should be **Pulse Guardian**, followed by **Pulse Data**. Guardian would simulate transactions before signature, detect malicious approvals and contracts, diagnose bridge or missing-token problems, and issue plain-language risk receipts. Data would provide redundant RPC, indexing, price, liquidity, and bridge-health feeds with provenance and staleness bounds.

This direction is a testable product hypothesis, not a finding about every PulseChain user. A July 14, 2026 snapshot shows a real but narrow PulseChain economy: approximately $41.35 million in TVL, $31.72 million in stablecoins, $2.33 million in daily DEX volume, and $9,300 in daily application fees. PulseX accounts for most observed TVL and DEX volume. These values change continuously, are third-party estimates rather than audited accounts, and should be treated only as a dated market-size signal. The exact retrieval time and raw API response were not preserved, so reproduce the snapshot before relying on it for a funding or launch decision. Sources: [PulseChain on DeFiLlama](https://defillama.com/chain/pulsechain) and [PulseX on DeFiLlama](https://defillama.com/protocol/pulsex).

## Honest starting point

PulseTensor currently has a strong economic-contract skeleton:

- native PLS stake accounting,
- subnet and mechanism registration,
- validator weight-hash commit and reveal,
- missed-reveal slashing,
- governed emission pools,
- optimistic inference-root commitments,
- fee escrow and pull claims,
- replay and duplicate-leaf challenges,
- Foundry tests, fuzzing, invariants, and security scripts, and
- bounded formalized state-model specifications.

It is not yet a Bittensor-class decentralized AI network. The repository does not contain miner or validator node software, service discovery, a P2P protocol, actual weight vectors, weight aggregation, Yuma-equivalent consensus, quality-derived miner payouts, a task market, semantic inference proofs, an indexer, or production testnet evidence. Revealed `weightsHash` values do not currently determine rewards. Governance selects payout recipients.

The repository also does not currently contain a machine-checked refinement proof from its YAML state models to Solidity and deployed bytecode. “Formal-specification-driven and adversarially tested” is accurate. “Fully formally verified” is not yet supported by the public evidence.

## What the PulseChain community may need

The evidence is a small convenience sample, not a representative survey: a forum index, two forum threads, one Reddit discussion, and aggregate chain metrics. It is vulnerable to selection, moderation, survivorship, and vocal-minority bias. Those sources repeatedly mention scams, fake support, bridge failures, missing assets, confusing wallet behavior, useful applications, and builder support. See the [PulseChain forum](https://www.pulsechain.forum/), a [customer-service scam warning](https://www.pulsechain.forum/t/pulsechain-customer-service-warning/2156), a [wallet trust discussion](https://www.pulsechain.forum/t/pulsewallet-legit-or-scam/225), and a [community longevity discussion](https://www.reddit.com/r/Pulsechain/comments/1jtx7ql/pulsechains_longevity/).

The resulting priority order is therefore a hypothesis to validate:

1. transaction safety, scam detection, bridge diagnosis, and credible support,
2. useful services and non-speculative business applications,
3. reliable RPC, indexing, oracle, and developer infrastructure,
4. easier onboarding and payment UX,
5. transparent builder funding with independent governance, and
6. trust earned through audits, reproducible deployment, evidence, and support.

### H0: users will pay for the first wedge

Guardian development should pass a demand gate before a new protocol or token is built.

- Interview 20 people across at least five wallets or front ends, five protocols or support teams, five active users, and five developers; record recruitment source and rejected interviews.
- Give each interviewee a clickable or command-line prototype and a priced offer, not only a feature description.
- **Support H0:** at least three unrelated organizations sign a paid 90-day pilot, aggregate contracted recurring revenue reaches at least $3,000 per month, at least 30 distinct users complete 100 real simulations, and at least 20% of shown high-risk warnings lead to an observable cancel-or-investigate action.
- **Refute H0:** after 20 qualified interviews and 10 priced proposals, fewer than three pilots or less than $3,000 monthly contracted revenue is obtained, or operators will not provide labeled incident data needed to measure false positives and misses.
- Preregister the interview guide, pricing bands, success thresholds, and exclusion rules. Publish de-identified counts, not hand-picked testimonials.

If H0 fails, test Pulse Data under a separately preregistered gate; do not reinterpret free beta usage as willingness to pay.

### Product sequence

| Order | Product | Paying users | Why PulseTensor helps |
|---|---|---|---|
| 1 | Pulse Guardian | Wallets, DEXs, bridges, support teams, end users | Multiple miners analyze a transaction; evaluators test the result; the user receives a signed, challengeable receipt. |
| 2 | Pulse Data | DApps, analytics sites, wallets, liquidators | Redundant providers produce provenance-bound feeds with explicit freshness and disagreement bounds. |
| 3 | Assurance market | Token teams, treasuries, developers | Paid, reproducible checks for contracts, deployments, vesting, escrow, and governance. |
| 4 | General compute and inference | Agents and smart-contract applications | Standard work receipts let contracts purchase outputs without pretending all outputs are objectively provable. |
| 5 | Permissionless training | Researchers and model builders | Sparse, contribution-scored training with dynamic participation and evidence-bearing settlement. |

## The 2026 Bittensor bar

Bittensor is a moving protocol, not one stable mechanism to copy. As documented in July 2026, miners produce subnet-specific commodities, validators score miners, subnet owners define incentive mechanisms, stakers can receive subnet alpha tokens, and Yuma Consensus converts validator rankings into participant emissions. At the network layer, the documentation says subnet allocation reverted in June 2026 from the flow-based model to a price-based model with additional protections. Any comparison must therefore name a documentation revision and distinguish subnet-level scoring from network-level allocation. See the [official subnet overview](https://docs.learnbittensor.org/subnets/understanding-subnets), [validator documentation](https://docs.learnbittensor.org/validators), [Yuma documentation](https://docs.learnbittensor.org/learn/yuma-consensus), [emission documentation](https://docs.learnbittensor.org/learn/emissions), and [protocol announcements](https://docs.learnbittensor.org/learn/announcements).

The operational bar has also moved beyond inference. The March 2026 [Covenant-72B preprint](https://arxiv.org/abs/2603.08163) reports a 72-billion-parameter, 1.1-trillion-token permissionless training run using Gauntlet and SparseLoCo on Bittensor. Treat it as reported experimental evidence, not proof of general permissionless-training security or an independently replicated benchmark; its comparisons are not fully controlled. PulseTensor needs a real data plane, dynamic node participation, contribution evaluation, checkpoint exchange, and usable model outputs before claiming runtime parity.

PulseTensor’s opportunity is not raw scale alone. It can make the assurance model explicit and enforce narrow value-safety properties more strongly than a large, fast-moving runtime.

### Parity matrix

“Bittensor parity” should mean passing each evidence row, not matching a token or vocabulary.

| Capability | PulseTensor public evidence now | Bittensor July 2026 reference bar | PulseTensor evidence gate |
|---|---|---|---|
| Economic kernel | Stake, registration, governance-set pools, and optimistic settlement contracts | Live chain, subnet registration, staking, and participant emissions | Independent audit plus bytecode-linked proofs of conservation, authorization, caps, refund, and single settlement |
| Miner/validator runtime | Not present | SDK/CLI and live miner/validator participation | Versioned open-source nodes; reproducible two-implementation interoperability test with churn and partitions |
| Discovery and transport | Not present | Operational network interfaces and subnet endpoints | Authenticated P2P/service discovery; NAT, replay, rate-limit, and eclipse tests |
| Quality-to-payout path | `weightsHash` does not determine payouts | Validator rankings feed Yuma participant emissions | Revealed vectors, deterministic aggregation, and a trace from scored work to exact payout |
| Subnet allocation | Governance-selected pools | Price-based subnet allocation as documented after June 2026 | Externally funded demand rule with wash-trading counterexamples and bounded subsidy |
| Useful service | No production demand evidence | Multiple live digital-commodity subnets | H0 paid pilots, public SLOs, labeled incidents, retention, and external fee receipts |
| Distributed training | Not present | Covenant-72B reported experiment | Reproducible smaller run, independent replication, byzantine/churn tests, and checkpoint recovery before scale claims |
| Assurance | Specs, tests, fuzzing, and invariants; no public source-to-bytecode proof | Subnet-specific operational assurance | Typed receipts, theorem inventory, explicit trusted computing base, refinement evidence, and public counterexamples |
| Operations | Deployment and security scripts; no capped beta history | Production operations and evolving protocol | Reproducible deploy, monitoring, incident drills, public bounty, and 90 incident-free capped days |

## Assurance-typed work receipts

Every payable inference, evaluation, training update, oracle observation, or subjective judgment should commit a common receipt:

```text
receiptVersion
domainSeparator(chainId, settlementContract, subnetId, mechanismId)
taskId
taskType
requester
workerOrWorkerSetRoot
epoch
asset
escrowedAmount
maximumFee
recipientSetRoot
feeScheduleHash
paymentTermsHash
requestedSemanticsId
programRoot
modelRoot
inputRoot
outputRoot
datasetOrBenchmarkRoot
preprocessRoot
executionEnvironmentRoot
randomnessCommitment
proofMode
proofSystemId
verifyingKeyHash
proofSecurityParametersHash
proofDigest
score
scoreRuleId
scoreUncertaintyAndSampleSize
verifierSetRoot
committeeSeed
evaluatorReportRoot
evaluatorSignatureRoot
evidenceAvailabilityCommitment
policyVersion
resourceClaim
submittedAt
challengeDeadlineAndFinalityRule
assumptionManifestHash
trustedComputingBaseHash
nullifier
```

The EIP-712-compatible signed/hashed domain prevents cross-chain, cross-contract, cross-subnet, and cross-mechanism replay. Amount, maximum fee, asset, recipients, and policy version are part of what is authorized; the contract must not infer them from mutable global configuration. The nullifier is derived from that full domain plus the task identifier and payer authorization. Personal data and proprietary inputs stay off-chain behind commitments with an explicit availability and dispute policy.

The `proofMode` determines what evidence is required:

| Mode | Suitable work | Required evidence |
|---|---|---|
| Exact | Deterministic transforms and tractable fixed models | Program, model, preprocessing, input, semantics, and output commitments plus a sound validity proof |
| Optimistic | Expensive deterministic inference | Canonical trace commitment, data availability, challenger bond, interactive fraud proof, and a finality-aware dispute window |
| Statistical | Probabilistic quality evaluation | Preregistered proper scoring rule, hidden random tests, sampling frame, sample size, confidence or credible interval, and contamination controls |
| Contribution | Training updates and adapters | Starting checkpoint, optimizer and seed commitments, assigned-shard authorization, uniqueness checks, hidden marginal-loss evidence, uncertainty, and robust aggregation |
| Subjective | Judgments without objective ground truth | Independent random assignment, conflict disclosure, minimum panel size, and an assumption-explicit peer-prediction or governed appeal mechanism |

Formal verification can prove that the contract applies the declared transition and never pays beyond escrow. It cannot prove that a model is useful, unbiased, uncontaminated, or truthful about the world.

### Canonical execution semantics

“Same model and input” is not enough for exact or optimistic verification. `requestedSemanticsId` must bind a versioned, executable specification of tokenizer and preprocessing, tensor shapes and layout, operator set, integer/fixed-point or floating-point format, rounding and overflow, reduction order, randomness algorithm and seed derivation, permitted nondeterminism, output encoding, and failure behavior. Exact settlement should use a canonical interpreter or proof circuit whose output is bit-for-bit determined. If heterogeneous hardware cannot reproduce that result, the receipt must use a statistical or tolerance-bearing mode and must not be labeled exact.

For randomized tasks, the receipt commits the requester’s entropy before worker selection, combines it with unpredictable finalized-chain entropy and worker/evaluator commitments, and records the derivation. A block producer’s manipulable block value alone is not adequate committee randomness.

### Trusted computing base

Each proof claim needs a versioned TCB manifest. Depending on mode, it may include the EVM and chain finality assumptions, hash and signature primitives, Solidity compiler or source-to-bytecode relation, proof-system verifier and precompiles, circuit generator, trusted setup/SRS, canonical interpreter, data-availability layer, randomness beacon, evaluator software and hidden-test custody, oracle inputs, proxy/admin keys, governance/timelock, and deployment procedure. “Verified” means only that the stated property holds if the declared TCB and assumptions hold.

## Correct-by-construction settlement target

The next value-moving contract should be a separate, small verified settlement kernel rather than more logic in `PulseTensorCore`.

Required safety properties:

- **Conservation:** payouts, refunds, fees, and precisely specified rounding dust equal the amount removed from escrow.
- **Solvency:** contract assets are never below outstanding participant liabilities under the stated asset assumptions.
- **Single settlement:** a task or receipt nullifier cannot be paid twice.
- **Monotone lifecycle:** status transitions follow one total, enumerated transition relation; resolved and settled states cannot reopen.
- **Verifiable slashing:** value can be slashed only after the contract verifies the declared objective proof. Any subjective or governed adjudication path must be separately labeled, bounded, delayed, and appealable; it is not a mathematical correctness guarantee.
- **Refund liveness:** pause and emergency modes cannot block a matured refund path.
- **Bounded authority:** fees, treasury transfers, pause duration, and emergency powers have immutable caps plus delayed governance. Existing jobs cannot be migrated to new logic without each payer’s explicit opt-in; otherwise an upgrade key could bypass every proved bound.
- **Refinement:** the concrete deployed bytecode simulates the abstract transition system for every reachable trace under declared environmental assumptions.

A minimum task lifecycle is:

| State | Allowed exits | Value rule |
|---|---|---|
| `Open` | `Assigned`, `Cancelled`, `Expired` | Escrow is locked; only authorized cancellation or timeout can refund. |
| `Assigned` | `Submitted`, `Expired` | Worker identity and terms are snapshotted; mutable global fees cannot change the job. |
| `Submitted` | `ChallengeWindow` | Receipt and evidence commitments are immutable; no service payout yet. |
| `ChallengeWindow` | `ResolvedAccepted`, `ResolvedRejected` | A valid challenge is an event within this state, not a terminal status; the specified resolver decides the exit. |
| `ResolvedAccepted` | `Settled` | Exactly the snapshotted payout vector becomes claimable. |
| `ResolvedRejected` | `Settled` | Exactly the specified refund, challenger reward, and slash vector becomes claimable. |
| `Cancelled`, `Expired` | `Settled` | Only the specified refund and any objectively earned fee become claimable. |
| `Settled` | none | Terminal for the job; nullifier is consumed and escrow liability is converted exactly once into pull-claim liabilities. A separate withdrawal transition reduces each claim only after a successful transfer. |

All time comparisons, chain-reorganization assumptions, pause behavior, partial claims, rounding order, zero-recipient handling, and failed asset transfers must be part of the transition specification. Liveness is conditional on stated chain progress, data availability, gas bounds, and at least one party willing and able to submit a transaction.

### Evidence ladder: differential testing is not refinement

Generated abstract-model traces replayed against Solidity are **differential tests** over finitely many inputs. They are valuable counterexample finders, but zero observed divergence is not a proof. A **refinement proof** universally quantifies over reachable abstract and concrete states and proves an invariant-preserving simulation relation, ideally down to deployed bytecode. Bounded model checking proves only the explored bound unless a completeness argument is supplied.

Use an explicit claim ladder:

1. executable specification with reviewed invariants,
2. unit, fuzz, invariant, mutation, and differential tests,
3. bounded model-checking results with bounds and solver versions,
4. an unbounded source-level safety proof for named properties, and
5. a source-to-bytecode or direct-bytecode refinement proof plus deployment hash attestation.

Useful precedents are [VerX source-level functional safety verification](https://www.sri.inf.ethz.ch/publications/permenev20verx), [KEVM’s executable EVM semantics](https://fsl.cs.illinois.edu/publications/hildenbrandt-saxena-zhu-rodrigues-daian-guth-moore-zhang-park-rosu-2018-csf.pdf), and the [Ethereum 2.0 deposit-contract verification](https://daejunpark.github.io/papers/deposit.pdf), which targeted compiled bytecode and explicitly scoped its proof to within one transaction. These are patterns and possible tools, not evidence that PulseTensor already has equivalent proofs. The repository should store theorem statements, assumptions, tool/container digests, proof logs, deployed bytecode hashes, and a mapping from each public assurance claim to its strongest completed rung.

For inference, full zero-knowledge proof should not be mandatory for every large-model call. Use a proof ladder. Exact work can use zkML or a zkVM. Large deterministic work can use optimistic verification and trace challenges. Quality claims need hidden tests and statistical evidence. High-value disputes can escalate to stronger verification. Relevant evidence includes [zkCNN](https://eprint.iacr.org/2021/673), [zkLLM](https://arxiv.org/abs/2404.16109), [zkGPT](https://www.usenix.org/system/files/usenixsecurity25-qu-zkgpt.pdf), [opML](https://arxiv.org/abs/2401.17555), and [TrueBit verification games](https://arxiv.org/abs/1908.04756).

A proof establishes execution relative to committed inputs, model, and program. It does not establish real-world truth or usefulness.

## Incentives and anti-collusion

No permissionless protocol should claim to be Sybil-proof. [Douceur’s Sybil result](https://www.microsoft.com/en-us/research/publication/the-sybil-attack/) explains the identity limitation absent a trusted authority or strong resource assumptions.

PulseTensor should combine:

- slashable economic identities,
- random evaluator committees,
- concave or capped influence,
- task-local decaying reputation,
- new-identity probation,
- hidden rotating tests,
- contribution uniqueness and correlation analysis,
- delayed inclusion and quarantine, and
- multiple aggregation defenses tested against adaptive attacks.

Robust aggregation is assumption-sensitive. [Krum](https://papers.nips.cc/paper/6617-machine-learning-with-adversaries-byzantine-tolerant-gradient-descent) and [Bulyan](https://proceedings.mlr.press/v80/mhamdi18a/mhamdi18a.pdf) provide guarantees under explicit bounds, while [Fall of Empires](https://www.auai.org/uai2019/proceedings/papers/83.pdf) constructs attacks against earlier distance-based defenses. The protocol should publish its adversary fraction, independence, data, and network assumptions rather than naming an algorithm as a guarantee.

Verifier incentives also matter. If checking costs money and verifiers are paid only when fraud is found, honest checking may not be an equilibrium. Version 8 of the [Proof-of-Learning with Incentive Security preprint](https://arxiv.org/html/2404.09005v8) proposes committed capture-the-flag flags or safe deviations to reward genuine checking. It is a May 2026 arXiv preprint, not a deployed standard or independently replicated PulseTensor result. Its guarantee is game-theoretic incentive security for rational actors under its cost, randomness, task-provider, and collusion model—not Byzantine correctness. The paper itself notes the PoL security/efficiency/difficulty trilemma, earlier spoofing attacks, communication costs for large models, and numerical reproducibility concerns. PulseTensor should reproduce the theorem and attacks with its own parameters before adoption.

Let `G_escape` be the incremental cheating benefit, including computation saved, conditional on escaping detection; `p` the lower-bound detection probability against the strongest modeled adaptive strategy; and `L_detect` the incremental loss on detection, including collectible bond and forfeited reward but excluding uncollectible or circular protocol tokens. Risk-neutral one-shot deterrence requires:

\[
(1-p)G_{escape} - pL_{detect} < 0
\quad\Longleftrightarrow\quad
p > \frac{G_{escape}}{G_{escape}+L_{detect}}.
\]

Repeated play must add future profit, identity-reset cost, collusion transfers, capital cost, false-positive risk, and risk preferences. Verifier participation separately requires expected checking compensation to exceed verification cost and opportunity cost even when real fraud is rare. These inequalities are design constraints only if each term has a conservative empirical interval, the bond is liquid and collectible, and sensitivity analysis shows the result survives worst-case bounds.

## Launch economics without a PulseTensor token

Use PLS or WPLS for bonds and PLS or a reviewed existing stable asset for service payments. Asset-specific assumptions must cover transfer fees, rebasing, blacklisting, hooks, decimal conversion, depeg, and price-oracle failure; the first kernel should support only explicitly allowlisted semantics. Do not create a protocol stablecoin or per-subnet speculative assets during product discovery.

For a customer payment `P`, the initial exact split should be simulated around:

| Recipient | Share |
|---|---:|
| Active service miner | 72% |
| Active evaluators | 12% |
| Subnet builder and maintainer | 5% |
| Core maintenance treasury | 5% |
| Security operations and bug bounty | 3% |
| Pulse ecosystem public goods or referrals | 3% |
| **Total** | **100%** |

For every accepted job, the implementation must calculate shares in base units with one documented rounding rule and enforce:

\[
P_{miner}+P_{eval}+P_{builder}+P_{core}+P_{security}+P_{ecosystem}+D=P,
\]

where the six named recipients correspond to the table and `D` is bounded rounding dust sent to a declared recipient. Refund and rejected-job equations must be specified separately. No administrator can withdraw liabilities or unassigned dust.

Recommended governance bounds are a feasible set, not independently selectable suggestions:

- miner: 60% to 80%,
- evaluators: 10% to 25%,
- subnet builder: 0% to 7%,
- core treasury: 4% to 5%,
- security: 2% to 5%,
- ecosystem: 1% to 5%, and
- every proposal must sum to exactly 100% and keep subnet builder plus core treasury at or below 12%.

The adjusted individual maxima eliminate the earlier 14% builder-plus-core conflict. The contract must still reject an infeasible vector rather than silently normalize it. Fee changes should be delayed and snapshotted per job. Stake should provide slashable security and selection friction, not dominate direct payout.

There should be no network subsidy at product launch. If research later introduces a finite treasury subsidy, define `F_ext,t` as externally sourced, nonrefunded fees after excluding protocol credits and known customer/provider/owner affiliates. For each epoch:

\[
R_t \le F_{ext,t} + S_t,
\qquad
0 \le S_t \le \min(S_{remaining,t},\, \sigma F_{ext,t}),
\qquad
S_{remaining,t+1}=S_{remaining,t}-S_t.
\]

`S_remaining` must start from a published finite budget, `σ` must be capped by governance, and the program must have a date and utilization sunset. Self-paid or circular volume can never mint an uncapped positive-sum reward.

A research-only subnet score can combine 50% normalized square-root trailing `F_ext`, 30% preregistered verified quality, and 20% verified reliability, with no stake term. If `q_j` is a subnet’s normalized score, set its subsidy share to `a_j = min(q_j, 0.15)` and do **not** renormalize after capping; the residual remains unissued. This resolves the mathematical conflict that fewer than seven eligible subnets cannot consume 100% of a budget under a 15% cap. Task-specific customer payments are unaffected and go to the task’s providers. The rule remains a hypothesis requiring wash-trading simulations, affiliate classification, and adversarial review.

### Funding the creator without hidden extraction

No tokenomics design guarantees a living. At the July 2026 ecosystem scale, the project should plan an 18-month non-token runway of approximately $280,000 to $330,000:

- about $9,000 per month in gross founder compensation,
- about $2,500 per month in infrastructure and security operations, and
- $75,000 to $125,000 for legal work, audits, and bounties.

The practical financing stack is:

1. ten Guardian or Data design partners at roughly $750 to $1,500 per month,
2. milestone sponsorship for prototype, proof, audit, and public-support deliverables,
3. paid hosted APIs, SLAs, enterprise support, and private deployments around the open protocol,
4. refundable, nontransferable service credits usable immediately, and
5. company equity or a properly exempt offering with counsel if pre-product capital is necessary.

The arithmetic exposes a financing gap. Eighteen months of $9,000 founder compensation plus $2,500 operations is $207,000; adding $75,000 to $125,000 for legal work, audits, and bounties yields $282,000 to $332,000 before taxes, payment costs, bad debt, or contingency. Even if $150,000 monthly service volume immediately produced a $7,500 core fee and ten $750 subscribers added $7,500, 18 months of gross revenue would be $270,000: a $12,000 to $62,000 shortfall, and the service-volume assumption is itself unvalidated.

Therefore use stage financing: paid discovery and pilots first, then obtain at least the uncovered audit/legal budget plus six months of fixed costs from disclosed grants, sponsorship, company equity, or a counsel-approved exempt financing before commissioning those obligations. Maintain a 13-week cash forecast and do not count token inventory, uncontracted volume, refundable customer escrow, security reserve, or customer bonds as runway. Founder compensation should fall, pause, or be separately financed if unrestricted cash drops below the published reserve policy.

Founder compensation should be a disclosed company or treasury budget. It should not be a hidden wallet royalty.

## Conditional token gate

Do not add a PulseTensor token until all of these are true:

- at least three independent useful subnets,
- at least seven independent evaluators,
- at least 100 independent paying customers,
- at least $25,000 per month in external paid volume for three consecutive months,
- 90 days of capped mainnet beta without a critical incident,
- two independent audits with published scope, and
- a funded public bug bounty.

It must also pass a **token function test**: name a necessary protocol capability that cannot be delivered with PLS/WPLS, customer payment assets, contractual service credits, or nontransferable reputation; quantify the user benefit; show that protocol safety does not depend on price appreciation; and show that removing the token breaks that capability for a technical rather than fundraising reason. PulseTensor does not pass this test today, because PLS can already provide payment and slashable collateral.

If those gates are met, a research starting point is a fixed one-billion-token maximum:

- 55% earned work and performance rewards released over at least ten years,
- 15% ecosystem grants and retroactive funding,
- 10% community treasury,
- 10% founder and core builder allocation,
- 5% future contributors,
- 3% protocol-owned liquidity, and
- 2% security and bounty reserve.

Founder and contributor allocations should vest for 48 months with a 12-month cliff and no administrative acceleration. There should be no public presale, sacrifice, revenue right, guaranteed yield, reflection tax, or generic delegation dividend. A token, if justified, should be a slashable bond and bounded governance tool. PLS should remain a payment and bond option.

The percentages sum to exactly 100%, but that is only a supply allocation, not a complete mechanism. A proposal would also need a per-epoch issuance cap, a deterministic release curve whose cumulative issuance never exceeds one billion, rules for unused emissions, circulating-supply disclosures, delegation and slashing equations, governance quorum/anti-capture rules, and simulations showing solvency without appreciation. This allocation is a hypothesis requiring legal review, mechanism simulation, and community governance. It is not a recommendation to issue a token now.

## Privacy-aware launch

The defensible goal is key security and operational compartmentation, not guaranteed public unlinkability and never concealment of beneficial ownership, taxable activity, sanctions exposure, or material conflicts from parties entitled to that information. Public blockchains make durable graph, timing, gas, signer, and governance metadata available; no deployment procedure can promise anonymity.

- Use separate entity treasury, deployer, Safe-owner, governance proposer, fee collector, vesting, testnet, and personal wallets.
- Use dedicated hardware devices, keys, and browser profiles.
- Fund a one-time entity deployer from a documented lawful source; retain internal source-of-funds, beneficial-owner, approval, and tax records. Avoid unnecessary commingling with personal wallets, but do not structure transfers to evade reporting or screening.
- Use a self-hosted node or contractually appropriate trusted RPC to reduce third-party metadata disclosure and improve reliability; this does not hide on-chain activity.
- Publish role addresses, deployed bytecode hashes, proxy/implementation bindings, timelocks, and control boundaries. Disclose controllers to auditors, counsel, banks, tax authorities, and other entitled parties even when personal names are not broadcast publicly.
- Keep payroll, company operations, and personal investing in separate books and accounts with a written expense and conflict policy.
- Do not use mixers, peel chains, nominee signers, false entities, or misleading transaction descriptions as a deployment workflow.

The canonical deployment script now supports hardware, KMS, keystore, and interactive signing without putting raw private keys or passwords in command arguments, verifies the chain ID and contract bindings, and writes a receipt intended to contain no secret. This reduces common secret-handling mistakes; it does not prove the host, hardware, KMS policy, shell environment, RPC, or signer is uncompromised. Public-chain observers can still see the deployer, funding graph, contract creation, timing, and later authority changes. Privacy is limited compartmentation, not anonymity.

## Falsifiable research program

PulseTensor’s research hypotheses must have support and refute recipes.

### H1: Demand-weighted allocation reduces reflexive subsidy

- Support: simulate honest demand, wash traffic, colluding providers, affiliate-classification error, and price shocks across preregistered parameter ranges; show that attacker net return is negative and useful subnets retain funding without violating the finite-subsidy law.
- Refute: construct a coalition that controls customer, miner, evaluator, and subnet owner identities and recovers more subsidy than its nonrecoverable fees and compute cost.
- Required artifact: deterministic strategy-sweep inputs, code, seed, Pareto frontier, and counterexample traces.

### H2: Assurance-typed receipts outperform one universal proof rule

- Support: preregister per-task service and security thresholds, then compare cost, latency, fraud detection, false positives, and payout accuracy across exact, optimistic, statistical, contribution, and subjective tasks.
- Refute: find a task class in which its assigned proof mode admits cheaper profitable fraud than an alternative mode under the same service target.
- Required artifact: task corpus, proof-cost profiles, challenge traces, and declared assumptions.

### H3: Committed capture-the-flag rewards solve verifier under-checking at launch scale

- Support: independently implement the PoL preprint’s committed flags/safe-deviation mechanism and attacks, instantiate a formal game with measured PulseTensor verification costs, and show honest checking is an equilibrium under explicitly bounded rational collusion and numerical-reproducibility assumptions.
- Refute: exhibit a lazy or colluding verifier strategy with higher expected payoff while reports still pass the on-chain checks.
- Required artifact: theorem statement, solver/model file, parameter bounds, and adversarial simulation.

### H4: Hidden evaluation predicts deployed utility

- Support: show that sealed and counterfactual benchmark performance predicts post-deployment outcomes better than public benchmark scores.
- Refute: demonstrate contamination, adaptive querying, or evaluator leakage that removes the predictive advantage.
- Required artifact: benchmark roots, rotation policy, contamination probes, and preregistered evaluation.

### H5: the Solidity settlement refines its state model

- Support: prove a named simulation relation from every reachable abstract state and input to contract bytecode behavior, including reverts, external-call outcomes, time, arithmetic, rounding, pause, and terminal claims.
- Refute: one generated, symbolic, or manually constructed concrete trace has no matching abstract transition, or one abstractly permitted transition cannot execute under the stated liveness assumptions.
- Required artifact: versioned model, relation and theorem statements, proof object/log, tool and container digests, compiler settings, deployed bytecode hash, and independently replayable counterexample tests.

## Evidence gates for value at risk

Passing a later gate does not broaden an earlier proof’s scope. A public evidence index should mark every item passed, failed, waived, or not applicable and link to immutable artifacts.

| Gate | Required evidence | Maximum exposure unlocked |
|---|---|---|
| G0 — demand | H0 interview record, three paid pilots, priced contracts, baseline incident labels | No protocol custody; prototype or read-only simulation only |
| G1 — specification | Threat model, lifecycle, asset semantics, theorem inventory, TCB manifest, authority matrix, economic equations, and failure/recovery plan | Testnet only |
| G2 — implementation | Reproducible build, all tests and static gates, mutation score target, differential traces, bounded-check bounds, dependency/SBOM review, and no unresolved critical findings | Internal testnet value only |
| G3 — independent assurance | Two reviewers with published scope, one independent economic attack review, remediated findings, bytecode-linked proof evidence for the named value properties, and a funded bounty | Capped public beta with per-job, per-epoch, and total-at-risk limits |
| G4 — operational beta | Reproducible deployment receipt, verified source and runtime hashes, timelocked roles, monitoring, two independent RPC paths, incident/rollback drills, 90 days without unresolved critical incident, and public SLO/error data | Incremental cap increase approved after a public review window |
| G5 — permissionless scale | Independent operators, churn/partition/byzantine tests, H1–H5 evidence, measured bond inequalities, governance capture analysis, and reserve/runway compliance | Only the exposure justified by measured detection, liquidity, and recovery bounds |

No “formally verified,” “correct by construction,” “trustless,” or loss-guarantee claim should appear in product material unless the evidence index names the exact property, artifact, code/bytecode revision, assumptions, TCB, and excluded behaviors.

## Launch sequence

### Days 0 to 30

- complete the replay-slashing fix and make every assurance gate executable,
- run the preregistered 20-interview H0 demand test and send 10 priced proposals,
- secure three design partners,
- form the operating entity and obtain securities, money-transmission, sanctions, tax, and stable-asset advice,
- publish the threat model and proof scope, and
- launch no token.

### Days 31 to 60

- run Guardian on PulseChain testnet,
- operate at least three miners and five evaluators,
- add typed signed work receipts,
- complete G1 and G2 for the first conservation and nullifier settlement kernel on testnet,
- commission independent review, and
- rehearse incident and rollback procedures.

### Days 61 to 90

- launch a value-capped mainnet beta only after G3,
- use at least seven independent evaluators,
- enforce per-job and per-epoch value caps,
- open a public dashboard and bug bounty,
- require two independent RPCs and reproducible deployment receipts, and
- fund rewards primarily from customer payments.

### Days 90 to 180

- add Pulse Data,
- permissionlessly onboard miners under bounded exposure,
- run anti-collusion and demand-allocation experiments,
- expand caps only after G4 evidence and a public review window, and
- make a token decision only if the measurable demand gates are satisfied.

## Legal boundary

This plan is not legal advice, and product labels or decentralization rhetoric do not determine legal treatment. The March 2026 SEC interpretation describes categories including functional digital commodities and digital tools, while explaining that even an asset that is not itself a security can be offered or sold as part of an investment contract depending on promises, purchaser expectations, and the issuer’s continuing essential managerial efforts. Classification is facts-and-circumstances specific and does not resolve commodities, money-transmission, consumer-protection, tax, sanctions, privacy, employment, or state law. See the [SEC fact sheet](https://www.sec.gov/files/33-11412-fact-sheet.pdf) and [SEC release](https://www.sec.gov/newsroom/press-releases/2026-30-sec-clarifies-application-federal-securities-laws-crypto-assets).

FinCEN’s 2019 guidance distinguishes merely developing a DApp from operating or using one in ways that accept and transmit value, but “noncustodial” and pull settlement are not automatic safe harbors; actual control, business model, fees, and transaction flow matter. See [FinCEN’s CVC guidance](https://www.fincen.gov/system/files/2019-05/FinCEN%20Guidance%20CVC%20FINAL%20508.pdf). Before launch, counsel should map each entity and software role, asset and payment path, hosted API, upgrade key, fee, customer jurisdiction, and state exposure. Avoid issuing a dollar-referenced stable asset without a separately approved regulatory and reserve plan. Implement a documented sanctions program appropriate to hosted services and treasury activity, preserve lawful beneficial-ownership/source-of-funds records, and keep lot-level digital-asset tax records. Current official references include [OFAC virtual-currency guidance](https://ofac.treasury.gov/media/913571/download?inline=) and [IRS digital-asset guidance](https://www.irs.gov/filing/digital-assets).

## Decision

PulseTensor should remain PLS-native while it builds paid Guardian and Data utility. Its next protocol breakthrough is not another emission curve. It is an evidence-bearing work market whose small settlement kernel can state exactly what is proven, what is statistically supported, what is economically assumed, and what remains unknown.
