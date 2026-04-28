# IBM Backup & Recovery for IKS/ROKS with Data Source Connector

[![Stable (With quality checks)](<https://img.shields.io/badge/Status-Stable%20(With%20quality%20checks)-green>)](https://terraform-ibm-modules.github.io/documentation/#/badge-status)
[![latest release](https://img.shields.io/github/v/release/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery?logo=GitHub&sort=semver)](https://github.com/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery/releases/latest)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://renovatebot.com/)
[![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/semantic-release)
[![Terraform Registry](https://img.shields.io/badge/terraform-registry-623CE4?logo=terraform)](https://registry.terraform.io/modules/terraform-ibm-modules/iks-ocp-backup-recovery/ibm/latest)

This module deploys the **Data Source Connector (DSC)** via Helm into an **IBM Kubernetes Service (IKS) or Red Hat OpenShift on IBM Cloud** cluster, registers the cluster with **[IBM Backup & Recovery Service](https://cloud.ibm.com/docs/backup-recovery?topic=backup-recovery-data-source-connector-iks-roks)**, and creates a **configurable protection policy**.

It automates:

- Security group rules for DSC-to-BRS communication
- Helm deployment of the DSC chart
- ServiceAccount + token generation
- Cluster registration with IBM B&R
- Flexible backup policy with incremental schedules, retention, and optional data lock (WORM)

## 📖 Protection Group Configuration Guide

For detailed guidance on configuring Kubernetes Protection Groups, including limitations, best practices, and working examples, see:

**[Protection Group Configuration Guide](./ProtectionGroup.md)**

<!-- BEGIN OVERVIEW HOOK -->
## Overview
<ul>
  <li><a href="#terraform-ibm-iks-ocp-backup-recovery">terraform-ibm-iks-ocp-backup-recovery</a></li>
  <li><a href="./examples">Examples</a>
    <ul>
      <li>
        <a href="./examples/kubernetes">Kubernetes example</a>
        <a href="https://cloud.ibm.com/schematics/workspaces/create?workspace_name=iks-ocp-backup-recovery-kubernetes-example&repository=https://github.com/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery/tree/main/examples/kubernetes"><img src="https://img.shields.io/badge/Deploy%20with%20IBM%20Cloud%20Schematics-0f62fe?style=flat&logo=ibm&logoColor=white&labelColor=0f62fe" alt="Deploy with IBM Cloud Schematics" style="height: 16px; vertical-align: text-bottom; margin-left: 5px;"></a>
      </li>
      <li>
        <a href="./examples/openshift">Openshift example</a>
        <a href="https://cloud.ibm.com/schematics/workspaces/create?workspace_name=iks-ocp-backup-recovery-openshift-example&repository=https://github.com/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery/tree/main/examples/openshift"><img src="https://img.shields.io/badge/Deploy%20with%20IBM%20Cloud%20Schematics-0f62fe?style=flat&logo=ibm&logoColor=white&labelColor=0f62fe" alt="Deploy with IBM Cloud Schematics" style="height: 16px; vertical-align: text-bottom; margin-left: 5px;"></a>
      </li>
    </ul>
    ℹ️ Ctrl/Cmd+Click or right-click on the Schematics deploy button to open in a new tab.
  </li>
  <li><a href="./solutions">Deployable Architectures</a>
    <ul>
      <li><a href="./solutions/fully-configurable">Cloud automation for OpenShift workloads Backup Recovery (Fully configurable)</a></li>
    </ul>
  </li>
  <li><a href="#contributing">Contributing</a></li>
</ul>
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
    { url = "oci://icr.io", username = "iamapikey", password = var.ibmcloud_api_key } # pragma: allowlist secret
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

#### Recovery Example

To restore backups created by protection groups:

```hcl
module "backup_recovery" {
  source  = "terraform-ibm-modules/iks-ocp-backup-recovery/ibm"
  version = "X.Y.Z"

  # ... other configuration ...

  # Recovery operations
  recoveries = [{
    name                 = "restore-production-namespace"
    snapshot_environment = "kKubernetes"
    kubernetes_params = {
      recovery_action = "RecoverNamespaces"
      objects = [{
        snapshot_id         = "snapshot-123"
        protection_group_id = "pg-456"
      }]
    }
  }]
}
```

**Note:** The current provider version supports basic recovery operations. Advanced features like namespace_mapping, volume_info_vec, and cross-cluster recovery may require provider updates.

### Required IAM Access Policies

You need the following permissions to run this module:

- **Backup & Recovery** service
  - `Editor` platform access
- **VPC Infrastructure**
  - `Editor` on security groups (for DSC outbound rules)
- **Kubernetes Service**
  - `Editor` platform access

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >=3.1.0, <4.0.0 |
| <a name="requirement_ibm"></a> [ibm](#requirement\_ibm) | >= 1.88.3, < 3.0.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >=3.0.1, <4.0.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >=0.12.1, <1.0.0 |

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_backup_recovery_instance"></a> [backup\_recovery\_instance](#module\_backup\_recovery\_instance) | terraform-ibm-modules/backup-recovery/ibm | v1.10.1 |
| <a name="module_crn_parser"></a> [crn\_parser](#module\_crn\_parser) | terraform-ibm-modules/common-utilities/ibm//modules/crn-parser | 1.5.0 |
| <a name="module_dsc_sg_rule"></a> [dsc\_sg\_rule](#module\_dsc\_sg\_rule) | terraform-ibm-modules/security-group/ibm | v2.9.0 |

### Resources

| Name | Type |
|------|------|
| [helm_release.data_source_connector](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [ibm_backup_recovery.recover_snapshot](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery) | resource |
| [ibm_backup_recovery_protection_group.protection_group](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery_protection_group) | resource |
| [ibm_backup_recovery_source_registration.source_registration](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery_source_registration) | resource |
| [ibm_container_vpc_worker_pool.data_source_connector](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/container_vpc_worker_pool) | resource |
| [ibm_resource_tag.cluster_brs_tag](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/resource_tag) | resource |
| [kubernetes_cluster_role_binding_v1.brsagent_admin](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding_v1) | resource |
| [kubernetes_namespace_v1.dsc_namespace](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_secret_v1.brsagent_token](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [kubernetes_service_account_v1.brsagent](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account_v1) | resource |
| [terraform_data.cleanup_brs_agent_resources](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.delete_auto_protect_pg](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.install_dependencies](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.wait_before_helm_destroy](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [time_sleep.wait_for_source_discovery](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [ibm_backup_recovery_protection_sources.sources](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/backup_recovery_protection_sources) | data source |
| [ibm_container_cluster.classic_cluster](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/container_cluster) | data source |
| [ibm_container_cluster_config.cluster_config](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/container_cluster_config) | data source |
| [ibm_container_vpc_cluster.vpc_cluster](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/container_vpc_cluster) | data source |
| [ibm_container_vpc_worker_pool.pool](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/container_vpc_worker_pool) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_tags"></a> [access\_tags](#input\_access\_tags) | Add existing access management tags to the Backup Recovery instance to manage access. | `list(string)` | `[]` | no |
| <a name="input_add_cluster_tags"></a> [add\_cluster\_tags](#input\_add\_cluster\_tags) | Whether to add BRS tags to the cluster. Set to false if you manage cluster tags externally to avoid drift. When false, you should manually add the tags 'brs-region:<region>' and 'brs-guid:<guid>' to your cluster. | `bool` | `true` | no |
| <a name="input_add_dsc_rules_to_cluster_sg"></a> [add\_dsc\_rules\_to\_cluster\_sg](#input\_add\_dsc\_rules\_to\_cluster\_sg) | Set to `true` to automatically add the security group rules required by the Data Source Connector. This is mandatory when registering the cluster via its public service endpoint. Set to `false` to only register the cluster and create the policy without modifying security groups. | `bool` | `true` | no |
| <a name="input_auto_protect_policy_name"></a> [auto\_protect\_policy\_name](#input\_auto\_protect\_policy\_name) | Name of an existing protection policy to use for auto-protect. Required when `enable_auto_protect` is `true`. The policy must already exist in the BRS instance (create it using the `terraform-ibm-backup-recovery` module). | `string` | `null` | no |
| <a name="input_brs_connection_name"></a> [brs\_connection\_name](#input\_brs\_connection\_name) | Name of the connection from the Backup & Recovery Service instance to be used for protecting the cluster. If `brs_create_new_connection` is set to `true` (default), this will be the name of the new connection created. If set to `false`, this must be the name of an existing connection. | `string` | n/a | yes |
| <a name="input_brs_create_new_connection"></a> [brs\_create\_new\_connection](#input\_brs\_create\_new\_connection) | Flag to create a new connection from the Backup & Recovery Service instance to the cluster. When set to `true` (default), a new connection is created with the name specified in `brs_connection_name`. When `false`, it uses an existing connection matching `brs_connection_name`. | `bool` | `true` | no |
| <a name="input_brs_endpoint_type"></a> [brs\_endpoint\_type](#input\_brs\_endpoint\_type) | The endpoint type to use when connecting to the Backup and Recovery service for creating a data source connection. Allowed values are 'public' or 'private'. | `string` | `"private"` | no |
| <a name="input_brs_instance_name"></a> [brs\_instance\_name](#input\_brs\_instance\_name) | Name of the Backup & Recovery Service instance. Required only when `existing_brs_instance_crn` is not provided. | `string` | `null` | no |
| <a name="input_cluster_config_endpoint_type"></a> [cluster\_config\_endpoint\_type](#input\_cluster\_config\_endpoint\_type) | The type of endpoint to use for the cluster config access: `default`, `private`, `vpe`, or `link`. The `default` value uses the default endpoint of the cluster. | `string` | `"default"` | no |
| <a name="input_cluster_id"></a> [cluster\_id](#input\_cluster\_id) | The ID of the cluster designated for backup and recovery. | `string` | n/a | yes |
| <a name="input_cluster_resource_group_id"></a> [cluster\_resource\_group\_id](#input\_cluster\_resource\_group\_id) | Resource group ID the cluster is deployed in. | `string` | n/a | yes |
| <a name="input_connection_env_type"></a> [connection\_env\_type](#input\_connection\_env\_type) | Connection environment type to determine the required parameters for creating a new connection. Allowed values are 'kIksVpc', 'kRoksVpc', 'kRoksClassic', and 'kIksClassic'. | `string` | `"kIksVpc"` | no |
| <a name="input_create_dsc_worker_pool"></a> [create\_dsc\_worker\_pool](#input\_create\_dsc\_worker\_pool) | Set to `true` to create a dedicated worker pool for the Data Source Connector in VPC clusters. If set to `false`, the connector will be deployed on existing worker nodes. | `bool` | `true` | no |
| <a name="input_dsc_chart_uri"></a> [dsc\_chart\_uri](#input\_dsc\_chart\_uri) | The full OCI registry URI for the Data Source Connector Helm chart, including the digest. | `string` | `"oci://icr.io/ext/brs/brs-ds-connector-chart:7.2.18-release-20260226-49768040@sha256:99728a3146a7d8b2ae2f88300a6a89752488d3733e29118ee83a655959114541"` | no |
| <a name="input_dsc_helm_timeout"></a> [dsc\_helm\_timeout](#input\_dsc\_helm\_timeout) | Timeout in seconds for the Data Source Connector Helm deployment. | `number` | `1500` | no |
| <a name="input_dsc_image_version"></a> [dsc\_image\_version](#input\_dsc\_image\_version) | Container image for the Data Source Connector. | `string` | `"icr.io/ext/brs/brs-ds-connector:7.2.18-release-20260226-49768040@sha256:99728a3146a7d8b2ae2f88300a6a89752488d3733e29118ee83a655959114541"` | no |
| <a name="input_dsc_name"></a> [dsc\_name](#input\_dsc\_name) | Release name for the Data Source Connector Helm deployment. | `string` | `"dsc"` | no |
| <a name="input_dsc_namespace"></a> [dsc\_namespace](#input\_dsc\_namespace) | The cluster namespace where the Data Source Connector will be installed. Will be created if it does not exist. | `string` | `"ibm-brs-data-source-connector"` | no |
| <a name="input_dsc_replicas"></a> [dsc\_replicas](#input\_dsc\_replicas) | Number of Data Source Connector pods to run.<br/>Recommended values:<br/>  • 3 – for high availability across multiple nodes/zones (strongly recommended in production)<br/>  • 1 – only for dev/test or single-node clusters | `number` | `1` | no |
| <a name="input_dsc_storage_class"></a> [dsc\_storage\_class](#input\_dsc\_storage\_class) | Storage class to use for the Data Source Connector persistent volume. By default, it uses 'ibmc-vpc-block-metro-5iops-tier' for VPC clusters and 'ibmc-block-silver' for Classic clusters. | `string` | `null` | no |
| <a name="input_enable_auto_protect"></a> [enable\_auto\_protect](#input\_enable\_auto\_protect) | Enable auto-protect during the initial cluster registration. This must be set to `true` on the first run; toggling it from `false` to `true` later is not supported by the underlying API and will not retroactively create the protection group. | `bool` | `true` | no |
| <a name="input_existing_brs_instance_crn"></a> [existing\_brs\_instance\_crn](#input\_existing\_brs\_instance\_crn) | CRN of the Backup & Recovery Service instance. | `string` | `null` | no |
| <a name="input_ibmcloud_api_key"></a> [ibmcloud\_api\_key](#input\_ibmcloud\_api\_key) | The IBM Cloud api key to generate an IAM token. | `string` | n/a | yes |
| <a name="input_install_required_binaries"></a> [install\_required\_binaries](#input\_install\_required\_binaries) | When set to true, a script will run to check if `kubectl` and `jq`, `IBM Cloud CLI (ibmcloud)`, and the `backup-recovery plugin` exist on the runtime and if not attempt to download them from the public internet and install them to /tmp. Set to false to skip running this script. | `bool` | `true` | no |
| <a name="input_kube_type"></a> [kube\_type](#input\_kube\_type) | Specify the type of target cluster for the backup and recovery. Accepted values are `openshift` or `kubernetes`. | `string` | `"openshift"` | no |
| <a name="input_policies"></a> [policies](#input\_policies) | A list of protection policies to create or look up. Set `create_new_policy` to `true` (default) to create a new policy with the specified `schedule` and `retention`. Set `create_new_policy` to `false` to reference an existing policy by `name`. | <pre>list(object({<br/>    name                      = string<br/>    create_new_policy         = optional(bool, false)<br/>    use_default_backup_target = optional(bool, true)<br/><br/>    # --- primary_backup_target advanced details ---<br/>    primary_backup_target_details = optional(object({<br/>      target_id = number<br/>      tier_settings = optional(list(object({<br/>        cloud_platform = string # AWS, Azure, Google, Oracle<br/>        aws_tiering = optional(object({<br/>          tiers = list(object({ tier_type = string, move_after = number, move_after_unit = string }))<br/>        }))<br/>        azure_tiering = optional(object({<br/>          tiers = list(object({ tier_type = string, move_after = number, move_after_unit = string }))<br/>        }))<br/>        google_tiering = optional(object({<br/>          tiers = list(object({ tier_type = string, move_after = number, move_after_unit = string }))<br/>        }))<br/>        oracle_tiering = optional(object({<br/>          tiers = list(object({ tier_type = string, move_after = number, move_after_unit = string }))<br/>        }))<br/>      })))<br/>    }))<br/><br/>    # --- Standard backup schedule and retention ---<br/>    schedule = optional(object({<br/>      unit            = string<br/>      minute_schedule = optional(object({ frequency = number }))<br/>      hour_schedule   = optional(object({ frequency = number }))<br/>      day_schedule    = optional(object({ frequency = number }))<br/>      week_schedule   = optional(object({ day_of_week = list(string) }))<br/>      month_schedule  = optional(object({ day_of_month = optional(number), day_of_week = optional(list(string)), week_of_month = optional(string) }))<br/>      year_schedule   = optional(object({ day_of_year = string }))<br/>    }))<br/>    retention = optional(object({<br/>      duration         = number<br/>      unit             = string<br/>      data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>    }))<br/><br/>    # --- Bare Metal Recovery (BMR) ---<br/>    bmr = optional(object({<br/>      schedule = optional(object({<br/>        unit            = string<br/>        minute_schedule = optional(object({ frequency = number }))<br/>        hour_schedule   = optional(object({ frequency = number }))<br/>        day_schedule    = optional(object({ frequency = number }))<br/>        week_schedule   = optional(object({ day_of_week = list(string) }))<br/>        month_schedule  = optional(object({ day_of_month = optional(number), day_of_week = optional(list(string)), week_of_month = optional(string) }))<br/>        year_schedule   = optional(object({ day_of_year = string }))<br/>      }))<br/>      retention = object({<br/>        duration         = number<br/>        unit             = string<br/>        data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>      })<br/>    }))<br/><br/>    # --- Continuous Data Protection (CDP) ---<br/>    cdp = optional(object({<br/>      retention = object({<br/>        duration         = number<br/>        unit             = string<br/>        data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>      })<br/>    }))<br/><br/>    # --- Database Log Backup ---<br/>    log = optional(object({<br/>      schedule = object({<br/>        unit            = string<br/>        minute_schedule = optional(object({ frequency = number }))<br/>        hour_schedule   = optional(object({ frequency = number }))<br/>        day_schedule    = optional(object({ frequency = number }))<br/>        week_schedule   = optional(object({ day_of_week = list(string) }))<br/>        month_schedule  = optional(object({ day_of_month = optional(number), day_of_week = optional(list(string)), week_of_month = optional(string) }))<br/>        year_schedule   = optional(object({ day_of_year = string }))<br/>      })<br/>      retention = object({<br/>        duration         = number<br/>        unit             = string<br/>        data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>      })<br/>    }))<br/><br/>    # --- Storage Array Snapshot ---<br/>    storage_array_snapshot = optional(object({<br/>      schedule = object({<br/>        unit            = string<br/>        minute_schedule = optional(object({ frequency = number }))<br/>        hour_schedule   = optional(object({ frequency = number }))<br/>        day_schedule    = optional(object({ frequency = number }))<br/>        week_schedule   = optional(object({ day_of_week = list(string) }))<br/>        month_schedule  = optional(object({ day_of_month = optional(number), day_of_week = optional(list(string)), week_of_month = optional(string) }))<br/>        year_schedule   = optional(object({ day_of_year = string }))<br/>      })<br/>      retention = object({<br/>        duration         = number<br/>        unit             = string<br/>        data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>      })<br/>    }))<br/><br/>    # --- Blackout windows ---<br/>    blackout_window = optional(list(object({<br/>      day = string<br/>      start_time = object({<br/>        hour      = number<br/>        minute    = number<br/>        time_zone = optional(string, "America/New_York")<br/>      })<br/>      end_time = object({<br/>        hour      = number<br/>        minute    = number<br/>        time_zone = optional(string, "America/New_York")<br/>      })<br/>    })))<br/><br/>    # --- Run timeouts (prevent hung backup jobs) ---<br/>    run_timeouts = optional(list(object({<br/>      timeout_mins = number<br/>      backup_type  = optional(string, "kRegular")<br/>    })))<br/><br/>    # --- Extended retention (keep certain snapshots longer) ---<br/>    extended_retention = optional(list(object({<br/>      schedule = object({<br/>        unit      = string<br/>        frequency = number<br/>      })<br/>      retention = object({<br/>        duration = number<br/>        unit     = string<br/>        data_lock_config = optional(object({<br/>          mode                           = string<br/>          unit                           = string<br/>          duration                       = number<br/>          enable_worm_on_external_target = optional(bool, false)<br/>        }))<br/>      })<br/>      run_type  = optional(string, "Regular")<br/>      config_id = optional(string)<br/>    })))<br/><br/>    # --- Cascaded Targets Config ---<br/>    cascaded_targets_config = optional(object({<br/>      source_cluster_id = number<br/>      remote_targets = list(object({<br/>        archival_targets = optional(list(object({<br/>          target_id           = number<br/>          backup_run_type     = optional(string)<br/>          config_id           = optional(string)<br/>          copy_on_run_success = optional(bool)<br/>          schedule = object({<br/>            unit      = string<br/>            frequency = optional(number)<br/>          })<br/>          retention = object({<br/>            duration         = number<br/>            unit             = string<br/>            data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>          })<br/>          extended_retention = optional(list(object({<br/>            schedule = object({<br/>              unit      = string<br/>              frequency = number<br/>            })<br/>            retention = object({<br/>              duration         = number<br/>              unit             = string<br/>              data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>            })<br/>            run_type  = optional(string, "Regular")<br/>            config_id = optional(string)<br/>          })))<br/>        })))<br/>        cloud_spin_targets = optional(list(object({<br/>          target = object({<br/>            id = optional(number)<br/>          })<br/>          backup_run_type     = optional(string)<br/>          config_id           = optional(string)<br/>          copy_on_run_success = optional(bool)<br/>          schedule = object({<br/>            unit      = string<br/>            frequency = optional(number)<br/>          })<br/>          retention = object({<br/>            duration         = number<br/>            unit             = string<br/>            data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>          })<br/>          extended_retention = optional(list(object({<br/>            schedule = object({<br/>              unit      = string<br/>              frequency = number<br/>            })<br/>            retention = object({<br/>              duration         = number<br/>              unit             = string<br/>              data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>            })<br/>            run_type  = optional(string, "Regular")<br/>            config_id = optional(string)<br/>          })))<br/>        })))<br/>        replication_targets = optional(list(object({<br/>          target_type         = string<br/>          target_id           = number<br/>          backup_run_type     = optional(string)<br/>          config_id           = optional(string)<br/>          copy_on_run_success = optional(bool)<br/>          schedule = object({<br/>            unit      = string<br/>            frequency = optional(number)<br/>          })<br/>          retention = object({<br/>            duration         = number<br/>            unit             = string<br/>            data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>          })<br/>          extended_retention = optional(list(object({<br/>            schedule = object({<br/>              unit      = string<br/>              frequency = number<br/>            })<br/>            retention = object({<br/>              duration         = number<br/>              unit             = string<br/>              data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))<br/>            })<br/>            run_type  = optional(string, "Regular")<br/>            config_id = optional(string)<br/>          })))<br/>        })))<br/>      }))<br/>    }))<br/>  }))</pre> | `null` | no |
| <a name="input_protection_groups"></a> [protection\_groups](#input\_protection\_groups) | List of protection groups for granular backup control. Each group selects specific namespaces/objects and applies a policy. Use this as an alternative to `enable_auto_protect` for fine-grained control over which workloads are backed up. | <pre>list(object({<br/>    name        = string<br/>    policy_name = string<br/>    description = optional(string)<br/><br/>    # --- Kubernetes-specific params ---<br/>    enable_indexing       = optional(bool, true)<br/>    leverage_csi_snapshot = optional(bool, false)<br/>    non_snapshot_backup   = optional(bool, false)<br/>    volume_backup_failure = optional(bool, false)<br/><br/>    # Objects (namespaces) to protect<br/>    objects = optional(list(object({<br/>      id                          = optional(number)<br/>      name                        = optional(string)<br/>      backup_only_pvc             = optional(bool, false)<br/>      fail_backup_on_hook_failure = optional(bool, false)<br/>      included_resources          = optional(list(string))<br/>      excluded_resources          = optional(list(string))<br/>      include_pvcs = optional(list(object({<br/>        id   = optional(number)<br/>        name = optional(string)<br/>      })))<br/>      exclude_pvcs = optional(list(object({<br/>        id   = optional(number)<br/>        name = optional(string)<br/>      })))<br/><br/>      # Per-object label-based PV/PVC inclusion<br/>      include_params = optional(object({<br/>        label_combination_method = optional(string, "AND") # AND, OR<br/>        label_vector = optional(list(object({<br/>          key   = string<br/>          value = string<br/>        })))<br/>        objects = optional(list(object({}))) # usually any or map but provider says array of objects<br/>        selected_resources = optional(list(object({<br/>          api_group         = optional(string)<br/>          is_cluster_scoped = optional(bool)<br/>          kind              = optional(string)<br/>          name              = optional(string)<br/>          version           = optional(string)<br/>          resource_list = optional(list(object({<br/>            entity_id = optional(number)<br/>            name      = optional(string)<br/>          })))<br/>        })))<br/>      }))<br/><br/>      # Per-object label-based PV/PVC exclusion<br/>      exclude_params = optional(object({<br/>        label_combination_method = optional(string, "AND")<br/>        label_vector = optional(list(object({<br/>          key   = string<br/>          value = string<br/>        })))<br/>        objects = optional(list(object({})))<br/>        selected_resources = optional(list(object({<br/>          api_group         = optional(string)<br/>          is_cluster_scoped = optional(bool)<br/>          kind              = optional(string)<br/>          name              = optional(string)<br/>          version           = optional(string)<br/>          resource_list = optional(list(object({<br/>            entity_id = optional(number)<br/>            name      = optional(string)<br/>          })))<br/>        })))<br/>      }))<br/><br/>      # Quiescing rules for app-consistent backups<br/>      quiesce_groups = optional(list(object({<br/>        quiesce_mode = string # kQuiesceTogether, kQuiesceIndependently<br/>        quiesce_rules = list(object({<br/>          pod_selector_labels = optional(list(object({<br/>            key   = string<br/>            value = string<br/>          })))<br/>          pre_snapshot_hooks = list(object({<br/>            commands      = list(string)<br/>            container     = optional(string)<br/>            fail_on_error = optional(bool, false)<br/>            timeout       = optional(number)<br/>          }))<br/>          post_snapshot_hooks = list(object({<br/>            commands      = list(string)<br/>            container     = optional(string)<br/>            fail_on_error = optional(bool, false)<br/>            timeout       = optional(number)<br/>          }))<br/>        }))<br/>      })))<br/>    })))<br/><br/>    # Object IDs to exclude<br/>    exclude_object_ids = optional(list(number))<br/><br/>    # Label-based namespace selection (2D array of label IDs)<br/>    label_ids         = optional(list(number))<br/>    exclude_label_ids = optional(list(number))<br/><br/>    # Global label-based inclusion filter<br/>    include_params = optional(object({<br/>      label_combination_method = optional(string, "AND") # AND, OR<br/>      label_vector = optional(list(object({<br/>        key   = string<br/>        value = string<br/>      })))<br/>      objects = optional(list(object({})))<br/>      selected_resources = optional(list(object({<br/>        api_group         = optional(string)<br/>        is_cluster_scoped = optional(bool)<br/>        kind              = optional(string)<br/>        name              = optional(string)<br/>        version           = optional(string)<br/>        resource_list = optional(list(object({<br/>          entity_id = optional(number)<br/>          name      = optional(string)<br/>        })))<br/>      })))<br/>    }))<br/><br/>    # Global label-based exclusion filter<br/>    exclude_params = optional(object({<br/>      label_combination_method = optional(string, "AND")<br/>      label_vector = optional(list(object({<br/>        key   = string<br/>        value = string<br/>      })))<br/>      objects = optional(list(object({})))<br/>      selected_resources = optional(list(object({<br/>        api_group         = optional(string)<br/>        is_cluster_scoped = optional(bool)<br/>        kind              = optional(string)<br/>        name              = optional(string)<br/>        version           = optional(string)<br/>        resource_list = optional(list(object({<br/>          entity_id = optional(number)<br/>          name      = optional(string)<br/>        })))<br/>      })))<br/>    }))<br/><br/>    # --- Alert policy ---<br/>    alert_policy = optional(object({<br/>      backup_run_status = list(string) # kFailure, kSuccess, kSlaViolation, kWarning<br/>      alert_targets = optional(list(object({<br/>        email_address  = string<br/>        language       = optional(string, "en-us")<br/>        recipient_type = optional(string, "kTo")<br/>      })))<br/>      raise_object_level_failure_alert                    = optional(bool)<br/>      raise_object_level_failure_alert_after_each_attempt = optional(bool)<br/>      raise_object_level_failure_alert_after_last_attempt = optional(bool)<br/>    }))<br/><br/>    # --- SLA ---<br/>    sla = optional(list(object({<br/>      backup_run_type = optional(string, "kIncremental") # kIncremental, kFull, kLog<br/>      sla_minutes     = number<br/>    })))<br/><br/>    # --- Scheduling ---<br/>    start_time = optional(object({<br/>      hour      = number<br/>      minute    = number<br/>      time_zone = optional(string, "America/Los_Angeles")<br/>    }))<br/><br/>    # --- Advanced configs (key/value pairs) ---<br/>    advanced_configs = optional(list(object({<br/>      key   = string<br/>      value = string<br/>    })))<br/><br/>    priority           = optional(string, "kMedium") # kLow, kMedium, kHigh<br/>    qos_policy         = optional(string)            # kBackupHDD, kBackupSSD, etc.<br/>    is_paused          = optional(bool, false)<br/>    abort_in_blackouts = optional(bool, false)<br/>    pause_in_blackouts = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_recoveries"></a> [recoveries](#input\_recoveries) | List of recovery operations to restore backups created by protection groups. Supports multiple environments: Kubernetes, VMware, Physical, AWS, Azure, GCP, SQL, Oracle, and more. This variable follows the official IBM Backup Recovery provider schema and can be used across different backup scenarios. For IKS/ROKS recovery, use kubernetes\_params. See the Usage section in the README for examples. | <pre>list(object({<br/>    name                 = string<br/>    snapshot_environment = string # kKubernetes, kVMware, kPhysical, kAWS, kAzure, kGCP, kSQL, kOracle, kView, etc.<br/><br/>    # Kubernetes-specific recovery parameters<br/>    kubernetes_params = optional(object({<br/>      recovery_action = string # RecoverNamespaces, RecoverPVs, RecoverApps<br/><br/>      objects = list(object({<br/>        snapshot_id           = string<br/>        point_in_time_usecs   = optional(number)<br/>        protection_group_id   = optional(string)<br/>        protection_group_name = optional(string)<br/>        recover_from_standby  = optional(bool, false)<br/>      }))<br/>    }))<br/><br/>    # VMware-specific recovery parameters (for future provider support)<br/>    vmware_params = optional(object({<br/>      recovery_action = optional(string)<br/>      objects = optional(list(object({<br/>        snapshot_id           = optional(string)<br/>        point_in_time_usecs   = optional(number)<br/>        protection_group_id   = optional(string)<br/>        protection_group_name = optional(string)<br/>        recover_from_standby  = optional(bool, false)<br/>      })))<br/>    }))<br/><br/>    # Physical server recovery parameters (for future provider support)<br/>    physical_params = optional(object({<br/>      recovery_action = optional(string)<br/>      objects = optional(list(object({<br/>        snapshot_id           = optional(string)<br/>        point_in_time_usecs   = optional(number)<br/>        protection_group_id   = optional(string)<br/>        protection_group_name = optional(string)<br/>      })))<br/>    }))<br/><br/>    # AWS-specific recovery parameters (for future provider support)<br/>    aws_params = optional(object({<br/>      recovery_action = optional(string)<br/>      objects = optional(list(object({<br/>        snapshot_id           = optional(string)<br/>        point_in_time_usecs   = optional(number)<br/>        protection_group_id   = optional(string)<br/>        protection_group_name = optional(string)<br/>      })))<br/>    }))<br/><br/>    # Azure-specific recovery parameters (for future provider support)<br/>    azure_params = optional(object({<br/>      recovery_action = optional(string)<br/>      objects = optional(list(object({<br/>        snapshot_id           = optional(string)<br/>        point_in_time_usecs   = optional(number)<br/>        protection_group_id   = optional(string)<br/>        protection_group_name = optional(string)<br/>      })))<br/>    }))<br/><br/>    # GCP-specific recovery parameters (for future provider support)<br/>    gcp_params = optional(object({<br/>      recovery_action = optional(string)<br/>      objects = optional(list(object({<br/>        snapshot_id           = optional(string)<br/>        point_in_time_usecs   = optional(number)<br/>        protection_group_id   = optional(string)<br/>        protection_group_name = optional(string)<br/>      })))<br/>    }))<br/><br/>    # SQL-specific recovery parameters (for future provider support)<br/>    sql_params = optional(object({<br/>      recovery_action = optional(string)<br/>      objects = optional(list(object({<br/>        snapshot_id           = optional(string)<br/>        point_in_time_usecs   = optional(number)<br/>        protection_group_id   = optional(string)<br/>        protection_group_name = optional(string)<br/>      })))<br/>    }))<br/><br/>    # Oracle-specific recovery parameters (for future provider support)<br/>    oracle_params = optional(object({<br/>      recovery_action = optional(string)<br/>      objects = optional(list(object({<br/>        snapshot_id           = optional(string)<br/>        point_in_time_usecs   = optional(number)<br/>        protection_group_id   = optional(string)<br/>        protection_group_name = optional(string)<br/>      })))<br/>    }))<br/>  }))</pre> | `[]` | no |
| <a name="input_region"></a> [region](#input\_region) | Region where the Backup & Recovery Service instance needs to be created. | `string` | `null` | no |
| <a name="input_registration_images"></a> [registration\_images](#input\_registration\_images) | The images required for backup and recovery registration. | <pre>object({<br/>    data_mover                  = string<br/>    velero                      = string<br/>    velero_aws_plugin           = string<br/>    velero_openshift_plugin     = string<br/>    cohesity_dataprotect_plugin = string<br/>    init_container              = optional(string, null)<br/>  })</pre> | <pre>{<br/>  "cohesity_dataprotect_plugin": "icr.io/ext/brs/cohesity-dataprotect-plugin:7.2.18@sha256:629fdf6852a9583674c41fc1ccbab3006c737067f5dccafbee2fe36fbc6ee748",<br/>  "data_mover": "icr.io/ext/brs/cohesity-datamover:7.2.18@sha256:f347698eb6180645d8c1b71d69a9fc40bb7c0bd14e5cdece9b7da79af74e8262",<br/>  "velero": "icr.io/ext/brs/oadp-velero:1.3.8@sha256:2d0014471b5c0e46cf96ac452069b9fa1ebbffd1d50a8ffecb2b443dbfbd4b00",<br/>  "velero_aws_plugin": "icr.io/ext/brs/oadp-velero-plugin-for-aws:1.3.8@sha256:3adcd0bfa963f980ad41dbff05c44c4b11d6b07e493a9c53a0ee3483a905039d",<br/>  "velero_openshift_plugin": "icr.io/ext/brs/oadp-velero-plugin-for-openshift:1.4.7@sha256:8b5dcea0fc837e5547c253f355d71b19f825eed6fac1e19c40af44b19fd7259a"<br/>}</pre> | no |
| <a name="input_resource_tags"></a> [resource\_tags](#input\_resource\_tags) | Add user resource tags to the Backup Recovery instance to organize, track, and manage costs. | `list(string)` | `[]` | no |
| <a name="input_rollback_on_failure"></a> [rollback\_on\_failure](#input\_rollback\_on\_failure) | Flag to automatically rollback the helm chart on installation failure. | `bool` | `true` | no |
| <a name="input_wait_till"></a> [wait\_till](#input\_wait\_till) | To avoid long wait times when you run your Terraform code, you can specify the stage when you want Terraform to mark the cluster resource creation as completed. Depending on what stage you choose, the cluster creation might not be fully completed and continues to run in the background. However, your Terraform code can continue to run without waiting for the cluster to be fully created. Supported args are `MasterNodeReady`, `OneWorkerNodeReady`, `IngressReady` and `Normal` | `string` | `"Normal"` | no |
| <a name="input_wait_till_timeout"></a> [wait\_till\_timeout](#input\_wait\_till\_timeout) | Timeout for wait\_till in minutes. | `number` | `90` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_brs_instance_crn"></a> [brs\_instance\_crn](#output\_brs\_instance\_crn) | CRN of the Backup & Recovery Service instance |
| <a name="output_brs_instance_guid"></a> [brs\_instance\_guid](#output\_brs\_instance\_guid) | GUID of the Backup & Recovery Service instance |
| <a name="output_brs_tags"></a> [brs\_tags](#output\_brs\_tags) | BRS tags that should be added to the cluster to prevent tag drift. Include these in your cluster's tags input. |
| <a name="output_brs_tenant_id"></a> [brs\_tenant\_id](#output\_brs\_tenant\_id) | Tenant ID of the Backup & Recovery Service instance |
| <a name="output_connection_id"></a> [connection\_id](#output\_connection\_id) | ID of the data source connection to the Backup & Recovery Service instance |
| <a name="output_protection_group_ids"></a> [protection\_group\_ids](#output\_protection\_group\_ids) | Map of protection group names to their IDs |
| <a name="output_protection_sources"></a> [protection\_sources](#output\_protection\_sources) | List of protection sources |
| <a name="output_recovery_ids"></a> [recovery\_ids](#output\_recovery\_ids) | Map of recovery operation names to their IDs |
| <a name="output_recovery_status"></a> [recovery\_status](#output\_recovery\_status) | Map of recovery operation names to their status information |
| <a name="output_source_registration_id"></a> [source\_registration\_id](#output\_source\_registration\_id) | ID of the registered Kubernetes source |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->

## Contributing

You can report issues and request features for this module in GitHub issues in the module repo. See [Report an issue or request a feature](https://github.com/terraform-ibm-modules/.github/blob/main/.github/SUPPORT.md).

To set up your local development environment, see [Local development setup](https://terraform-ibm-modules.github.io/documentation/#/local-dev-setup) in the project documentation.
