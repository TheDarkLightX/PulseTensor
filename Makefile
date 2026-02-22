.PHONY: build test fmt verify-private verify-compiler-bugs verify-security-controls verify-security-antipatterns verify-solhint verify-slither-exclusions verify-slither verify-mythril-allowlist verify-mythril verify-fuzz-invariant verify-echidna verify-artifacts-security verify-artifacts-release verify-security verify-esso verify-morph verify-zag verify-orch verify-all verify-dev verify-release verify-release-full

build:
	forge build

test:
	forge test

fmt:
	forge fmt

verify-private:
	bash scripts/check_private_boundaries.sh

verify-compiler-bugs:
	bash scripts/check_compiler_known_bugs.sh

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

verify-echidna:
	bash scripts/check_echidna.sh

verify-artifacts-security:
	bash scripts/check_artifact_freshness.sh docs/security/artifact_manifest.security.txt

verify-artifacts-release:
	bash scripts/check_artifact_freshness.sh docs/security/artifact_manifest.release.txt

verify-security:
	bash scripts/check_security.sh

verify-esso:
	bash scripts/check_esso.sh

verify-morph:
	bash scripts/check_morph.sh

verify-zag:
	bash scripts/check_zag.sh

verify-orch:
	bash scripts/check_orch_unit.sh

verify-all:
	bash scripts/verify_all.sh

verify-dev:
	RUN_MORPH=0 RUN_ZAG=0 RUN_ORCH=1 RUN_SECURITY=0 bash scripts/verify_all.sh

verify-release:
	bash scripts/verify_release.sh

verify-release-full:
	bash scripts/verify_release_full.sh
