# IBM Backup & Recovery for IKS/ROKS with Data Source Connector

[![Stable (With quality checks)](https://img.shields.io/badge/Status-Stable%20(With%20quality%20checks)-green)](https://terraform-ibm-modules.github.io/documentation/#/badge-status)
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

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_backup_recovery_instance"></a> [backup\_recovery\_instance](#module\_backup\_recovery\_instance) | terraform-ibm-modules/backup-recovery/ibm | v1.9.0 |
| <a name="module_crn_parser"></a> [crn\_parser](#module\_crn\_parser) | terraform-ibm-modules/common-utilities/ibm//modules/crn-parser | 1.5.0 |
| <a name="module_dsc_sg_rule"></a> [dsc\_sg\_rule](#module\_dsc\_sg\_rule) | terraform-ibm-modules/security-group/ibm | v2.9.0 |

### Resources

| Name | Type |
|------|------|
| [helm_release.data_source_connector](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [ibm_backup_recovery_protection_policy.protection_policy](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery_protection_policy) | resource |
| [ibm_backup_recovery_source_registration.source_registration](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery_source_registration) | resource |
| [ibm_container_vpc_worker_pool.data_source_connector](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/container_vpc_worker_pool) | resource |
| [ibm_resource_tag.cluster_brs_tag](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/resource_tag) | resource |
| [kubernetes_cluster_role_binding_v1.brsagent_admin](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cluster_role_binding_v1) | resource |
| [kubernetes_namespace_v1.dsc_namespace](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_secret_v1.brsagent_token](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [kubernetes_service_account_v1.brsagent](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account_v1) | resource |
| [terraform_data.delete_auto_protect_pg](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [ibm_backup_recovery_protection_policies.existing_policies](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/backup_recovery_protection_policies) | data source |
| [ibm_container_cluster.classic_cluster](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/container_cluster) | data source |
| [ibm_container_vpc_cluster.vpc_cluster](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/container_vpc_cluster) | data source |
| [ibm_container_vpc_worker_pool.pool](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/container_vpc_worker_pool) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_tags"></a> [access\_tags](#input\_access\_tags) | Add existing access management tags to the Backup Recovery instance to manage access. | `list(string)` | `[]` | no |
| <a name="input_add_dsc_rules_to_cluster_sg"></a> [add\_dsc\_rules\_to\_cluster\_sg](#input\_add\_dsc\_rules\_to\_cluster\_sg) | Set to `true` to automatically add the security group rules required by the Data Source Connector. This is mandatory when registering the cluster via its public service endpoint. Set to `false` to only register the cluster and create the policy without modifying security groups. | `bool` | `true` | no |
| <a name="input_brs_connection_name"></a> [brs\_connection\_name](#input\_brs\_connection\_name) | Name of the connection from the Backup & Recovery Service instance to be used for protecting the cluster. If `brs_create_new_connection` is set to `true` (default), this will be the name of the new connection created. If set to `false`, this must be the name of an existing connection. | `string` | n/a | yes |
| <a name="input_brs_create_new_connection"></a> [brs\_create\_new\_connection](#input\_brs\_create\_new\_connection) | Flag to create a new connection from the Backup & Recovery Service instance to the cluster. When set to `true` (default), a new connection is created with the name specified in `brs_connection_name`. When `false`, it uses an existing connection matching `brs_connection_name`. | `bool` | `true` | no |
| <a name="input_brs_endpoint_type"></a> [brs\_endpoint\_type](#input\_brs\_endpoint\_type) | The endpoint type to use when connecting to the Backup and Recovery service for creating a data source connection. Allowed values are 'public' or 'private'. | `string` | `"private"` | no |
| <a name="input_brs_instance_name"></a> [brs\_instance\_name](#input\_brs\_instance\_name) | Name of the Backup & Recovery Service instance. Required only when `existing_brs_instance_crn` is not provided. | `string` | `null` | no |
| <a name="input_cluster_config_endpoint_type"></a> [cluster\_config\_endpoint\_type](#input\_cluster\_config\_endpoint\_type) | The type of endpoint to use for the cluster config access: `default`, `private`, `vpe`, or `link`. The `default` value uses the default endpoint of the cluster. | `string` | `"default"` | no |
| <a name="input_cluster_id"></a> [cluster\_id](#input\_cluster\_id) | The ID of the cluster designated for backup and recovery. | `string` | n/a | yes |
| <a name="input_cluster_resource_group_id"></a> [cluster\_resource\_group\_id](#input\_cluster\_resource\_group\_id) | Resource group ID the cluster is deployed in. | `string` | n/a | yes |
| <a name="input_connection_env_type"></a> [connection\_env\_type](#input\_connection\_env\_type) | Connection environment type to determine the required parameters for creating a new connection. Allowed values are 'kIksVpc', 'kRoksVpc', 'kRoksClassic', and 'kIksClassic'. | `string` | `"kIksVpc"` | no |
| <a name="input_create_dsc_worker_pool"></a> [create\_dsc\_worker\_pool](#input\_create\_dsc\_worker\_pool) | Set to `true` to create a dedicated worker pool for the Data Source Connector in VPC clusters. If set to `false`, the connector will be deployed on existing worker nodes. | `bool` | `true` | no |
| <a name="input_dsc_chart_uri"></a> [dsc\_chart\_uri](#input\_dsc\_chart\_uri) | The full OCI registry URI for the Data Source Connector Helm chart, including the digest. | `string` | `"oci://icr.io/ext/brs/brs-ds-connector-chart:7.2.17-release-20260108-ed857f1c@sha256:0b3e84175cb8c1b2608e99e65fc72f2d5c4264dc0a0939ad98e089cc2bb7288e"` | no |
| <a name="input_dsc_helm_timeout"></a> [dsc\_helm\_timeout](#input\_dsc\_helm\_timeout) | Timeout in seconds for the Data Source Connector Helm deployment. | `number` | `1500` | no |
| <a name="input_dsc_image_version"></a> [dsc\_image\_version](#input\_dsc\_image\_version) | Container image for the Data Source Connector. | `string` | `"icr.io/ext/brs/brs-ds-connector:7.2.17-release-20260108-ed857f1c@sha256:560ff2170c880dc19712e0f37ba1575240e462f5e2a2ecbc4ecb791aa471f2d0"` | no |
| <a name="input_dsc_name"></a> [dsc\_name](#input\_dsc\_name) | Release name for the Data Source Connector Helm deployment. | `string` | `"dsc"` | no |
| <a name="input_dsc_namespace"></a> [dsc\_namespace](#input\_dsc\_namespace) | The cluster namespace where the Data Source Connector will be installed. Will be created if it does not exist. | `string` | `"ibm-brs-data-source-connector"` | no |
| <a name="input_dsc_replicas"></a> [dsc\_replicas](#input\_dsc\_replicas) | Number of Data Source Connector pods to run.<br/>Recommended values:<br/>  • 3 – for high availability across multiple nodes/zones (strongly recommended in production)<br/>  • 1 – only for dev/test or single-node clusters | `number` | `1` | no |
| <a name="input_dsc_storage_class"></a> [dsc\_storage\_class](#input\_dsc\_storage\_class) | Storage class to use for the Data Source Connector persistent volume. By default, it uses 'ibmc-vpc-block-metro-5iops-tier' for VPC clusters and 'ibmc-block-silver' for Classic clusters. | `string` | `null` | no |
| <a name="input_enable_auto_protect"></a> [enable\_auto\_protect](#input\_enable\_auto\_protect) | Enable auto-protect during the initial cluster registration. This must be set to `true` on the first run; toggling it from `false` to `true` later is not supported by the underlying API and will not retroactively create the protection group. | `bool` | `true` | no |
| <a name="input_existing_brs_instance_crn"></a> [existing\_brs\_instance\_crn](#input\_existing\_brs\_instance\_crn) | CRN of the Backup & Recovery Service instance. | `string` | `null` | no |
| <a name="input_ibmcloud_api_key"></a> [ibmcloud\_api\_key](#input\_ibmcloud\_api\_key) | The IBM Cloud api key to generate an IAM token. | `string` | n/a | yes |
| <a name="input_kube_type"></a> [kube\_type](#input\_kube\_type) | Specify the type of target cluster for the backup and recovery. Accepted values are `openshift` or `kubernetes`. | `string` | `"openshift"` | no |
| <a name="input_policy"></a> [policy](#input\_policy) | The backup schedule and retentions of a Protection Policy. | <pre>object({<br/>    name = string<br/>    schedule = optional(object({<br/>      unit      = string # Minutes, Hours, Days, Weeks, Months, Years, Runs<br/>      frequency = number # required when unit is Minutes/Hours/Days<br/><br/>      # Optional extra layers (allowed even when unit = Minutes)<br/>      minute_schedule = optional(object({ frequency = number }))<br/>      hour_schedule   = optional(object({ frequency = number }))<br/>      day_schedule    = optional(object({ frequency = number }))<br/>      week_schedule   = optional(object({ day_of_week = list(string) }))<br/>      month_schedule = optional(object({<br/>        day_of_week   = optional(list(string))<br/>        week_of_month = optional(string) # First, Second, Third, Fourth, Last<br/>        day_of_month  = optional(number)<br/>      }))<br/>      year_schedule = optional(object({ day_of_year = string })) # First, Last<br/>    }))<br/><br/>    retention = optional(object({<br/>      duration = number<br/>      unit     = string # Days, Weeks, Months, Years<br/><br/>      data_lock_config = optional(object({<br/>        mode                           = string # Compliance, Administrative<br/>        unit                           = string # Days, Weeks, Months, Years<br/>        duration                       = number<br/>        enable_worm_on_external_target = optional(bool, false)<br/>      }))<br/>    }))<br/><br/>    use_default_backup_target = optional(bool, true)<br/><br/>    # --- Full backup schedule (periodic full backups on top of incrementals) ---<br/>    full_schedule = optional(object({<br/>      unit          = string # Days, Weeks, Months, Years, ProtectOnce<br/>      day_schedule  = optional(object({ frequency = number }))<br/>      week_schedule = optional(object({ day_of_week = list(string) }))<br/>      month_schedule = optional(object({<br/>        day_of_week   = optional(list(string))<br/>        week_of_month = optional(string)<br/>        day_of_month  = optional(number)<br/>      }))<br/>      year_schedule = optional(object({ day_of_year = string }))<br/><br/>      retention = object({<br/>        duration = number<br/>        unit     = string # Days, Weeks, Months, Years<br/>        data_lock_config = optional(object({<br/>          mode                           = string<br/>          unit                           = string<br/>          duration                       = number<br/>          enable_worm_on_external_target = optional(bool, false)<br/>        }))<br/>      })<br/>    }))<br/><br/>    # --- Blackout windows (time windows when backups should not run) ---<br/>    blackout_window = optional(list(object({<br/>      day = string # Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday<br/>      start_time = object({<br/>        hour      = number<br/>        minute    = number<br/>        time_zone = optional(string, "America/New_York")<br/>      })<br/>      end_time = object({<br/>        hour      = number<br/>        minute    = number<br/>        time_zone = optional(string, "America/New_York")<br/>      })<br/>    })))<br/><br/>    # --- Run timeouts (prevent hung backup jobs) ---<br/>    run_timeouts = optional(list(object({<br/>      timeout_mins = number<br/>      backup_type  = optional(string, "kRegular") # kRegular, kFull, kLog, kSystem, kHydrateCDP, kStorageArraySnapshot<br/>    })))<br/><br/>    # --- Extended retention (keep certain snapshots longer) ---<br/>    extended_retention = optional(list(object({<br/>      schedule = object({<br/>        unit      = string # Runs, Days, Weeks, Months, Years<br/>        frequency = number<br/>      })<br/>      retention = object({<br/>        duration = number<br/>        unit     = string # Days, Weeks, Months, Years<br/>        data_lock_config = optional(object({<br/>          mode                           = string<br/>          unit                           = string<br/>          duration                       = number<br/>          enable_worm_on_external_target = optional(bool, false)<br/>        }))<br/>      })<br/>      run_type  = optional(string, "Regular")<br/>      config_id = optional(string)<br/>    })))<br/>  })</pre> | <pre>{<br/>  "name": "default-policy",<br/>  "retention": {<br/>    "duration": 4,<br/>    "unit": "Weeks"<br/>  },<br/>  "schedule": {<br/>    "frequency": 6,<br/>    "unit": "Hours"<br/>  },<br/>  "use_default_backup_target": true<br/>}</pre> | no |
| <a name="input_region"></a> [region](#input\_region) | Region where the Backup & Recovery Service instance needs to be created. | `string` | `null` | no |
| <a name="input_registration_images"></a> [registration\_images](#input\_registration\_images) | The images required for backup and recovery registration. | <pre>object({<br/>    data_mover                  = string<br/>    velero                      = string<br/>    velero_aws_plugin           = string<br/>    velero_openshift_plugin     = string<br/>    cohesity_dataprotect_plugin = string<br/>    init_container              = optional(string, null)<br/>  })</pre> | <pre>{<br/>  "cohesity_dataprotect_plugin": "icr.io/ext/brs/cohesity-dataprotect-plugin:7.2.17@sha256:d7b0e02b267f27aa41c2879bb5c8dcafe9e2e6e0a825fa9e4116a7cd41403983",<br/>  "data_mover": "icr.io/ext/brs/cohesity-datamover:7.2.17@sha256:2b9e69f37752c6f8758b8de61b4c4ec6ccc60083d23211f59b07780069e9ddf8",<br/>  "velero": "icr.io/ext/brs/oadp-velero:1.3.8@sha256:2d0014471b5c0e46cf96ac452069b9fa1ebbffd1d50a8ffecb2b443dbfbd4b00",<br/>  "velero_aws_plugin": "icr.io/ext/brs/oadp-velero-plugin-for-aws:1.3.8@sha256:3adcd0bfa963f980ad41dbff05c44c4b11d6b07e493a9c53a0ee3483a905039d",<br/>  "velero_openshift_plugin": "icr.io/ext/brs/oadp-velero-plugin-for-openshift:1.4.7@sha256:8b5dcea0fc837e5547c253f355d71b19f825eed6fac1e19c40af44b19fd7259a"<br/>}</pre> | no |
| <a name="input_resource_tags"></a> [resource\_tags](#input\_resource\_tags) | Add user resource tags to the Backup Recovery instance to organize, track, and manage costs. | `list(string)` | `[]` | no |
| <a name="input_rollback_on_failure"></a> [rollback\_on\_failure](#input\_rollback\_on\_failure) | Flag to automatically rollback the helm chart on installation failure. | `bool` | `true` | no |
| <a name="input_wait_till"></a> [wait\_till](#input\_wait\_till) | To avoid long wait times when you run your Terraform code, you can specify the stage when you want Terraform to mark the cluster resource creation as completed. Depending on what stage you choose, the cluster creation might not be fully completed and continues to run in the background. However, your Terraform code can continue to run without waiting for the cluster to be fully created. Supported args are `MasterNodeReady`, `OneWorkerNodeReady`, `IngressReady` and `Normal` | `string` | `"Normal"` | no |
| <a name="input_wait_till_timeout"></a> [wait\_till\_timeout](#input\_wait\_till\_timeout) | Timeout for wait\_till in minutes. | `number` | `90` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_brs_instance_crn"></a> [brs\_instance\_crn](#output\_brs\_instance\_crn) | CRN of the Backup & Recovery Service instance |
| <a name="output_brs_instance_guid"></a> [brs\_instance\_guid](#output\_brs\_instance\_guid) | GUID of the Backup & Recovery Service instance |
| <a name="output_brs_tenant_id"></a> [brs\_tenant\_id](#output\_brs\_tenant\_id) | Tenant ID of the Backup & Recovery Service instance |
| <a name="output_connection_id"></a> [connection\_id](#output\_connection\_id) | ID of the data source connection to the Backup & Recovery Service instance |
| <a name="output_protection_policy_id"></a> [protection\_policy\_id](#output\_protection\_policy\_id) | ID of the protection policy (null if using an existing policy) |
| <a name="output_source_registration_id"></a> [source\_registration\_id](#output\_source\_registration\_id) | ID of the registered Kubernetes source |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Contributing

You can report issues and request features for this module in GitHub issues in the module repo. See [Report an issue or request a feature](https://github.com/terraform-ibm-modules/.github/blob/main/.github/SUPPORT.md).

To set up your local development environment, see [Local development setup](https://terraform-ibm-modules.github.io/documentation/#/local-dev-setup) in the project documentation.
