# IBM Backup & Recovery for IKS/ROKS with Cohesity DSC

[![Stable (With quality checks)](https://img.shields.io/badge/Status-Stable%20(With%20quality%20checks)-green)](https://terraform-ibm-modules.github.io/documentation/#/badge-status)
[![latest release](https://img.shields.io/github/v/release/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery?logo=GitHub&sort=semver)](https://github.com/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery/releases/latest)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://renovatebot.com/)
[![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/semantic-release)

This module deploys the **Cohesity Data Source Connector (DSC)** via Helm into an **IBM Kubernetes Service (IKS) or Red Hat OpenShift on IBM Cloud** cluster, registers the cluster with **[IBM Backup & Recovery Service](https://cloud.ibm.com/docs/backup-recovery?topic=backup-recovery-data-source-connector-iks-roks)**, and creates a **configurable protection policy**.

It automates:

- Security group rules for DSC-to-BRS communication
- Helm deployment of the DSC chart
- ServiceAccount + token generation
- Cluster registration with IBM B&R
- Flexible backup policy with incremental schedules, retention, and optional data lock (WORM)

<!-- BEGIN OVERVIEW HOOK -->
## Overview
* [terraform-ibm-iks-ocp-backup-recovery](#terraform-ibm-iks-ocp-backup-recovery)
* [Examples](./examples)
    * [Basic example](./examples/basic)
* [Contributing](#contributing)
<!-- END OVERVIEW HOOK -->

## terraform-ibm-iks-ocp-backup-recovery

### Usage

```hcl
# ############################################################################
# Init cluster config for helm
# ############################################################################

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id = "xxxxxxxxx" # replace with cluster ID or name
}

# ############################################################################
# Config providers
# ############################################################################

provider "ibm" {
  ibmcloud_api_key = "xxxxxxxxxxxx"  # pragma: allowlist secret
}

provider "helm" {
  kubernetes {
    host                   = data.ibm_container_cluster_config.cluster_config.host
    token                  = data.ibm_container_cluster_config.cluster_config.token
    cluster_ca_certificate = data.ibm_container_cluster_config.cluster_config.ca_certificate
  }
  registries = [
    { url = "oci://icr.io", username = "iamapikey", password = var.ibmcloud_api_key }
  ]
}

provider "kubernetes" {
  host                   = data.ibm_container_cluster_config.cluster_config.host
  token                  = data.ibm_container_cluster_config.cluster_config.token
  cluster_ca_certificate = data.ibm_container_cluster_config.cluster_config.ca_certificate
}

# ############################################################################
# Install DSC
# ############################################################################
module "backup_recovery" {
  source  = "terraform-ibm-modules/iks-ocp-backup-recovery/ibm"
  version = "X.Y.Z"  # Replace "X.Y.Z" with a release version to lock into a specific release
  cluster_id                    = "xxxxxxx" # replace with ID of the cluster
  cluster_resource_group_id     = "xxxxxxx" # replace with ID of the cluster resource group
  dsc_registration_token        = "xxxxxxx" # replace with Registration_token
  connection_id                 = "xxxxxxx" # replace with connection ID
  # --- B&R Instance ---
  brs_instance_guid   = "xxxxxxx" # replace with ID of the BRS instance
  brs_instance_region = var.region
  brs_endpoint_type   = "public"
  brs_tenant_id       = "xxxxxxx" # replace with tenant ID of the BRS instance
  registration_name   = "ocp-dsc"
  # --- Backup Policy ---
  policy = {
    name = "daily-with-monthly-retention"
    schedule = {
      unit      = "Hours"
      frequency = 24
    }
    retention = {
      duration = 4
      unit     = "Weeks"
    }
    use_default_backup_target = true
  }
}
```

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
  - `Viewer` platform access
  - `Administrator` service access

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | 3.1.0 |
| <a name="requirement_ibm"></a> [ibm](#requirement\_ibm) | >= 1.85.0, < 2.0.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | 2.38.0 |

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_dsc_sg_rule"></a> [dsc\_sg\_rule](#module\_dsc\_sg\_rule) | terraform-ibm-modules/security-group/ibm | v2.8.0 |

### Resources

| Name | Type |
|------|------|
| [helm_release.data_source_connector](https://registry.terraform.io/providers/hashicorp/helm/3.1.0/docs/resources/release) | resource |
| [ibm_backup_recovery_protection_policy.protection_policy](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery_protection_policy) | resource |
| [ibm_backup_recovery_source_registration.source_registration](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery_source_registration) | resource |
| [kubernetes_cluster_role_binding.brsagent_admin](https://registry.terraform.io/providers/hashicorp/kubernetes/2.38.0/docs/resources/cluster_role_binding) | resource |
| [kubernetes_secret.brsagent_token](https://registry.terraform.io/providers/hashicorp/kubernetes/2.38.0/docs/resources/secret) | resource |
| [kubernetes_service_account.brsagent](https://registry.terraform.io/providers/hashicorp/kubernetes/2.38.0/docs/resources/service_account) | resource |
| [ibm_container_vpc_cluster.cluster](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/container_vpc_cluster) | data source |
| [ibm_is_security_group.clustersg](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/is_security_group) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_add_dsc_rules_to_cluster_sg"></a> [add\_dsc\_rules\_to\_cluster\_sg](#input\_add\_dsc\_rules\_to\_cluster\_sg) | Set to `true` to automatically add required security group rules for the Data Source Connector and set to `false` to only register the cluster and create the policy. | `bool` | `true` | no |
| <a name="input_brs_endpoint_type"></a> [brs\_endpoint\_type](#input\_brs\_endpoint\_type) | The endpoint type to use when connecting to the Backup and Recovery service for creating a data source connection. Allowed values are 'public' or 'private'. | `string` | `"public"` | no |
| <a name="input_brs_instance_guid"></a> [brs\_instance\_guid](#input\_brs\_instance\_guid) | GUID of the Backup & Recovery Service instance. | `string` | n/a | yes |
| <a name="input_brs_instance_region"></a> [brs\_instance\_region](#input\_brs\_instance\_region) | Region of the Backup & Recovery Service instance. | `string` | n/a | yes |
| <a name="input_brs_tenant_id"></a> [brs\_tenant\_id](#input\_brs\_tenant\_id) | BRS tenant ID in the format `<tenant-guid>/`. Required for API calls and agent configuration. | `string` | n/a | yes |
| <a name="input_cluster_config_endpoint_type"></a> [cluster\_config\_endpoint\_type](#input\_cluster\_config\_endpoint\_type) | The type of endpoint to use for the cluster config access: `default`, `private`, `vpe`, or `link`. The `default` value uses the default endpoint of the cluster. | `string` | `"default"` | no |
| <a name="input_cluster_id"></a> [cluster\_id](#input\_cluster\_id) | The ID of the cluster designated for backup and recovery. | `string` | n/a | yes |
| <a name="input_cluster_resource_group_id"></a> [cluster\_resource\_group\_id](#input\_cluster\_resource\_group\_id) | Resource group ID the cluster is deployed in. | `string` | n/a | yes |
| <a name="input_connection_id"></a> [connection\_id](#input\_connection\_id) | Connection ID for the backup service | `string` | n/a | yes |
| <a name="input_dsc_chart"></a> [dsc\_chart](#input\_dsc\_chart) | Name of the Data Source connector Helm chart. | `string` | `"cohesity-dsc-chart"` | no |
| <a name="input_dsc_chart_location"></a> [dsc\_chart\_location](#input\_dsc\_chart\_location) | OCI registry location of the Data Source Connector Helm chart. | `string` | `"oci://icr.io/ext/brs"` | no |
| <a name="input_dsc_chart_version"></a> [dsc\_chart\_version](#input\_dsc\_chart\_version) | Version of the Data Source Connector Helm chart to deploy. | `string` | `"7.2.15-release-20250721-6aa24701"` | no |
| <a name="input_dsc_image"></a> [dsc\_image](#input\_dsc\_image) | Container image for the Data Source Connector. | `string` | `"icr.io/ext/brs/cohesity-data-source-connector_7.2.15-release-20250721"` | no |
| <a name="input_dsc_image_version_tag"></a> [dsc\_image\_version\_tag](#input\_dsc\_image\_version\_tag) | Image tag for the Data Source Connector container. | `string` | `"6aa24701"` | no |
| <a name="input_dsc_name"></a> [dsc\_name](#input\_dsc\_name) | Release name for the Data Source Connector Helm deployment. | `string` | `"dsc"` | no |
| <a name="input_dsc_namespace"></a> [dsc\_namespace](#input\_dsc\_namespace) | The cluster namespace where the Data Source Connector will be installed. Will be created if it does not exist. | `string` | `"data-source-connector"` | no |
| <a name="input_dsc_registration_token"></a> [dsc\_registration\_token](#input\_dsc\_registration\_token) | Registration token generated in the Backup & Recovery Service UI when adding a cluster data source. | `string` | n/a | yes |
| <a name="input_dsc_replicas"></a> [dsc\_replicas](#input\_dsc\_replicas) | Number of Data Source Connector pods to run (typically 1). | `number` | `1` | no |
| <a name="input_kube_type"></a> [kube\_type](#input\_kube\_type) | Specify the type of target cluster for the backup and recovery. Accepted values are `ROKS` or `IKS`. | `string` | `"ROKS"` | no |
| <a name="input_policy"></a> [policy](#input\_policy) | The backup schedule and retentions of a Protection Policy. | <pre>object({<br/>    name = string<br/>    schedule = object({<br/>      unit      = string # Minutes, Hours, Days, Weeks, Months, Years, Runs<br/>      frequency = number # required when unit is Minutes/Hours/Days<br/><br/>      # Optional extra layers (allowed even when unit = Minutes)<br/>      minute_schedule = optional(object({ frequency = number }))<br/>      hour_schedule   = optional(object({ frequency = number }))<br/>      day_schedule    = optional(object({ frequency = number }))<br/>      week_schedule   = optional(object({ day_of_week = list(string) }))<br/>      month_schedule = optional(object({<br/>        day_of_week   = optional(list(string))<br/>        week_of_month = optional(string) # First, Second, Third, Fourth, Last<br/>        day_of_month  = optional(number)<br/>      }))<br/>      year_schedule = optional(object({ day_of_year = string })) # First, Last<br/>    })<br/><br/>    retention = object({<br/>      duration = number<br/>      unit     = string # Days, Weeks, Months, Years<br/><br/>      data_lock_config = optional(object({<br/>        mode                           = string # Compliance, Administrative<br/>        unit                           = string # Days, Weeks, Months, Years<br/>        duration                       = number<br/>        enable_worm_on_external_target = optional(bool, false)<br/>      }))<br/>    })<br/><br/>    use_default_backup_target = optional(bool, true)<br/>  })</pre> | n/a | yes |
| <a name="input_registration_images"></a> [registration\_images](#input\_registration\_images) | The images required for backup and recovery registration. | <pre>object({<br/>    data_mover              = optional(string, null)<br/>    velero                  = optional(string, null)<br/>    velero_aws_plugin       = optional(string, null)<br/>    velero_openshift_plugin = optional(string, null)<br/>    init_container          = optional(string, null)<br/>  })</pre> | `{}` | no |
| <a name="input_registration_name"></a> [registration\_name](#input\_registration\_name) | Name of the registration. | `string` | n/a | yes |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_protection_policy_name"></a> [protection\_policy\_name](#output\_protection\_policy\_name) | Name of the created protection policy |
| <a name="output_source_registration_id"></a> [source\_registration\_id](#output\_source\_registration\_id) | ID of the registered Kubernetes source |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Contributing

You can report issues and request features for this module in GitHub issues in the module repo. See [Report an issue or request a feature](https://github.com/terraform-ibm-modules/.github/blob/main/.github/SUPPORT.md).

To set up your local development environment, see [Local development setup](https://terraform-ibm-modules.github.io/documentation/#/local-dev-setup) in the project documentation.
