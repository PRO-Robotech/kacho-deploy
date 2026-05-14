.PHONY: dev-up dev-down reload-svc logs-svc psql preflight e2e-test helm-lint seed-ipam \
        ci-images ci-up ci-down ci-logs ci-seed \
        loadtest-address-allocate loadtest-address-allocate-clean

CLUSTER_NAME := kacho

# --- CI docker-compose stack (newman E2E) ---------------------------------
# Lightweight non-kind stack for the kacho-vpc/ + kacho-compute/ newman regression
# suites. Separate from the kind+helm dev-stand above; api-gateway is on host port
# 28080 (NOT 18080 — that belongs to the dev-stand). See ci/docker-compose.yml.
CI_COMPOSE   := ci/docker-compose.yml
CI_PROJECT   := kacho-ci
PROJECT_ROOT := $(abspath ..)        # cloud-demo/kacho-workspace/project — Docker build context

# Build the :dev images this stack needs, only if they're not present.
# (Build context is the workspace `project/` dir — same as each repo's `make docker`.)
ci-images:
	@for svc in resource-manager vpc compute api-gateway; do \
		if ! docker image inspect kacho-$$svc:dev >/dev/null 2>&1; then \
			echo "=== building kacho-$$svc:dev ==="; \
			docker build -f $(PROJECT_ROOT)/kacho-$$svc/Dockerfile -t kacho-$$svc:dev $(PROJECT_ROOT); \
		else \
			echo "kacho-$$svc:dev already present (skip build; 'docker rmi kacho-$$svc:dev' to force rebuild)"; \
		fi; \
	done

# Bring up the stack and seed fixtures. Writes ci/.seeded-ids.env (sourced by CI).
ci-up: ci-images
	docker compose -p $(CI_PROJECT) -f $(CI_COMPOSE) up -d
	BASE_URL=http://localhost:28080 OUT=ci/.seeded-ids.env ./ci/seed.sh
	@echo
	@echo "CI stack up. api-gateway: http://localhost:28080  (seeded ids in ci/.seeded-ids.env)"

# Re-run the seed step against an already-running stack (idempotent).
ci-seed:
	BASE_URL=http://localhost:28080 OUT=ci/.seeded-ids.env ./ci/seed.sh

ci-down:
	docker compose -p $(CI_PROJECT) -f $(CI_COMPOSE) down -v
	@rm -f ci/.seeded-ids.env

ci-logs:
	docker compose -p $(CI_PROJECT) -f $(CI_COMPOSE) logs --tail=200

preflight:
	@command -v docker >/dev/null || { echo "ERROR: docker not installed"; exit 1; }
	@command -v kind >/dev/null || { echo "ERROR: kind not installed (install from https://kind.sigs.k8s.io/)"; exit 1; }
	@command -v kubectl >/dev/null || { echo "ERROR: kubectl not installed"; exit 1; }
	@command -v helm >/dev/null || { echo "ERROR: helm not installed"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "ERROR: docker daemon is not running"; exit 1; }
	@if ss -tln | grep -q ':28080 '; then echo "ERROR: port 28080 is already in use, free it or change kind/kind-config.yaml"; exit 1; fi
	@grep -q "api.kacho.local" /etc/hosts || echo "WARN: '127.0.0.1 api.kacho.local' missing in /etc/hosts — ingress will not resolve from host"
	@echo "preflight OK"

dev-up: preflight
	@start=$$(date +%s); \
	kind get clusters | grep -q "^$(CLUSTER_NAME)$$" || ./kind/create-cluster.sh; \
	kubectl config use-context kind-$(CLUSTER_NAME); \
	cd helm/umbrella && helm dep update >/dev/null && cd ../..; \
	helm upgrade --install kacho-umbrella ./helm/umbrella -n kacho --create-namespace -f ./helm/umbrella/values.dev.yaml --wait --timeout 5m; \
	echo "Waiting for ingress-nginx admission webhook..."; \
	kubectl -n kacho wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=60s; \
	end=$$(date +%s); \
	echo "dev-up complete in $$((end-start))s"; \
	echo; \
	echo "API endpoint: http://api.kacho.local (add '127.0.0.1 api.kacho.local' to /etc/hosts if missing)"

dev-down:
	kind delete cluster --name $(CLUSTER_NAME) || true

helm-lint:
	cd helm/umbrella && helm dep update >/dev/null && helm lint -f values.dev.yaml

reload-svc:
ifndef SVC
	$(error SVC variable is required, e.g. make reload-svc SVC=compute)
endif
	@if [ "$(SVC)" != "resource-manager" ] && [ "$(SVC)" != "vpc" ] && [ "$(SVC)" != "compute" ] && [ "$(SVC)" != "loadbalancer" ] && [ "$(SVC)" != "api-gateway" ]; then \
		echo "ERROR: unknown service '$(SVC)'"; exit 1; \
	fi; \
	if ! kubectl -n kacho get deploy $(SVC) >/dev/null 2>&1; then \
		echo "WARN: service '$(SVC)' is not deployed yet (planned for sub-phase 0.X — see roadmap)"; \
		exit 0; \
	fi; \
	cd .. && docker build -f kacho-$(SVC)/Dockerfile -t kacho-$(SVC):dev . && \
	kind load docker-image kacho-$(SVC):dev --name $(CLUSTER_NAME) && \
	kubectl rollout restart -n kacho deployment/$(SVC)

logs-svc:
ifndef SVC
	$(error SVC variable is required)
endif
	kubectl logs -n kacho -f deploy/$(SVC)

psql:
ifndef SVC
	$(error SVC variable is required)
endif
	kubectl exec -it -n kacho statefulset/pg-$(SVC) -- psql -U $(SVC) -d kacho_$(SVC)

seed-ipam:
	@echo "seed-ipam: NOOP. Auto-seeding отключён — admin должен явно создать AddressPool через kachoctl-ipam."
	@echo
	@echo "  cd ../kacho-vpc && make build-ipam"
	@echo "  kubectl -n kacho port-forward svc/vpc 19091:9091 &"
	@echo "  ./bin/kachoctl-ipam -addr localhost:19091 pool create \\"
	@echo "    --folder <real_folder_id_from_resource_manager> \\"
	@echo "    --kind EXTERNAL_PUBLIC \\"
	@echo "    --region-id ru-central1 \\"
	@echo "    --cidr 198.51.100.0/24 \\"
	@echo "    --is-default \\"
	@echo "    --name production-pool"

e2e-test:
	@for sh in e2e/0.1/*.sh; do \
		echo "=== $$sh ==="; \
		bash "$$sh" || exit 1; \
	done

# ─── Load testing ────────────────────────────────────────────────

loadtest-address-allocate:
	@kubectl -n kacho delete job k6-address-allocate --ignore-not-found
	@kubectl -n kacho apply -f load-tests/k6-address-allocate.yaml
	@echo "→ Job created, waiting for completion (max 600s)…"
	@kubectl -n kacho wait --for=condition=complete job/k6-address-allocate --timeout=600s || \
	  kubectl -n kacho wait --for=condition=failed job/k6-address-allocate --timeout=10s
	@kubectl -n kacho logs -l job-name=k6-address-allocate --tail=-1

loadtest-address-allocate-clean:
	@kubectl -n kacho delete job k6-address-allocate --ignore-not-found
	@kubectl -n kacho delete cm k6-address-allocate --ignore-not-found
