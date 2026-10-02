.PHONY: verify verify-quick test

verify:
	@bash scripts/verify.sh

verify-quick:
	@bash scripts/verify.sh --quick

test:
	@bash hooks/tests/run.sh && bash tests/install-test.sh
