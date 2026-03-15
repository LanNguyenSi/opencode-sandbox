SHELL := /usr/bin/env bash

.PHONY: help test check install

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make test    Run local smoke tests' \
		'  make check   Run smoke tests plus optional docker compose validation' \
		'  make install Install opencode-sandbox into ~/.local/bin'

test:
	@./tests/smoke.sh

check: test
	@if command -v docker >/dev/null 2>&1; then \
		docker compose config >/dev/null; \
		printf 'docker compose config: ok\n'; \
	else \
		printf 'docker compose config: skipped (docker not found)\n'; \
	fi

install:
	@./install.sh
