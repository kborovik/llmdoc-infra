# Google Cloud Infrastructure for Document Question Answering with Generative AI and Elasticsearch

Google Cloud infrastructure deployment for https://github.com/kborovik/llmdoc

## Deployment Stack

![Deployment Diagram](docs/deployment.svg)

# Pipeline Stages

- Security static analysis
- Terraform deployment
- Kubernetes deployment
- Functional testing

## Security Static Analysis

Checkov is a static code analysis tool for scanning infrastructure as code (IaC) files for misconfigurations that may lead to security or compliance problems.

https://www.checkov.io/

```shell
make checkov
```

[![asciicast](docs/643320.svg)](https://asciinema.org/a/643320)

## Terraform

Work in progress

```shell
make terraform
```

[![asciicast](docs/642869.svg)](https://asciinema.org/a/642869)

## Kubernetes (HELM)

### HashiCorp Vault

```shell
make vault
```

[![asciicast](docs/649438.svg)](https://asciinema.org/a/649438)

### Document Question Answering

Work in progress

## Functional Testing

Work in progress
