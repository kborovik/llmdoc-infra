.EXPORT_ALL_VARIABLES:
.ONESHELL:
.SILENT:

MAKEFLAGS += --no-builtin-rules --no-builtin-variables

###############################################################################
# Variables
###############################################################################

deploy_target ?= dev1

ifeq ($(deploy_target),dev1)
google_project := lab5-llmdoc-dev1
google_region := us-east5
google_zone := ${google_region}-b
endif

###############################################################################
# Settings
###############################################################################

app_id := llmdoc

gke_name := $(app_id)-01

VERSION := $(file < VERSION)

gpg_key := 1A4A6FC0BB90A4B5F2A11031E577D405DD6ABEA5

root_dir := $(abspath .)

###############################################################################
# Settings
###############################################################################

settings:
	$(call header,Settings)
	$(call var,VERSION,$(VERSION))
	$(call var,deploy_target,$(deploy_target))
	$(call var,google_project,$(google_project))
	$(call var,google_region,$(google_region))
	$(call var,gpg_key,$(gpg_key))

###############################################################################
# End-to-End Pipeline
###############################################################################

all: terraform vault

clean: vault-clean terraform-clean gke-clean

###############################################################################
# Terraform
###############################################################################

terraform_dir := $(root_dir)/terraform
terraform_config := ${terraform_dir}/${google_project}.tfvars
terraform_output := $(root_dir)/state/terraform-$(google_project).json
terraform_bucket := terraform-${google_project}
terraform_prefix := ${app_id}

.PHONY: terraform

terraform: terraform-plan prompt terraform-apply

terraform-fmt: terraform-version
	$(call header,Check Terraform Code Format)
	cd ${terraform_dir}
	terraform fmt -check -recursive

terraform-init: terraform-fmt
	$(call header,Initialize Terraform)
	cd ${terraform_dir}
	terraform init -upgrade -input=false -reconfigure -backend-config="bucket=${terraform_bucket}" -backend-config="prefix=${terraform_prefix}"

terraform-plan: terraform-init
	$(call header,Run Terraform Plan)
	cd ${terraform_dir}
	terraform plan -input=false -refresh=true -var-file="${terraform_config}"

terraform-apply: terraform-init
	$(call header,Run Terraform Apply)
	set -e
	cd ${terraform_dir}
	terraform apply -auto-approve -input=false -refresh=true -var-file="${terraform_config}"
	terraform output -json -no-color >| ${terraform_output}
	gsutil cp ${terraform_output} gs://${terraform_bucket}/${terraform_prefix}/output.json

terraform-destroy: terraform-init
	$(call header,Run Terraform Apply)
	cd ${terraform_dir}
	terraform apply -destroy -input=false -refresh=true -var-file="${terraform_config}"

terraform-clean:
	$(call header,Delete Terraform providers and state)
	-rm -rf ${terraform_dir}/.terraform ${terraform_dir}/.terraform.lock.hcl

terraform-show:
	cd ${terraform_dir}
	terraform show

terraform-version:
	$(call header,Terraform Version)
	terraform version

terraform-state-list:
	cd ${terraform_dir}
	terraform state list

terraform-state-recursive:
	gsutil ls -r gs://${terraform_bucket}/**

terraform-state-versions:
	gsutil ls -a gs://${terraform_bucket}/${terraform_prefix}/default.tfstate

terraform-state-unlock:
	gsutil rm gs://${terraform_bucket}/${terraform_prefix}/default.tflock

terraform-bucket-create:
	$(call header,Create Terrafomr state GCS bucket)
	set -e
	gsutil mb -p $(google_project) -l ${google_region} -b on gs://${terraform_bucket} || true
	gsutil ubla set on gs://${terraform_bucket}
	gsutil versioning set on gs://${terraform_bucket}

###############################################################################
# Hashicorp Vault
# Docs: https://developer.hashicorp.com/vault/docs/platform/k8s/vso
###############################################################################

vault_ver := 1.15.6
vault_namespace := vault
vault_dir := kubernetes/vault
vault_tls_key := $(shell gpg -dq secrets/tls.key.asc | base64 -w0)
vault_token := $(HOME)/.vault-token
vault_unseal_keys := secrets/vault-unseal-keys.json
vault_disks := state/vault-disks-$(google_project).json
vault_kube_dns := vault.vault.svc.cluster.local

vault_vars += --set="vault_ver=$(vault_ver)"
vault_vars += --set="vault_tls_key=$(vault_tls_key)"

vault: vault-deploy vault-pod-running vault-init vault-unseal vault-pod-ready vault-cluster-members vault-cluster-status vault-disks-list

vault-restart: vault-pod-restart vault-pod-running vault-unseal vault-pod-ready vault-cluster-members vault-cluster-status

.hashicorp-helm-repo:
	$(call header,Configure Hashicorp Helm repository)
	helm repo add hashicorp https://helm.releases.hashicorp.com
	helm repo update
	touch $@

vault-template:
	helm template vault $(vault_dir) --namespace $(vault_namespace) $(vault_vars)

vault-set-namespace:
	kubectl config set-context --current --namespace $(vault_namespace)

vault-deploy: vault-set-namespace
	$(call header,Deploy Hashicorp Vault HELM Chart)
	helm upgrade vault $(vault_dir) --install --create-namespace --namespace $(vault_namespace) $(vault_vars)

vault-pod-restart: vault-set-namespace
	$(call header,Restart Hashicorp Vault)
	for pod in 0 1 2; do
		kubectl delete pod vault-$$pod -n $(vault_namespace) --wait=true
	done
	echo "Hashicorp Vault pods restarted. Waiting for pods to be Running..."
	sleep 20

vault-pod-running:
	$(call header,Wait for Hashicorp Vault pods to be Running)
	for pod in 0 1 2; do
		running=$$(kubectl get pods vault-$$pod -n $(vault_namespace) -o jsonpath='{.status.phase}')
		while [ "$$running" != "Running" ]; do
			echo "Waiting for Hashicorp Vault vault-$$pod to be Running..."
			sleep 2
			running=$$(kubectl get pods vault-$$pod -n $(vault_namespace) -o jsonpath='{.status.phase}')
		done
		echo "Hashicorp Vault vault-$$pod is Running"
	done

vault-pod-ready:
	$(call header,Wait for Hashicorp Vault StatefulSet to be Ready)
	ready=""
	while [ "$$ready" != "3" ]; do
		ready=$$(kubectl get statefulsets vault -n $(vault_namespace) --output json | jq '.status.readyReplicas')
		sleep 2
	done
	echo "Hashicorp Vault StatefulSet is Ready"

vault-init: $(vault_unseal_keys)

$(vault_unseal_keys):
	$(call header,Initialize Hashicorp Vault)
	gpg --yes $(@).asc \
	&& exit 0 \
	|| kubectl exec -n $(vault_namespace) vault-0 -- vault operator init -key-shares=5 -key-threshold=3 -format=json > $(@) \
	&& gpg -a -e -r $(gpg_key) $(@) \

vault-unseal: $(vault_unseal_keys)
	$(call header,Unseal Hashicorp Vault)
	for pod in 0 1 2; do
		for key in 0 1 2; do
			kubectl exec -n $(vault_namespace) vault-$$pod -- vault operator unseal $$(jq -r .unseal_keys_b64[$$key] $(vault_unseal_keys))
		done
	done

vault-join: $(vault_unseal_keys)
	for key in 0 1 2; do
		kubectl exec -n $(vault_namespace) vault-0 -- vault operator unseal $$(jq -r .unseal_keys_b64[$$key] $(vault_unseal_keys))
	done
	for pod in 0 1 2; do
		kubectl exec -n $(vault_namespace) vault-$$pod -- vault operator raft join -leader-ca-cert="/vault/certs/tls.ca" https://vault-0.cluster:8200
	done

vault-cluster-wait: vault-login
	$(call header,Wait for Hashicorp Vault Cluster to reconcile)
	while ! kubectl exec -i -n $(vault_namespace) vault-0 -- nc -z -w1 $(vault_kube_dns) 8200 2>/dev/null; do
		echo "Waiting for Hashicorp Vault Cluster to reconcile..."
		sleep 5
	done

vault-cluster-status: vault-cluster-wait
	$(call header,Check Vault Cluster Status)
	kubectl exec -i -n $(vault_namespace) vault-0 -- vault status -address=https://$(vault_kube_dns):8200

vault-cluster-members: vault-cluster-wait
	$(call header,Check Vault Cluster Members)
	kubectl exec -i -n $(vault_namespace) vault-0 -- vault operator raft list-peers -address=https://$(vault_kube_dns):8200

vault-token: $(vault_token)

$(vault_token):
	jq -r '.root_token' secrets/vault-unseal-keys.json >| $(@)

vault-login: $(vault_token)
	kubectl cp -n $(vault_namespace) $(vault_token) vault-0:/home/vault/.vault-token

$(vault_disks):
	gcloud compute disks list --filter='pvc-' --format=json > $(@)

vault-disks-list: $(vault_disks)
	$(call header,List Vault Disks)
	jq '[.[] | {name: .name, lastAttachTimestamp: .lastAttachTimestamp, selfLink: .selfLink}]' $(vault_disks)

vault-disks-delete:
	$(call header,Delete Vault Disks)
	jq '.[].selfLink' $(vault_disks) | xargs -I {} gcloud compute disks delete {} --quiet

vault-helm-list: .hashicorp-helm-repo
	$(call header,List Hashicorp Helm versions)
	helm search repo hashicorp/vault

vault-uninstall:
	$(call header,Uninstall Hashicorp Vault)
	helm uninstall vault --namespace $(vault_namespace)

vault-clean:
	$(call header,Delete Vault token and keys)
	rm -rf .hashicorp-helm-repo $(vault_token) $(vault_unseal_keys)

vault-purge: vault-clean
	$(call header,Purge Vault data)
	rm -rf $(vault_disks) $(vault_unseal_keys).asc

###############################################################################
# Hashicorp Vault Secrets Operator
# Docs: https://developer.hashicorp.com/vault/docs/platform/k8s/vso
###############################################################################
vso_chart_version := 0.6.0

vso_namespace := vault-secrets-operator

vso_values := $(root_dir)/kubernetes/vault-secrets-operator/values.yaml

vso_settings += --set=defaultVaultConnection.enabled=true
vso_settings += --set=defaultVaultConnection.address=https://vault.vault.svc.cluster.local:8200
vso_settings += --set=defaultVaultConnection.skipTLSVerify=true

vso-template: .hashicorp-helm-repo
	$(call header,Template Hashicorp Vault Secrets Operator)
	helm template vso hashicorp/vault-secrets-operator \
	--version $(vso_chart_version) --namespace $(vso_namespace) $(vso_settings)

vso-deploy: .hashicorp-helm-repo
	$(call header,Deploy Hashicorp Vault Secrets Operator)
	helm upgrade vso hashicorp/vault-secrets-operator \
	--version $(vso_chart_version) --namespace $(vso_namespace) \
	--install --create-namespace --wait --timeout=10m --atomic $(vso_settings)

###############################################################################
# ElasticSearch
# Docs: https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-install-helm.html
###############################################################################

elastic_eck_ver := 2.11.1

elastic:

.elastic-helm-repo:
	$(call header,Configure Elastic Helm repository)
	helm repo add elastic https://helm.elastic.co
	helm repo update
	touch $@

elastic-helm-list: .elastic-helm-repo
	$(call header,List Elastic Helm versions)
	helm search repo elastic/eck-operator

elastic-clean:
	$(call header,Reset Elastic Config)
	rm -rf .elastic-helm

###############################################################################
# Google CLI
###############################################################################

google: gcloud-auth gcloud-config

gcloud-auth:
	$(call header,Configure Google CLI)
	set -e
	gcloud auth revoke --all
	gcloud auth login --update-adc

gcloud-config:
	set -e
	gcloud config set core/project ${google_project}
	gcloud config set compute/region ${google_region}
	gcloud config list

###############################################################################
# Kubernetes (GKE)
###############################################################################

KUBECONFIG ?= ${HOME}/.kube/config

kube: kube-clean kube-auth

kube-auth: $(KUBECONFIG)

$(KUBECONFIG):
	$(call header,Get Kubernetes credentials)
	set -e
	gcloud container clusters get-credentials --zone=${google_region} ${gke_name}
	kubectl cluster-info

kube-clean:
	$(call header,Delete Kubernetes credentials)
	rm -rf $(KUBECONFIG)

###############################################################################
# Checkov
###############################################################################

.checkov.baseline:
	echo "{}" >| $@

checkov: .checkov.baseline
	$(call header,Run Checkov with baseline)
	checkov --baseline .checkov.baseline

checkov-all:
	$(call header,Run Checkov NO baseline)
	checkov --quiet

checkov-baseline:
	$(call header,Create Checkov baseline)
	checkov --quiet --create-baseline

checkov-clean:
	rm -rf .checkov.baseline

checkov-install:
	pipx install checkov

checkov-upgrade:
	pipx upgrade checkov

###############################################################################
# Colors and Headers
###############################################################################

black := \033[30m
red := \033[31m
green := \033[32m
yellow := \033[33m
blue := \033[34m
magenta := \033[35m
cyan := \033[36m
white := \033[37m
reset := \033[0m

define header
echo "$(blue)==> $(1) <==$(reset)"
endef

define help
echo "$(green)$(1)$(reset) - $(white)$(2)$(reset)"
endef

define var
echo "$(magenta)$(1)$(reset): $(yellow)$(2)$(reset)"
endef

prompt:
	echo -n "$(blue)Continue?$(reset) $(yellow)(yes/no)$(reset)"
	read -p ": " answer && [ "$$answer" = "yes" ] || exit 1

###############################################################################
# Repo Version
###############################################################################

.PHONY: version

version:
	version=$$(date +%Y.%m.%d-%H%M)
	echo "$$version" >| VERSION
	$(call header,Version: $$(cat VERSION))
	git add VERSION

commit: version
	git add --all
	git commit -m "$$(cat VERSION)"

tag: commit
	version=$$(date +%Y.%m.%d)
	git tag "$$version" -m "Version: $$version"

release: tag
	git push --tags --force

###############################################################################
# Errors
###############################################################################
ifeq ($(shell which gcloud),)
$(error ==> Missing Google CLI https://cloud.google.com/sdk/docs/install <==)
endif

ifeq ($(shell which terraform),)
$(error ==> Missing terraform https://www.terraform.io/downloads <==)
endif

ifeq ($(shell which helm),)
$(error ==> Missing helm https://helm.sh/ <==)
endif
