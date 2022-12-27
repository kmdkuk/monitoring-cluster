KIND_VERSION = 0.17.0
KUBERNETES_VERSION = 1.23.13
KUSTOMIZE_VERSION = 4.2.0

GRAFANA_OPERATOR_VERSION = 4.6.0
GRAFANA_PLUGINS_INIT_VERSION = 0.0.6
LOKI_VERSION = 2.7.1

# related loki version
MEMCACHED_VERSION = 1.6.16.1
MEMCACHED_EXPORTER_VERSION = 0.10.0.1

VICTORIA_METRICS_OPERATOR_VERSION = 0.29.2

# related victoria metrics
VICTORIA_METRICS_VERSION = 1.80.0.1
ALERTMANAGER_VERSION = 0.24.0.3
CONFIGMAP_RELOAD_VERSION = 0.7.1.2
PROMETHEUS_CONFIG_RELOADER_VERSION = 0.55.1.1

K8S_LIBSONNET_VERSION = 1.21
TANKA_VERSION = 0.21.0
JSONNET_BUILDER_VERSION := 0.5.1
YQ_VERSION := 4.24.5

BIN_DIR := $(abspath $(CURDIR)/bin)
KIND := ${BIN_DIR}/kind
KUBECTL := ${BIN_DIR}/kubectl
KUSTOMIZE := ${BIN_DIR}/kustomize

TK := $(BIN_DIR)/tk
JB := $(BIN_DIR)/jb
YQ := $(BIN_DIR)/yq

VM_OPERATOR_VERSION = 0.29.2

.PHONY: start
start:
	$(KIND) create cluster --image kindest/node:v$(KUBERNETES_VERSION) --name=monitoring --config cluster-config/cluster-config.yaml
	$(KUBECTL) create ns monitoring
	$(KUBECTL) create ns logging

.PHONY: stop
stop:
	$(KIND) delete cluster --name=monitoring

.PHONY: create-minio
create-minio:
	$(KUBECTL) create secret generic loki-data-bucket -n logging \
		--save-config \
		--dry-run=client \
		--from-literal=AWS_ACCESS_KEY_ID="minioadmin" \
		--from-literal=AWS_SECRET_ACCESS_KEY="minioadmin" \
		-o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) apply -f minio/minio.yaml
	$(KUBECTL) apply -f minio/minio-client.yaml
	$(KUBECTL) wait -n logging pod/minio-0 --for condition=ready --timeout 3m
	$(KUBECTL) wait -n logging pod -l app=minio-client --for condition=ready --timeout 3m
	$(KUBECTL) exec -n logging deploy/minio-client -it -- bash -c 's3cmd --host=$${BUCKET_HOST} \
		--host-bucket=$${BUCKET_HOST} --no-ssl --access_key=$${AWS_ACCESS_KEY_ID} \
		--secret_key=$${AWS_SECRET_ACCESS_KEY} mb s3://$${BUCKET_NAME}'

.PHONY: get-grafana-password
get-grafana-password:
	$(KUBECTL)  get secret -n monitoring grafana-admin-credentials -o jsonpath="{.data.GF_SECURITY_ADMIN_PASSWORD}" | base64 -d; echo

.PHONY: grafana-port-forward
grafana-port-forward:
	$(MAKE) get-grafana-password
	$(KUBECTL) port-forward -n monitoring svc/grafana-service 3000:3000

.PHONY: update-all
update-all: update-grafana-operator update-loki update-victoriametrics-operator

.PHONY: update-grafana-operator
update-grafana-operator:
	rm -rf /tmp/grafana-operator
	cd /tmp; git clone --depth 1 -b v${GRAFANA_OPERATOR_VERSION} https://github.com/grafana-operator/grafana-operator
	rm -rf grafana-operator/upstream/*
	mkdir -p grafana-operator/upstream/cluster_roles
	mkdir -p grafana-operator/upstream/manifests
	cp -r /tmp/grafana-operator/deploy/cluster_roles/* grafana-operator/upstream/cluster_roles
	cp -r /tmp/grafana-operator/deploy/manifests/latest/* grafana-operator/upstream/manifests
	rm -rf /tmp/grafana-operator
	sed -i -E '/newName:.*grafana-operator$$/!b;n;s/newTag:.*$$/newTag: ${GRAFANA_OPERATOR_VERSION}.1/' grafana-operator/kustomization.yaml
	sed -i -E 's/grafana-plugins-init-container-tag=.*$$/grafana-plugins-init-container-tag=${GRAFANA_PLUGINS_INIT_VERSION}.1/' grafana-operator/deployment.yaml

.PHONY: update-loki
update-loki:
	rm -rf /tmp/loki
	mkdir /tmp/loki
	cd /tmp/loki; \
	$(TK) init --k8s $(K8S_LIBSONNET_VERSION) && \
	$(TK) env add environments/loki --namespace=logging && \
	$(TK) env add environments/loki-canary --namespace=logging && \
	$(JB) install github.com/grafana/loki/production/ksonnet/loki@v${LOKI_VERSION} && \
	$(JB) install github.com/grafana/loki/production/ksonnet/loki-canary@v${LOKI_VERSION}

	cp loki/upstream/main.jsonnet /tmp/loki/environments/loki/main.jsonnet
	rm -rf loki/upstream/generated/*
	cd /tmp/loki && \
	$(TK) export $(shell pwd)/loki/upstream/generated environments/loki/ -t '!.*/consul(-sidekick)?'

	sed -i -E '/name:.*loki$$/!b;n;s/newTag:.*$$/newTag: ${LOKI_VERSION}.1/' loki*/kustomization.yaml

	sed -i -E '/name:.*memcached$$/!b;n;s/newTag:.*$$/newTag: ${MEMCACHED_VERSION}/' loki/kustomization.yaml
	sed -i -E '/name:.*memcached-exporter$$/!b;n;s/newTag:.*$$/newTag: ${MEMCACHED_EXPORTER_VERSION}/' loki/kustomization.yaml

.PHONY: update-victoriametrics-operator
update-victoriametrics-operator:
	rm -rf /tmp/operator
	cd /tmp; git clone --depth 1 -b v${VICTORIA_METRICS_OPERATOR_VERSION} https://github.com/VictoriaMetrics/operator
	rm -rf victoriametrics/upstream/*
	cp -r /tmp/operator/config/crd /tmp/operator/config/rbac victoriametrics/upstream/
	rm -rf /tmp/operator
	sed -i -E 's,quay.io/cybozu/victoriametrics-operator:.*$$,quay.io/cybozu/victoriametrics-operator:${VICTORIA_METRICS_OPERATOR_VERSION}.1,' victoriametrics/operator.yaml

.PHONY: update-victoriametrics
update-victoriametrics:
	sed -i -E '/name: VM_VMALERTDEFAULT_VERSION$$/!b;n;s/value:.*$$/value: "${VICTORIA_METRICS_VERSION}"/' victoriametrics/operator.yaml
	sed -i -E '/name: VM_VMAGENTDEFAULT_VERSION$$/!b;n;s/value:.*$$/value: "${VICTORIA_METRICS_VERSION}"/' victoriametrics/operator.yaml
	sed -i -E '/name: VM_VMSINGLEDEFAULT_VERSION$$/!b;n;s/value:.*$$/value: "${VICTORIA_METRICS_VERSION}"/' victoriametrics/operator.yaml
	sed -i -E '/name: VM_VMCLUSTERDEFAULT_VMSELECTDEFAULT_VERSION$$/!b;n;s/value:.*$$/value: "${VICTORIA_METRICS_VERSION}"/' victoriametrics/operator.yaml
	sed -i -E '/name:.*victoriametrics-vmselect$$/!b;n;s/newTag:.*$$/newTag: ${VICTORIA_METRICS_VERSION}/' victoriametrics/kustomization.yaml
	sed -i -E '/name: VM_VMCLUSTERDEFAULT_VMSTORAGEDEFAULT_VERSION$$/!b;n;s/value:.*$$/value: "${VICTORIA_METRICS_VERSION}"/' victoriametrics/operator.yaml
	sed -i -E '/name: VM_VMCLUSTERDEFAULT_VMINSERTDEFAULT_VERSION$$/!b;n;s/value:.*$$/value: "${VICTORIA_METRICS_VERSION}"/' victoriametrics/operator.yaml
	sed -i -E '/name: VM_VMALERTMANAGER_ALERTMANAGERVERSION$$/!b;n;s/value:.*$$/value: "${ALERTMANAGER_VERSION}"/' victoriametrics/operator.yaml
	sed -i -E 's,quay.io/cybozu/configmap-reload:.*$$,quay.io/cybozu/configmap-reload:${CONFIGMAP_RELOAD_VERSION},' victoriametrics/operator.yaml
	sed -i -E 's,quay.io/cybozu/prometheus-config-reloader:.*$$,quay.io/cybozu/prometheus-config-reloader:${PROMETHEUS_CONFIG_RELOADER_VERSION},' victoriametrics/operator.yaml

.PHONY: setup-tools
setup-tools: $(KIND) $(KUBECTL) $(KUSTOMIZE) $(TK) $(JB) $(YQ)
	$(KIND) version
	$(KUBECTL) version
	$(KUSTOMIZE) version
	$(TK) --version
	$(JB) --version
	$(YQ) --version

$(KIND):
	mkdir -p ${BIN_DIR}
	curl -sfL -o $@ https://github.com/kubernetes-sigs/kind/releases/download/v$(KIND_VERSION)/kind-linux-amd64
	chmod a+x $@

$(KUBECTL):
	mkdir -p ${BIN_DIR}
	curl -sfL -o $@ https://dl.k8s.io/release/v$(KUBERNETES_VERSION)/bin/linux/amd64/kubectl
	chmod a+x $@

$(KUSTOMIZE):
	mkdir -p ${BIN_DIR}
	wget -O /tmp/kustomize.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v$(KUSTOMIZE_VERSION)_linux_amd64.tar.gz
	tar zxf /tmp/kustomize.tar.gz -C ${BIN_DIR}
	rm /tmp/kustomize.tar.gz

$(TK):
	wget -O $@ https://github.com/grafana/tanka/releases/download/v$(TANKA_VERSION)/tk-linux-amd64
	chmod +x $@

$(JB):
	wget -O $@ https://github.com/jsonnet-bundler/jsonnet-bundler/releases/download/v$(JSONNET_BUILDER_VERSION)/jb-linux-amd64
	chmod +x $@

$(YQ):
	wget -O /tmp/yq.tar.gz https://github.com/mikefarah/yq/releases/download/v$(YQ_VERSION)/yq_linux_amd64.tar.gz
	tar -C ${BIN_DIR} -zxf /tmp/yq.tar.gz ./yq_linux_amd64 -O > $@
	chmod +x $@
