.PHONY: build test fmt deploy preset synth-goal-frontier synth-tokenomics-frontier synth-participant-regret-frontier ui-install ui-dev ui-build ui-preview ui-test ui-reproducible ui-release-test ui-exact-manifest ui-hash ui-release ui-ipfs verify-ui verify-private verify-goal-frontier verify-tokenomics-frontier verify-participant-regret-frontier verify-compiler-bugs verify-deploy-size verify-local-e2e verify-requirements-traceability verify-security-controls verify-security-antipatterns verify-solhint verify-slither-exclusions verify-slither verify-mythril-allowlist verify-mythril verify-fuzz-invariant verify-echidna-harness verify-echidna write-assurance-evidence verify-assurance-evidence verify-artifacts-security verify-artifacts-release verify-artifacts-complete verify-security verify-all verify-dev verify-release verify-release-full verify-complete

build:
	forge build

test:
	forge test

fmt:
	forge fmt

deploy:
	bash scripts/deploy_pulsetensor.sh $${DEPLOY_ARGS:?set DEPLOY_ARGS with --expected-chain-id and one protected signer}

preset:
	bash scripts/render_launch_preset.sh --preset "$${PRESET:?set PRESET}" --netuid "$${NETUID:?set NETUID}" $${MECHID:+--mechid "$${MECHID}"} $${CORE:+--core "$${CORE}"} $${SETTLEMENT:+--settlement "$${SETTLEMENT}"} $${GOVERNANCE:+--governance "$${GOVERNANCE}"} $${OUT:+--out "$${OUT}"}

synth-goal-frontier:
	python3 scripts/synthesize_goal_frontier.py --model configs/formal/pulsetensor_emergency_mode_goal_frontier.json --out runs/formal/pulsetensor_emergency_mode_goal_frontier.report.json

synth-tokenomics-frontier:
	python3 scripts/synthesize_goal_frontier.py --model configs/formal/pulsetensor_tokenomics_goal_frontier.json --out runs/formal/pulsetensor_tokenomics_goal_frontier.report.json

synth-participant-regret-frontier:
	python3 scripts/synthesize_goal_frontier.py --model configs/formal/pulsetensor_participant_regret_goal_frontier.json --out runs/formal/pulsetensor_participant_regret_goal_frontier.report.json

ui-install:
	npm --prefix frontend ci

ui-dev:
	npm --prefix frontend run dev

ui-build:
	npm --prefix frontend run build

ui-preview:
	npm --prefix frontend run preview

ui-test:
	npm --prefix frontend test

ui-reproducible:
	npm --prefix frontend run reproducible

ui-release-test:
	bash scripts/test_frontend_release_hardening.sh

ui-exact-manifest:
	npm --prefix frontend run prepare-exact-manifest -- --input "$${INPUT:?set INPUT to candidate JSON}" --output "$${OUTPUT:?set OUTPUT to canonical JSON}" --receipt "$${RECEIPT:?set RECEIPT to digest receipt JSON}"

ui-hash:
	bash scripts/hash_frontend_dist.sh

ui-release:
	bash scripts/release_frontend_community.sh

ui-ipfs:
	bash scripts/publish_frontend_ipfs.sh

verify-ui:
	npm --prefix frontend test
	npm --prefix frontend run check
	bash scripts/test_frontend_release_hardening.sh
	npm --prefix frontend run build
	bash scripts/check_frontend_dist_portable.sh frontend/dist
	npm --prefix frontend run reproducible

verify-private:
	bash scripts/check_private_boundaries.sh

verify-goal-frontier:
	bash scripts/check_goal_frontier_example.sh

verify-tokenomics-frontier:
	bash scripts/check_tokenomics_goal_frontier.sh

verify-participant-regret-frontier:
	bash scripts/check_participant_regret_frontier.sh

verify-compiler-bugs:
	bash scripts/check_compiler_known_bugs.sh

verify-deploy-size:
	bash scripts/check_deploy_code_size.sh

verify-local-e2e:
	bash scripts/check_local_e2e.sh

verify-requirements-traceability:
	bash scripts/check_requirements_traceability.sh

verify-security-controls:
	bash scripts/check_security_controls.sh

verify-security-antipatterns:
	bash scripts/check_security_antipatterns.sh

verify-solhint:
	bash scripts/check_solhint.sh

verify-slither-exclusions:
	bash scripts/check_slither_exclusions.sh

verify-slither:
	bash scripts/check_slither.sh

verify-mythril-allowlist:
	bash scripts/check_mythril_allowlist.sh

verify-mythril:
	bash scripts/check_mythril.sh

verify-fuzz-invariant:
	bash scripts/check_fuzz_invariant.sh

verify-echidna-harness:
	bash scripts/test_echidna_harness_checker.sh

verify-echidna:
	bash scripts/check_echidna.sh

write-assurance-evidence:
	bash scripts/write_assurance_evidence.sh

verify-assurance-evidence:
	bash scripts/verify_assurance_evidence.sh

verify-artifacts-security:
	bash scripts/check_artifact_freshness.sh docs/security/artifact_manifest.security.txt

verify-artifacts-release:
	bash scripts/check_artifact_freshness.sh docs/security/artifact_manifest.release.txt

verify-artifacts-complete:
	bash scripts/check_artifact_freshness.sh docs/security/artifact_manifest.complete.txt

verify-security:
	bash scripts/check_security.sh

verify-all:
	bash scripts/verify_all.sh

verify-dev:
	RUN_SECURITY=0 bash scripts/verify_all.sh

verify-release:
	bash scripts/verify_release.sh

verify-release-full:
	bash scripts/verify_release_full.sh

verify-complete:
	bash scripts/verify_complete.sh
