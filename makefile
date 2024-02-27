.ONESHELL:
.SILENT:
.EXPORT_ALL_VARIABLES:
.PHONY: default terraform kubernetes ansible

default: settings

root_path := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

###############################################################################
# Global Varitables
###############################################################################
app_id := llmdoc

google_project ?= lab5-llmdoc-dev1
google_region ?= us-east5
google_zone ?= ${google_region}-b

gke_name ?= llmdoc-01

terraform_dir ?= ${root_path}/terraform
terraform_config ?= ${terraform_dir}/${google_project}.tfvars
terraform_output ?= ${root_path}/terraform-output.json
terraform_bucket ?= terraform-${google_project}
terraform_prefix ?= ${app_id}

PAUSE ?= 0

###############################################################################
# Settings
###############################################################################
settings:
	$(call header,Common Settings)
	echo "# app_id=${app_id}"
	echo "# google_project=${google_project}"
	echo "# google_region=${google_region}"
	echo "# terraform_dir=${terraform_dir}"
	echo

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
demo: demo-terraform

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
