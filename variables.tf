##############################################################################
# Cluster variables
##############################################################################

variable "cluster_id" {
  type        = string
  description = "The ID of the cluster designated for backup and recovery."
}

variable "cluster_resource_group_id" {
  type        = string
  description = "Resource group ID the cluster is deployed in."
}

variable "cluster_config_endpoint_type" {
  description = "The type of endpoint to use for the cluster config access: `default`, `private`, `vpe`, or `link`. The `default` value uses the default endpoint of the cluster."
  type        = string
  default     = "default"
  nullable    = false # use default if null is passed in
  validation {
    error_message = "Invalid endpoint type. Valid values are `default`, `private`, `vpe`, or `link`."
    condition     = contains(["default", "private", "vpe", "link"], var.cluster_config_endpoint_type)
  }
}

variable "kube_type" {
  description = "Specify the type of target cluster for the backup and recovery. Accepted values are `openshift` or `kubernetes`."
  type        = string
  default     = "openshift"

  validation {
    condition = contains([
      "openshift",
      "kubernetes",
    ], var.kube_type)
    error_message = "Accepted values are: ROKS or IKS."
  }
}

variable "wait_till" {
  description = "To avoid long wait times when you run your Terraform code, you can specify the stage when you want Terraform to mark the cluster resource creation as completed. Depending on what stage you choose, the cluster creation might not be fully completed and continues to run in the background. However, your Terraform code can continue to run without waiting for the cluster to be fully created. Supported args are `MasterNodeReady`, `OneWorkerNodeReady`, `IngressReady` and `Normal`"
  type        = string
  default     = "Normal"

  validation {
    error_message = "`wait_till` value must be one of `MasterNodeReady`, `OneWorkerNodeReady`, `IngressReady` or `Normal`."
    condition = contains([
      "MasterNodeReady",
      "OneWorkerNodeReady",
      "IngressReady",
      "Normal"
    ], var.wait_till)
  }
}

variable "wait_till_timeout" {
  description = "Timeout for wait_till in minutes."
  type        = number
  default     = 90
}

##############################################################################
# Data Source Connector (BRS)
##############################################################################

variable "add_dsc_rules_to_cluster_sg" {
  type        = bool
  description = "Set to `true` to automatically add required security group rules for the Data Source Connector and set to `false` to only register the cluster and create the policy."
  default     = true
}

variable "dsc_chart" {
  description = "Name of the Data Source connector Helm chart."
  type        = string
  default     = "cohesity-dsc-chart"
  nullable    = false
}

variable "dsc_chart_location" {
  description = "OCI registry location of the Data Source Connector Helm chart."
  type        = string
  default     = "oci://icr.io/ext/brs"
  nullable    = false
}

variable "dsc_chart_version" {
  description = "Version of the Data Source Connector Helm chart to deploy."
  type        = string
  default     = "7.2.16-release-20251014-fbc7ff85"
  nullable    = false
}

variable "dsc_image_version" {
  description = "Container image for the Data Source Connector."
  type        = string
  default     = "icr.io/ext/brs/cohesity-data-source-connector:7.2.16@sha256:2674c764ca46310aef3adb733d950f7786d9bf560bf72c22cff52370e77e29b5"
  nullable    = false
  validation {
    condition     = length(split("@", var.dsc_image_version)[0]) > 0
    error_message = "The image version must be in the format '<registry>/<namespace>/<repository>:<semver-tag>@sha256:<64-hex-digest>'."
  }
}

variable "dsc_name" {
  description = "Release name for the Data Source Connector Helm deployment."
  type        = string
  default     = "dsc"
  nullable    = false
}

variable "dsc_replicas" {
  description = <<-EOT
  Number of Data Source Connector podsto run.
  Recommended values:
    • 3 – for high availability across multiple nodes/zones (strongly recommended in production)
    • 1 – only for dev/test or single-node clusters
  EOT
  type        = number
  default     = 1
  nullable    = false
}

variable "dsc_namespace" {
  type        = string
  description = "The cluster namespace where the Data Source Connector will be installed. Will be created if it does not exist."
  default     = "ibm-brs-data-source-connector"
  nullable    = false
}

variable "dsc_registration_token" {
  type        = string
  description = "Registration token generated in the Backup & Recovery Service UI when adding a cluster data source."
  sensitive   = true
  nullable    = false
}

##############################################################################
# Backup Recovery Service Instance
##############################################################################

variable "connection_id" {
  type        = string
  description = "Connection ID for the backup service"
}

variable "brs_instance_guid" {
  type        = string
  description = "GUID of the Backup & Recovery Service instance."
  nullable    = false
}

variable "brs_instance_region" {
  type        = string
  description = "Region of the Backup & Recovery Service instance."
  nullable    = false
  validation {
    condition     = contains(["us-east"], var.brs_instance_region)
    error_message = "Kubernetes & Opernshift backup recovery is only supported in these regions: \"us-east\"."
  }
}

variable "brs_endpoint_type" {
  type        = string
  description = "The endpoint type to use when connecting to the Backup and Recovery service for creating a data source connection. Allowed values are 'public' or 'private'."
  default     = "private"

  validation {
    condition     = contains(["public", "private"], var.brs_endpoint_type)
    error_message = "`endpoint_type` must be 'public' or 'private'."
  }
}

variable "brs_tenant_id" {
  type        = string
  description = "BRS tenant ID in the format `<tenant-guid>/`. Required for API calls and agent configuration."
  nullable    = false
}

variable "registration_name" {
  type        = string
  description = "Name of the registration."
  nullable    = false
}

variable "registration_images" {
  type = object({
    data_mover              = string
    velero                  = string
    velero_aws_plugin       = string
    velero_openshift_plugin = string
    init_container          = optional(string, null)
  })
  default = {
    data_mover              = "icr.io/ext/brs/cohesity-datamover:7.2.16@sha256:f7fa1cfbb74e469117d553c02deedf6f4a35b3a61647028a9424be346fc3eb09"
    velero                  = "icr.io/ext/brs/velero:7.2.16@sha256:1a5ee2393f0b1063ef095246d304c1ec4648c3af6a47261325ef039256a4a041"
    velero_aws_plugin       = "icr.io/ext/brs/velero-plugin-for-aws:7.2.16@sha256:dbcd35bcbf0d4c7deeae67b7dfd55c4fa51880b61307d71eeea3e9e84a370e13"
    velero_openshift_plugin = "icr.io/ext/brs/velero-plugin-for-openshift:7.2.16@sha256:6b643edcb920ad379c9ef1e2cca112a2ad0a1d55987f9c27af4022f7e3b19552"
  }
  description = "The images required for backup and recovery registration."
  nullable    = false
}

variable "policy" {
  type = object({
    name = string
    schedule = optional(object({
      unit      = string # Minutes, Hours, Days, Weeks, Months, Years, Runs
      frequency = number # required when unit is Minutes/Hours/Days

      # Optional extra layers (allowed even when unit = Minutes)
      minute_schedule = optional(object({ frequency = number }))
      hour_schedule   = optional(object({ frequency = number }))
      day_schedule    = optional(object({ frequency = number }))
      week_schedule   = optional(object({ day_of_week = list(string) }))
      month_schedule = optional(object({
        day_of_week   = optional(list(string))
        week_of_month = optional(string) # First, Second, Third, Fourth, Last
        day_of_month  = optional(number)
      }))
      year_schedule = optional(object({ day_of_year = string })) # First, Last
    }))

    retention = optional(object({
      duration = number
      unit     = string # Days, Weeks, Months, Years

      data_lock_config = optional(object({
        mode                           = string # Compliance, Administrative
        unit                           = string # Days, Weeks, Months, Years
        duration                       = number
        enable_worm_on_external_target = optional(bool, false)
      }))
    }))

    use_default_backup_target = optional(bool, true)
  })
  default = {
    name = "default-policy"
    schedule = {
      unit      = "Hours"
      frequency = 6
    }
    retention = {
      duration = 4
      unit     = "Weeks"
    }
    use_default_backup_target = true
  }
  validation {
    condition = contains(["Gold", "Silver", "Bronze"], var.policy.name) ? (
      var.policy.schedule == null && var.policy.retention == null
      ) : (
      var.policy.schedule != null && var.policy.retention != null
    )
    error_message = "If using built-in policies (Gold, Silver, Bronze), do not provide schedule or retention. For custom policies, both are required."
  }
  description = "The backup schedule and retentions of a Protection Policy."
}

variable "enable_auto_protect" {
  type        = bool
  description = "Set to `true` to enable auto-protect on the registered cluster with the specified protection policy."
  default     = false
}

variable "ibmcloud_api_key" {
  type        = string
  description = "The IBM Cloud api key to generate an IAM token."
  sensitive   = true
}
