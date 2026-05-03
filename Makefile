.PHONY: dev-up dev-down reload-svc logs-svc psql preflight e2e-test helm-lint

CLUSTER_NAME := kacho

preflight:
	@command -v docker >/dev/null || { echo "ERROR: docker not installed"; exit 1; }
	@command -v kind >/dev/null || { echo "ERROR: kind not installed (install from https://kind.sigs.k8s.io/)"; exit 1; }
	@command -v kubectl >/dev/null || { echo "ERROR: kubectl not installed"; exit 1; }
	@command -v helm >/dev/null || { echo "ERROR: helm not installed"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "ERROR: docker daemon is not running"; exit 1; }
	@if ss -tln | grep -q ':80 '; then echo "ERROR: port 80 is already in use, free it or change kind/kind-config.yaml"; exit 1; fi
	@grep -q "api.kacho.local" /etc/hosts || echo "WARN: '127.0.0.1 api.kacho.local' missing in /etc/hosts — ingress will not resolve from host"
	@echo "preflight OK"

dev-up: preflight
	@start=$$(date +%s); \
	kind get clusters | grep -q "^$(CLUSTER_NAME)$$" || ./kind/create-cluster.sh; \
	kubectl config use-context kind-$(CLUSTER_NAME); \
	cd helm/umbrella && helm dep update >/dev/null; \
	helm upgrade --install kacho-umbrella . -n kacho --create-namespace -f values.dev.yaml --wait --timeout 5m; \
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
	cd ../kacho-$(SVC) && docker build -t kacho-$(SVC):dev . && \
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

e2e-test:
	@for sh in e2e/0.1/*.sh; do \
		echo "=== $$sh ==="; \
		bash "$$sh" || exit 1; \
	done
