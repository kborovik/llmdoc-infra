# Google Cloud Infrastructure for Document Question Answering with Generative AI and Elasticsearch

This repository contains the Google Cloud infrastructure deployment for the [llmdoc](https://github.com/kborovik/llmdoc) project, which implements a document question answering system using Generative AI and Elasticsearch.

## Pipeline Design Principles

Our development and deployment pipeline adheres to the following principles:

1. **Rapid Iteration**: All dependencies are kept within the project to maximize short feedback development cycles.
2. **Seamless Deployment**: End-to-end deployment and testing can be executed with a single command: `make all`.
3. **Configuration Management**: Deployment target differences are managed through `google_project.tfvars` configuration files.
4. **Version Control**: Code base changes are tracked using `git branch`, while deployment states are tracked with `git tag`.

## Deployment Architecture

![Deployment Diagram](docs/deployment.svg)

Our deployment stack leverages various Google Cloud services and open-source tools to create a robust and scalable infrastructure.

## Security Static Analysis

We use [Checkov](https://www.checkov.io/), a static code analysis tool, to scan our infrastructure as code (IaC) files for potential security misconfigurations or compliance issues.

To run the security analysis:

```shell
make checkov
```

[![Checkov Analysis Demo](docs/643320.svg)](https://asciinema.org/a/643320)

## Infrastructure as Code with Terraform

We use Terraform to manage and provision our Google Cloud infrastructure. This allows for version-controlled, repeatable deployments across different environments.

To apply the Terraform configuration:

```shell
make terraform
```

[![Terraform Deployment Demo](docs/642869.svg)](https://asciinema.org/a/642869)

## Kubernetes and HELM

### HashiCorp Vault

We use HashiCorp Vault for secrets management, providing a secure and centralized solution for storing and accessing sensitive information.

To deploy Vault:

```shell
make vault
```

[![Vault Deployment Demo](docs/649438.svg)](https://asciinema.org/a/649438)

### Vault Secrets Operator

The [Vault Secrets Operator](https://github.com/hashicorp/vault-secrets-operator) is a Kubernetes operator that synchronizes secrets between Vault and Kubernetes. This allows for seamless integration of Vault's secret management capabilities with Kubernetes applications.

For more information, see the [Vault Secrets Operator documentation](https://developer.hashicorp.com/vault/tutorials/kubernetes/vault-secrets-operator).

### Document Question Answering

The document question answering system deployment is currently in progress. This component will leverage Generative AI and Elasticsearch to provide intelligent responses to queries about document content.

## Functional Testing

Comprehensive functional testing of the deployed infrastructure and applications is currently under development. This will ensure the reliability and correctness of the entire system.
