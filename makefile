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

PAUSE ?= 0

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
	echo "# VERSION: $(VERSION)"
	echo "# deploy_target=$(deploy_target)"
	echo "# google_project=$(google_project)"
	echo "# google_region=$(google_region)"
	echo "# gpg_key=$(gpg_key)"

###############################################################################
# Repo Version
###############################################################################

version:
	echo $$(date +%y.%m.%d-%H%M) >| VERSION
	git add VERSION
	echo "VERSION: $$(cat VERSION)"

commit: version
	git add --all
	git commit -m "$$(cat VERSION)"

tag:
	git tag $$(cat VERSION) -m "$$(cat VERSION)"
	git push --tags

release: tag

###############################################################################
# Terraform
###############################################################################

terraform_dir := $(root_dir)/terraform
terraform_config := ${terraform_dir}/${google_project}.tfvars
terraform_output := $(root_dir)/state/terraform-$(google_project).json
terraform_bucket := terraform-${google_project}
terraform_prefix := ${app_id}

terraform: terraform-plan prompt terraform-apply gke-credentials

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
	$(call header,Run Terraform Clean)
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

vault_vars += --set="vault_ver=$(vault_ver)"
vault_vars += --set="vault_tls_key=$(vault_tls_key)"

vault: vault-deploy vault-running vault-init vault-unseal vault-ready vault-cluster-members vault-cluster-status vault-disks-list

vault-restart: vault-pod-restart vault-running vault-unseal vault-ready vault-cluster-members vault-cluster-status

vault-template:
	helm template vault $(vault_dir) --namespace $(vault_namespace) $(vault_vars)

vault-template-original: .vault-helm-repo
	helm template vault  hashicorp/vault --namespace $(vault_namespace) \
	--set="injector.enabled=false" \
	--set="server.ha.enabled=true" \
	--set="server.ha.replicas=3"

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

vault-running:
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

vault-ready:
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
	for key in 0 1 2; do
		kubectl exec -n $(vault_namespace) vault-0 -- vault operator unseal $$(jq -r .unseal_keys_b64[$$key] $(vault_unseal_keys))
		kubectl exec -n $(vault_namespace) vault-1 -- vault operator unseal $$(jq -r .unseal_keys_b64[$$key] $(vault_unseal_keys))
		kubectl exec -n $(vault_namespace) vault-2 -- vault operator unseal $$(jq -r .unseal_keys_b64[$$key] $(vault_unseal_keys))
	done

vault-join: $(vault_unseal_keys)
	for key in 0 1 2; do
		kubectl exec -n $(vault_namespace) vault-0 -- vault operator unseal $$(jq -r .unseal_keys_b64[$$key] $(vault_unseal_keys))
	done
	kubectl exec -n $(vault_namespace) vault-0 -- vault operator raft join -leader-ca-cert="/vault/certs/tls.ca" https://vault-0.cluster:8200
	kubectl exec -n $(vault_namespace) vault-1 -- vault operator raft join -leader-ca-cert="/vault/certs/tls.ca" https://vault-0.cluster:8200
	kubectl exec -n $(vault_namespace) vault-2 -- vault operator raft join -leader-ca-cert="/vault/certs/tls.ca" https://vault-0.cluster:8200

vault-cluster-wait: vault-login
	$(call header,Wait for Hashicorp Vault Cluster to reconcile)
	while ! kubectl exec -i -n $(vault_namespace) vault-0 -- nc -z -w2 active 8200 2>/dev/null; do
		echo "Waiting for Hashicorp Vault Cluster to reconcile..."
		sleep 5
	done

vault-cluster-status: vault-cluster-wait
	$(call header,Check Vault Cluster Status)
	kubectl exec -i -n $(vault_namespace) vault-0 -- vault status -address=https://active:8200

vault-cluster-members: vault-cluster-wait
	$(call header,Check Vault Cluster Members)
	kubectl exec -i -n $(vault_namespace) vault-0 -- vault operator raft list-peers -address=https://active:8200

vault-token: $(vault_token)
$(vault_token):
	jq -r '.root_token' secrets/vault-unseal-keys.json | tee $(@)

vault-login: $(vault_token)
	kubectl cp -n $(vault_namespace) $(vault_token) vault-0:/home/vault/.vault-token

$(vault_disks):
	gcloud compute disks list --filter='pvc-' --format=json > $(@)

vault-disks-list: $(vault_disks)
	$(call header,List Vault Disks)
	jq '[.[] | {name: .name, lastAttachTimestamp: .lastAttachTimestamp, selfLink: .selfLink}]' $(vault_disks)

vault-disks-delete: $(vault_disks)
	$(call header,Delete Vault Disks)
	jq '.[].selfLink' $(vault_disks) | xargs -I {} gcloud compute disks delete {} --quiet && rm -rf $(vault_disks) || exit 1

.vault-helm-repo:
	$(call header,Configure Hashicorp Helm repository)
	helm repo add hashicorp https://helm.releases.hashicorp.com
	helm repo update
	touch $@

vault-helm-list: .vault-helm-repo
	$(call header,List Hashicorp Helm versions)
	helm search repo hashicorp/vault

vault-uninstall:
	$(call header,Uninstall Hashicorp Vault)
	helm uninstall vault --namespace $(vault_namespace) --wait

vault-clean:
	$(call header,Reset Vault Config)
	set -e
	$(MAKE) vault-disks-delete
	rm -rf .vault-helm-repo $(vault_token) $(vault_unseal_keys) $(vault_unseal_keys).asc

###############################################################################
# Hashicorp Vault Secrets Operator
# Docs: https://developer.hashicorp.com/vault/docs/platform/k8s/vso
###############################################################################

vault_opr_ver := 0.5.2

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
gcloud-auth:
	$(call header,Configure Google CLI)
	gcloud auth application-default login

gcloud-config:
	set -e
	gcloud config set core/project ${google_project}
	gcloud config set compute/region ${google_region}
	gcloud config list

gcloud-version:
	$(call header,gcloud version)
	gcloud version

###############################################################################
# Kubernetes (GKE)
###############################################################################

KUBECONFIG ?= ${HOME}/.kube/config

gke-credentials:
	$(call header,Get GKE Credentials)
	set -e
	-rm -f ${KUBECONFIG}
	gcloud container clusters get-credentials --zone=${google_region} ${gke_name}
	kubectl cluster-info

###############################################################################
# Checkov
###############################################################################

checkov_args := --soft-fail --enable-secret-scan-all-files --compact --deep-analysis --directory .

.checkov.baseline:
	echo "{}" >| $@

checkov: .checkov.baseline
	$(call header,Run Checkov with baseline)
	checkov --baseline .checkov.baseline ${checkov_args}

checkov-all:
	$(call header,Run Checkov NO baseline)
	checkov --quiet ${checkov_args}

checkov-baseline:
	$(call header,Create Checkov baseline)
	checkov --quiet --create-baseline ${checkov_args}

checkov-clean:
	rm -rf .checkov.baseline

checkov-install:
	pipx install checkov

checkov-upgrade:
	pipx upgrade checkov

###############################################################################
# Demo
###############################################################################

demo: demo-checkov demo-terraform

demo-checkov:
	asciinema rec -t "llmdocs-infra - checkov" -c "PAUSE=3 make checkov"

demo-terraform:
	asciinema rec -t "llmdocs-infra - terraform" -c "PAUSE=3 make terraform-plan prompt terraform-apply"

demo-vault:
	asciinema rec -t "llmdocs-infra - vault" -c "PAUSE=4 make settings vault"

###############################################################################
# Prompt
###############################################################################

prompt:
	echo
	read -p "Continue deployment? (yes/no): " INP
	if [ "$${INP}" != "yes" ]; then
	  echo "Deployment aborted"
	  exit 1
	fi

###############################################################################
# Functions
###############################################################################
define header
echo
echo "###############################################################################"
echo "# $(1)"
echo "###############################################################################"
sleep ${PAUSE}
endef

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
