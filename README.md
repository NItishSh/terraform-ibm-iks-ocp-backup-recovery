# IBM Backup & Recovery for IKS/ROKS with Cohesity DSC

[![Incubating (Not yet consumable)](https://img.shields.io/badge/status-Incubating%20(Not%20yet%20consumable)-red)](https://terraform-ibm-modules.github.io/documentation/#/badge-status)
[![latest release](https://img.shields.io/github/v/release/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery?logo=GitHub&sort=semver)](https://github.com/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery/releases/latest)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://renovatebot.com/)
[![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/semantic-release)

This module deploys the **Cohesity Data Source Connector (DSC)** via Helm into an **IBM Kubernetes Service (IKS) or Red Hat OpenShift on IBM Cloud (ROKS)** cluster, registers the cluster with **IBM Backup & Recovery Service**, and creates a **configurable protection policy**.

It automates:
- Security group rules for DSC-to-BRS communication
- Helm deployment of the DSC chart
- ServiceAccount + token generation (in `default` namespace)
- Cluster registration with IBM B&R
- Flexible backup policy with incremental schedules, retention, and optional data lock (WORM)

---

## Overview
* [terraform-ibm-iks-ocp-backup-recovery](#terraform-ibm-iks-ocp-backup-recovery)
* [Examples](./examples)
    * [Basic example](./examples/basic)
    * [Advanced example](./examples/advanced)
* [Contributing](#contributing)

---

## terraform-ibm-iks-ocp-backup-recovery

### Usage

```hcl
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = "X.Y.Z"  # Lock into a provider version that satisfies the module constraints
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.0"
    }
  }
}

provider "ibm" {
  ibmcloud_api_key = "your-api-key-here"
  region           = "us-south"
}

module "backup_recovery" {
  source  = "terraform-ibm-modules/iks-ocp-backup-recovery/ibm"
  version = "1.0.0"  # Use latest release

  # --- DSC Helm Chart ---
  dsc = {
    release_name       = "cohesity-dsc"
    chart_name         = "cohesity-dsc-chart"
    chart_repository   = "oci://your-registry/cohesity-charts"
    namespace          = "cohesity-dsc"
    create_namespace   = true
    chart_version      = "7.2.15"
    registration_token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
    replica_count      = 1
    timeout            = 1800

    image = {
      namespace  = "cohesity"
      repository = "dsc"
      tag        = "7.2.15"
      pullPolicy = "IfNotPresent"
    }
  }

  # --- B&R Instance ---
  brsintance = {
    guid          = "6B29FC40-CA47-1067-B31D-00DD010662DA"
    region        = "us-south"
    endpoint_type = "public"
    tenant_id     = "tenant-67890"
  }

  # --- Cluster Registration ---
  cluster_id    = "c1234567890abcdef1234567890abcdef"
  connection_id = "conn-12345"

  registration = {
    name = "my-iks-cluster"
    cluster = {
      id                = "c1234567890abcdef1234567890abcdef"
      resource_group_id = "rg-12345"
      endpoint          = "c1234567890abcdef1234567890abcdef.us-south.containers.cloud.ibm.com"
      distribution      = "IKS"
      images = {
        data_mover              = "icr.io/cohesity/data-mover:7.2.15"
        velero                  = "icr.io/cohesity/velero:1.9.0"
        velero_aws_plugin       = "icr.io/cohesity/velero-plugin-aws:1.5.0"
        velero_openshift_plugin = "icr.io/cohesity/velero-plugin-openshift:1.5.0"
        init_container          = "icr.io/cohesity/init-container:7.2.15"
      }
    }
  }

  # --- Backup Policy ---
  policy = {
    name = "daily-with-weekly-lock"

    schedule = {
      unit      = "Hours"
      frequency = 6
      # Optional layered schedule
      week_schedule = {
        day_of_week = ["Sunday"]
      }
    }

    retention = {
      duration = 4
      unit     = "Weeks"
      data_lock_config = {
        mode                           = "Compliance"
        unit                           = "Years"
        duration                       = 1
        enable_worm_on_external_target = true
      }
    }

    use_default_backup_target = true
  }
}
```

---

### Required IAM Access Policies

You need the following permissions to run this module:

- **Backup & Recovery** service
  - `Editor` platform access
  - `Manager` service access
- **Cloud Object Storage**
  - `Writer` service access (if using COS as backup target)
- **VPC Infrastructure**
  - `Editor` on security groups (for DSC outbound rules)
- **Kubernetes Service**
  - Access to manage service accounts, secrets, and Helm releases in the target cluster

---

### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.9.0 |
| <a name="requirement_ibm"></a> [ibm](#requirement_ibm) | >= 1.85.0, < 2.0.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement_kubernetes) | 2.38.0 |
| <a name="requirement_helm"></a> [helm](#requirement_helm) | 3.1.0 |

### Modules

| Name | Source | Version |
|------|--------|---------|
| dsc_sg_rule | terraform-ibm-modules/security-group/ibm | v2.8.0 |

### Resources

| Name | Type |
|------|------|
| [helm_release.dsc_chart](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace.dsc](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_service_account.brsagent](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account) | resource |
| [kubernetes_cluster_role_binding.brsagent_admin](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding) | resource |
| [kubernetes_secret.brsagent_token](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [ibm_backup_recovery_source_registration.source_registration](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery_source_registration) | resource |
| [ibm_backup_recovery_protection_policy.protection_policy](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery_protection_policy) | resource |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_dsc"></a> [dsc](#input_dsc) | Configuration for Cohesity DSC Helm chart deployment | `object({...})` | n/a | yes |
| <a name="input_connection_id"></a> [connection_id](#input_connection_id) | Connection ID for the backup service | `string` | n/a | yes |
| <a name="input_cluster_id"></a> [cluster_id](#input_cluster_id) | IKS/ROKS cluster ID to register | `string` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant_id](#input_tenant_id) | IBM Cloud tenant ID | `string` | n/a | yes |
| <a name="input_registration"></a> [registration](#input_registration) | Kubernetes cluster registration details (sensitive) | `object({...})` | n/a | yes |
| <a name="input_brsintance"></a> [brsintance](#input_brsintance) | Backup & Recovery instance details (GUID, region, endpoint type) | `object({...})` | n/a | yes |
| <a name="input_policy"></a> [policy](#input_policy) | Protection policy with flexible schedule, retention, and data lock | `object({...})` | n/a | yes |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_helm_release_name"></a> [helm_release_name](#output_helm_release_name) | Name of the deployed Helm release |
| <a name="output_helm_release_status"></a> [helm_release_status](#output_helm_release_status) | Status of the Helm release |
| <a name="output_protection_policy_name"></a> [protection_policy_name](#output_protection_policy_name) | Name of the created protection policy |

---

## Contributing

You can report issues and request features for this module in GitHub issues in the module repo. See [Report an issue or request a feature](https://github.com/terraform-ibm-modules/.github/blob/main/.github/SUPPORT.md).

To set up your local development environment, see [Local development setup](https://terraform-ibm-modules.github.io/documentation/#/local-dev-setup) in the project documentation.
