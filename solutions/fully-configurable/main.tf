# Retrieve information about an existing VPC cluster
data "ibm_container_vpc_cluster" "vpc_cluster" {
  name              = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  wait_till         = var.wait_till
  wait_till_timeout = var.wait_till_timeout
}

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  config_dir        = "${path.module}/kubeconfig"
  endpoint_type     = var.cluster_config_endpoint_type != "default" ? var.cluster_config_endpoint_type : null
  admin             = true

  # Wait for cluster to be ready before fetching config
  # This prevents timeouts when cluster is still provisioning
  depends_on = [
    data.ibm_container_vpc_cluster.vpc_cluster
  ]
}

module "existing_brs_crn_parser" {
  count   = var.existing_brs_instance_crn != null ? 1 : 0
  source  = "terraform-ibm-modules/common-utilities/ibm//modules/crn-parser"
  version = "1.5.0"
  crn     = var.existing_brs_instance_crn
}

locals {
  region = var.existing_brs_instance_crn != null ? module.existing_brs_crn_parser[0].region : var.region
}

module "protect_cluster" {
  source                       = "../.."
  cluster_id                   = var.cluster_id
  cluster_resource_group_id    = var.cluster_resource_group_id
  cluster_config_endpoint_type = var.cluster_config_endpoint_type
  add_dsc_rules_to_cluster_sg  = var.add_dsc_rules_to_cluster_sg
  kube_type                    = var.kube_type
  ibmcloud_api_key             = var.ibmcloud_api_key
  # --- BRS Instance Details---
  brs_endpoint_type         = var.brs_endpoint_type
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_instance_name         = var.brs_instance_name
  # --- BRS Connection Details---
  brs_connection_name       = var.brs_connection_name
  brs_create_new_connection = var.brs_create_new_connection
  region                    = local.region
  connection_env_type       = var.connection_env_type
  # --- Backup Policy ---
  auto_protect_policy_name = var.auto_protect_policy_name
  protection_groups        = var.protection_groups
  wait_till                = var.wait_till
  wait_till_timeout        = var.wait_till_timeout
  # --- Data Source Connector (DSC) ---
  dsc_chart_uri          = var.dsc_chart_uri
  dsc_image_version      = var.dsc_image_version
  dsc_name               = var.dsc_name
  dsc_replicas           = var.dsc_replicas
  dsc_namespace          = var.dsc_namespace
  dsc_helm_timeout       = var.dsc_helm_timeout
  dsc_storage_class      = var.dsc_storage_class
  create_dsc_worker_pool = var.create_dsc_worker_pool
  rollback_on_failure    = var.rollback_on_failure
  # --- Registration Settings ---
  registration_images = var.registration_images
  enable_auto_protect = var.enable_auto_protect
  # --- Policies ---
  policies = var.policies
  # --- Resource Tags ---
  resource_tags = var.resource_tags
  access_tags   = var.access_tags
}


##############################################################################
# Recovery Configuration (Optional)
##############################################################################

locals {
  # Determine which protection group to use for recovery
  recovery_pg_name = var.enable_recovery ? (
    var.recovery_protection_group_name != null ? var.recovery_protection_group_name :
    try(length(var.protection_groups), 0) > 0 ? var.protection_groups[0].name :
    var.auto_protect_policy_name
  ) : null

  # Extract protection group ID for recovery
  recovery_pg_id = var.enable_recovery && local.recovery_pg_name != null ? (
    try(split("::", module.protect_cluster.protection_group_ids[local.recovery_pg_name])[1], null)
  ) : null
}

##############################################################################
# Cross-Cluster Recovery: Target Cluster Registration
##############################################################################

# Only needed for cross-cluster recovery
data "ibm_container_vpc_cluster" "target_cluster" {
  count             = var.enable_recovery && var.recovery_type == "cross-cluster" ? 1 : 0
  name              = var.target_cluster_id
  resource_group_id = var.target_cluster_resource_group_id
  wait_till         = var.wait_till
  wait_till_timeout = var.wait_till_timeout
}

data "ibm_container_cluster_config" "target_cluster_config" {
  depends_on = [data.ibm_container_vpc_cluster.target_cluster]

  count             = var.enable_recovery && var.recovery_type == "cross-cluster" ? 1 : 0
  cluster_name_id   = var.target_cluster_id
  resource_group_id = var.target_cluster_resource_group_id
  config_dir        = "${path.module}/kubeconfig"
  endpoint_type     = var.target_cluster_config_endpoint_type == "default" ? null : var.target_cluster_config_endpoint_type
  admin             = true
}

# Register target cluster with BRS for cross-cluster recovery
module "target_cluster_registration" {
  count  = var.enable_recovery && var.recovery_type == "cross-cluster" ? 1 : 0
  source = "../.."

  providers = {
    helm       = helm.target
    kubernetes = kubernetes.target
  }

  cluster_id                   = var.target_cluster_id
  cluster_resource_group_id    = var.target_cluster_resource_group_id
  cluster_config_endpoint_type = var.target_cluster_config_endpoint_type
  add_dsc_rules_to_cluster_sg  = var.add_dsc_rules_to_cluster_sg
  kube_type                    = var.kube_type
  ibmcloud_api_key             = var.ibmcloud_api_key

  # Use same BRS instance as source
  existing_brs_instance_crn = module.protect_cluster.brs_instance_crn
  brs_endpoint_type         = var.brs_endpoint_type
  region                    = local.region

  # Target connection configuration
  brs_connection_name       = var.target_brs_connection_name != null ? var.target_brs_connection_name : "${var.target_cluster_id}-target-connection"
  brs_create_new_connection = true
  connection_env_type       = var.connection_env_type

  # DSC configuration for target
  dsc_chart_uri          = var.dsc_chart_uri
  dsc_image_version      = var.dsc_image_version
  dsc_name               = var.dsc_name
  dsc_replicas           = var.dsc_replicas
  dsc_namespace          = var.dsc_namespace
  dsc_helm_timeout       = var.dsc_helm_timeout
  dsc_storage_class      = var.dsc_storage_class
  create_dsc_worker_pool = var.target_create_dsc_worker_pool
  rollback_on_failure    = var.rollback_on_failure

  # Registration settings
  registration_images = var.registration_images
  enable_auto_protect = false # Don't auto-protect target cluster

  # No policies or protection groups for target (it's just a recovery destination)
  policies          = []
  protection_groups = null

  # Tags
  resource_tags = var.resource_tags
  access_tags   = var.access_tags

  depends_on = [
    data.ibm_container_cluster_config.target_cluster_config
  ]
}

# Wait for target registration to propagate
resource "time_sleep" "wait_for_target_registration" {
  count = var.enable_recovery && var.recovery_type == "cross-cluster" ? 1 : 0

  depends_on = [module.target_cluster_registration]

  create_duration = "90s"
}

##############################################################################
# Immediate Backup Trigger and Completion Polling
##############################################################################

# Trigger an immediate on-demand backup run for the recovery protection group.
resource "ibm_backup_recovery_protection_group_run_request" "recovery_backup_run" {
  count = var.enable_recovery ? 1 : 0

  x_ibm_tenant_id = module.protect_cluster.brs_tenant_id
  group_id        = local.recovery_pg_id
  run_type        = "kRegular"
  endpoint_type   = var.brs_endpoint_type
  instance_id     = module.protect_cluster.brs_instance_guid
  region          = local.region

  # Only depends on source cluster - backup triggers immediately when PG is ready
  depends_on = [
    module.protect_cluster
  ]
}

# Poll for backup completion before attempting recovery
resource "terraform_data" "wait_for_backup" {
  count = var.enable_recovery ? 1 : 0

  depends_on = [
    module.protect_cluster,
    time_sleep.wait_for_target_registration,
    ibm_backup_recovery_protection_group_run_request.recovery_backup_run
  ]

  input = {
    url                   = "https://${module.protect_cluster.brs_instance_guid}.${local.region}.backup-recovery.cloud.ibm.com"
    tenant                = module.protect_cluster.brs_tenant_id
    endpoint_type         = var.brs_endpoint_type
    instance_id           = module.protect_cluster.brs_instance_guid
    protection_group_id   = local.recovery_pg_id
    api_key               = sensitive(var.ibmcloud_api_key)
    timeout_minutes       = var.recovery_wait_timeout_minutes
    poll_interval_seconds = var.recovery_poll_interval_seconds
    binaries_path         = "/tmp"
  }

  provisioner "local-exec" {
    command     = "${path.module}/../../scripts/wait_for_backup_run.sh '${self.input.url}' '${self.input.tenant}' '${self.input.endpoint_type}' '${self.input.instance_id}' '${self.input.protection_group_id}' '${self.input.timeout_minutes}' '${self.input.poll_interval_seconds}' '${self.input.binaries_path}' > /tmp/backup_snapshot_${self.input.instance_id}.json"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      IBMCLOUD_API_KEY = self.input.api_key # pragma: allowlist secret
    }
  }
}

# Read the snapshot ID from the file created by polling
data "local_file" "snapshot_info" {
  count = var.enable_recovery ? 1 : 0

  filename = "/tmp/backup_snapshot_${module.protect_cluster.brs_instance_guid}.json"

  depends_on = [terraform_data.wait_for_backup]
}

locals {
  snapshot_data = var.enable_recovery ? jsondecode(data.local_file.snapshot_info[0].content) : null
}

##############################################################################
# Same-Cluster Recovery
##############################################################################

resource "terraform_data" "same_cluster_recovery" {
  count = var.enable_recovery && var.recovery_type == "same-cluster" ? 1 : 0

  input = {
    url              = "https://${module.protect_cluster.brs_instance_guid}.${local.region}.backup-recovery.cloud.ibm.com"
    tenant           = module.protect_cluster.brs_tenant_id
    endpoint_type    = var.brs_endpoint_type
    instance_id      = module.protect_cluster.brs_instance_guid
    source_pg_id     = local.recovery_pg_id
    target_source_id = split("::", module.protect_cluster.source_registration_id)[1]
    snapshot_id      = local.snapshot_data.snapshot_id
    api_key          = sensitive(var.ibmcloud_api_key)
    recovery_name    = "recovery-${local.recovery_pg_name}-${formatdate("YYYYMMDD-hhmm", timestamp())}"
    binaries_path    = "/tmp"
    namespace_prefix = var.recovery_namespace_prefix
  }

  provisioner "local-exec" {
    command = <<-EOT
      ${path.module}/../../scripts/trigger_cross_cluster_recovery.sh \
        '${self.input.url}' \
        '${self.input.tenant}' \
        '${self.input.endpoint_type}' \
        '${self.input.instance_id}' \
        '${self.input.source_pg_id}' \
        '${self.input.target_source_id}' \
        '${self.input.snapshot_id}' \
        '${self.input.recovery_name}' \
        '${self.input.namespace_prefix}' \
        '${self.input.binaries_path}'
    EOT
    environment = {
      IBMCLOUD_API_KEY = self.input.api_key # pragma: allowlist secret
    }
  }

  depends_on = [
    terraform_data.wait_for_backup,
    data.local_file.snapshot_info
  ]
}

##############################################################################
# Cross-Cluster Recovery
##############################################################################

resource "terraform_data" "cross_cluster_recovery" {
  count = var.enable_recovery && var.recovery_type == "cross-cluster" ? 1 : 0

  input = {
    url              = "https://${module.protect_cluster.brs_instance_guid}.${local.region}.backup-recovery.cloud.ibm.com"
    tenant           = module.protect_cluster.brs_tenant_id
    endpoint_type    = var.brs_endpoint_type
    instance_id      = module.protect_cluster.brs_instance_guid
    source_pg_id     = local.recovery_pg_id
    target_source_id = split("::", module.target_cluster_registration[0].source_registration_id)[1]
    snapshot_id      = local.snapshot_data.snapshot_id
    api_key          = sensitive(var.ibmcloud_api_key)
    recovery_name    = "cross-cluster-recovery-${local.recovery_pg_name}-${formatdate("YYYYMMDD-hhmm", timestamp())}"
    binaries_path    = "/tmp"
    namespace_prefix = var.recovery_namespace_prefix
  }

  provisioner "local-exec" {
    command = <<-EOT
      ${path.module}/../../scripts/trigger_cross_cluster_recovery.sh \
        '${self.input.url}' \
        '${self.input.tenant}' \
        '${self.input.endpoint_type}' \
        '${self.input.instance_id}' \
        '${self.input.source_pg_id}' \
        '${self.input.target_source_id}' \
        '${self.input.snapshot_id}' \
        '${self.input.recovery_name}' \
        '${self.input.namespace_prefix}' \
        '${self.input.binaries_path}'
    EOT
    environment = {
      IBMCLOUD_API_KEY = self.input.api_key # pragma: allowlist secret
    }
  }

  depends_on = [
    terraform_data.wait_for_backup,
    data.local_file.snapshot_info,
    module.target_cluster_registration,
    time_sleep.wait_for_target_registration
  ]
}
