# Hashicorp Vault

This directory contains a Kubernetes deployment for Hashicorp Vault based on the official Hashicorp Vault Helm chart (https://www.vaultproject.io/docs/platform/k8s/helm).

## Overview

The deployment in this directory is a simplified version of the official Hashicorp Helm chart. It has been rewritten to:

1. Narrow the deployment scope
2. Simplify the Helm code
3. Focus on deploying HashiCorp Vault in High Availability (HA) mode
4. Include the Hashicorp Vault Secrets Operator

## Contents

This deployment includes:

- HashiCorp Vault HA configuration
- Hashicorp Vault Secrets Operator

## Usage

For detailed instructions on how to deploy and use this Vault configuration, please refer to the deployment guide in this directory.

## Notes

This deployment is intended to provide a streamlined setup for Hashicorp Vault in Kubernetes environments. While it simplifies the deployment process, users should ensure they understand the implications and requirements for running Vault in production environments.
