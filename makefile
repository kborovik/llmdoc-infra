.EXPORT_ALL_VARIABLES:
.ONESHELL:
.SILENT:
MAKEFLAGS += --no-builtin-rules --no-builtin-variables

###############################################################################
# Variables
###############################################################################
app_id := llmdoc

google_project ?= lab5-llmdoc-dev1
google_region ?= us-east5
google_zone ?= ${google_region}-b

gke_name ?= llmdoc-01
PAUSE ?= 0

###############################################################################
# Settings
###############################################################################

VERSION := $(file < VERSION)

root_dir := $(abspath .)

terraform_dir := $(root_dir)/terraform
terraform_config := ${terraform_dir}/${google_project}.tfvars
terraform_output := $(root_dir)/terraform-output.json
terraform_bucket := terraform-${google_project}
terraform_prefix := ${app_id}

###############################################################################
# Settings
###############################################################################

settings:
	$(call header,Common Settings)
	echo "# VERSION: ${VERSION}"
	echo "# app_id=${app_id}"
	echo "# google_project=${google_project}"
	echo "# google_region=${google_region}"

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

release: commit tag

###############################################################################
# Terraform
###############################################################################

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

vault_vars += --set="appVersion=$(vault_ver)"
vault_vars += --set="vault_tls_key=$(vault_tls_key)"

vault:

vault_template := kubernetes/vault/template.yaml

vault-template:
	helm template vault $(vault_dir) --namespace $(vault_namespace) $(vault_vars)

vault-install: vault-set-namespace
	$(call header,Install Hashicorp Vault)
	helm upgrade vault hashicorp/vault --namespace $(vault_namespace) $(vault_vars) \
	--install --create-namespace --wait --timeout=2m --atomic

vault-set-namespace:
	kubectl config set-context --current --namespace $(vault_namespace)

.vault-helm-repo:
	$(call header,Configure Hashicorp Helm repository)
	helm repo add hashicorp https://helm.releases.hashicorp.com
	helm repo update
	touch $@

vault-helm-list: .vault-helm-repo
	$(call header,List Hashicorp Helm versions)
	helm search repo hashicorp/vault

vault-clean:
	$(call header,Reset Vault Config)
	rm -rf .vault-helm-repo

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
echo "########################################################################"
echo "# $(1)"
echo "########################################################################"
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
