locals {
  # --- Environment type detection ---
  is_vpc     = length(regexall("Vpc$", var.connection_env_type)) > 0
  is_classic = length(regexall("Classic$", var.connection_env_type)) > 0

  # --- Recovery mode detection ---
  is_full_recovery = var.deployment_mode == "full_backup_recovery"
}
# Retrieve information about an existing VPC cluster
# Uses ibm.cluster provider — source account in cross-account deployments.
data "ibm_container_vpc_cluster" "vpc_cluster" {
  count             = local.is_vpc ? 1 : 0
  provider          = ibm.cluster
  name              = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  wait_till         = var.wait_till
  wait_till_timeout = var.wait_till_timeout
}

# Retrieve information about an existing Classic cluster
data "ibm_container_cluster" "classic_cluster" {
  count             = local.is_classic ? 1 : 0
  provider          = ibm.cluster
  name              = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  wait_till         = var.wait_till
  wait_till_timeout = var.wait_till_timeout
}
data "ibm_container_cluster_config" "cluster_config" {
  provider          = ibm.cluster
  cluster_name_id   = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  config_dir        = "${path.module}/kubeconfig"
  endpoint_type     = var.cluster_config_endpoint_type != "default" ? var.cluster_config_endpoint_type : null
  admin             = true

  # Wait for cluster to be ready before fetching config
  # This prevents timeouts when cluster is still provisioning
  depends_on = [
    data.ibm_container_vpc_cluster.vpc_cluster,
    data.ibm_container_cluster.classic_cluster
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
  source = "../.."
  providers = {
    ibm         = ibm         # target (BRS) account — or only account in same-account mode
    ibm.cluster = ibm.cluster # source (cluster/VPC) account — same as ibm when source_ibmcloud_api_key is null
  }
  # --- Cluster ---
  cluster_id                   = var.cluster_id
  cluster_resource_group_id    = var.cluster_resource_group_id
  cluster_config_endpoint_type = var.cluster_config_endpoint_type
  add_dsc_rules_to_cluster_sg  = var.add_dsc_rules_to_cluster_sg
  add_cluster_tags             = var.add_cluster_tags
  kube_type                    = var.kube_type
  wait_till                    = var.wait_till
  wait_till_timeout            = var.wait_till_timeout
  # --- Deployment Mode ---
  deployment_mode = var.deployment_mode
  # --- BRS Instance ---
  ibmcloud_api_key          = var.ibmcloud_api_key
  brs_endpoint_type         = var.brs_endpoint_type
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_instance_name         = var.brs_instance_name
  brs_resource_group_id     = var.brs_resource_group_id
  region                    = local.region
  # --- BRS Connection ---
  brs_connection_name       = var.brs_connection_name
  brs_create_new_connection = var.brs_create_new_connection
  connection_env_type       = var.connection_env_type
  # --- VPE + S2S (cross-account and same-account private routing) ---
  create_brs_vpe        = var.create_brs_vpe
  vpc_id                = var.vpc_id
  vpc_subnets           = var.vpc_subnets
  brs_source_account_id = var.brs_source_account_id
  brs_vpe_name          = var.brs_vpe_name
  # --- Data Source Connector (DSC) ---
  dsc_chart_uri           = var.dsc_chart_uri
  dsc_name                = var.dsc_name
  dsc_replicas            = var.dsc_replicas
  dsc_namespace           = var.dsc_namespace
  dsc_helm_timeout        = var.dsc_helm_timeout
  dsc_storage_class       = var.dsc_storage_class
  create_dsc_worker_pool  = var.create_dsc_worker_pool
  dsc_worker_pool_zones   = var.dsc_worker_pool_zones
  dsc_worker_pool_flavor  = var.dsc_worker_pool_flavor
  dsc_pod_cpu_limits      = var.dsc_pod_cpu_limits
  dsc_pod_memory_limits   = var.dsc_pod_memory_limits
  dsc_pod_cpu_requests    = var.dsc_pod_cpu_requests
  dsc_pod_memory_requests = var.dsc_pod_memory_requests
  # --- Registration Settings ---
  registration_images = var.registration_images
  enable_auto_protect = var.enable_auto_protect
  # --- Backup Policy ---
  auto_protect_policy_name = var.auto_protect_policy_name
  protection_groups        = var.protection_groups
  policies                 = var.policies
  # --- Resource Tags ---
  resource_tags = var.resource_tags
  access_tags   = var.access_tags
  # --- Recovery Settings ---
  recovery_mode                    = var.recovery_type
  target_cluster_id                = var.target_cluster_id
  target_cluster_resource_group_id = var.target_cluster_resource_group_id
}


##############################################################################
# Recovery Configuration (Optional)
##############################################################################

locals {
  # Determine which protection group to use for recovery
  # Only applicable in full_backup_recovery mode
  recovery_pg_name = local.is_full_recovery ? (
    var.recovery_protection_group_name != null ? var.recovery_protection_group_name :
    try(length(var.protection_groups), 0) > 0 ? var.protection_groups[0].name :
    var.auto_protect_policy_name
  ) : null

}

##############################################################################
# Target Cluster Registration
##############################################################################

# Needed for:
# 1. connected_component mode - to register both source and target clusters
# 2. full_backup_recovery mode with cross-cluster recovery
locals {
  deploy_target_cluster = (
    var.deployment_mode == "connected_component" ||
    (local.is_full_recovery && var.recovery_type == "cross-cluster")
  )
}

data "ibm_container_vpc_cluster" "target_cluster" {
  count             = local.deploy_target_cluster ? 1 : 0
  provider          = ibm.cluster
  name              = var.target_cluster_id
  resource_group_id = var.target_cluster_resource_group_id
  wait_till         = var.wait_till
  wait_till_timeout = var.wait_till_timeout
}

data "ibm_container_cluster_config" "target_cluster_config" {
  depends_on = [data.ibm_container_vpc_cluster.target_cluster]

  count             = local.deploy_target_cluster ? 1 : 0
  provider          = ibm.cluster
  cluster_name_id   = var.target_cluster_id
  resource_group_id = var.target_cluster_resource_group_id
  config_dir        = "${path.module}/kubeconfig"
  endpoint_type     = var.target_cluster_config_endpoint_type == "default" ? null : var.target_cluster_config_endpoint_type
  admin             = true
}

# Register target cluster with BRS
module "target_cluster_registration" {
  count  = local.deploy_target_cluster ? 1 : 0
  source = "../.."

  providers = {
    ibm         = ibm         # target (BRS) account
    ibm.cluster = ibm.cluster # source (cluster/VPC) account — same as ibm when source_ibmcloud_api_key is null
    helm        = helm.target
    kubernetes  = kubernetes.target
  }

  cluster_id                   = var.target_cluster_id
  cluster_resource_group_id    = var.target_cluster_resource_group_id
  cluster_config_endpoint_type = var.target_cluster_config_endpoint_type
  add_dsc_rules_to_cluster_sg  = var.add_dsc_rules_to_cluster_sg
  kube_type                    = var.kube_type
  ibmcloud_api_key             = var.ibmcloud_api_key

  # Use same BRS instance as source. The source's BRS instance CRN is only known
  # after apply when the source creates a new instance, so create_new_instance is
  # set explicitly to false to keep the module's count/for_each gates from
  # depending on that unknown value at plan time.
  existing_brs_instance_crn = module.protect_cluster.brs_instance_crn
  create_new_brs_instance   = false
  brs_endpoint_type         = var.brs_endpoint_type
  region                    = local.region

  # Target connection configuration
  brs_connection_name       = var.target_brs_connection_name != null ? var.target_brs_connection_name : "${var.target_cluster_id}-target-connection"
  brs_create_new_connection = var.target_brs_create_new_connection
  connection_env_type       = var.connection_env_type

  # DSC configuration for target
  dsc_chart_uri          = var.dsc_chart_uri
  dsc_name               = var.dsc_name
  dsc_replicas           = var.dsc_replicas
  dsc_namespace          = var.dsc_namespace
  dsc_helm_timeout       = var.dsc_helm_timeout
  dsc_storage_class      = var.dsc_storage_class
  create_dsc_worker_pool = var.target_create_dsc_worker_pool

  # Registration settings
  registration_images = var.registration_images
  enable_auto_protect = false # Don't auto-protect target cluster

  # No policies or protection groups for target (it's just a recovery destination)
  policies          = []
  protection_groups = null

  # --- VPE (target cluster's own VPC — needed when target is in a different VPC from source) ---
  create_brs_vpe        = var.target_create_brs_vpe
  vpc_id                = var.target_vpc_id
  vpc_subnets           = var.target_vpc_subnets
  brs_source_account_id = var.brs_source_account_id
  brs_vpe_name          = var.target_brs_vpe_name

  # Tags
  resource_tags = var.resource_tags
  access_tags   = var.access_tags

  depends_on = [
    data.ibm_container_cluster_config.target_cluster_config
  ]
}

# Wait for target registration to propagate
resource "time_sleep" "wait_for_target_registration" {
  count = local.deploy_target_cluster ? 1 : 0

  depends_on = [module.target_cluster_registration]

  create_duration = "90s"
}

##############################################################################
# Backup Completion Polling
##############################################################################

# module.protect_cluster already triggers an on-demand backup run for every
# protection group when deployment_mode is "full_backup_recovery" (see
# terraform_data.trigger_backup_run in the root module). Triggering a second
# run here would race with that one, so this only polls for the backup that
# module.protect_cluster already started.
resource "terraform_data" "wait_for_backup" {
  count = local.is_full_recovery ? 1 : 0

  depends_on = [
    module.protect_cluster,
    time_sleep.wait_for_target_registration
  ]

  input = {
    url                   = module.protect_cluster.brs_instance_url
    tenant                = module.protect_cluster.brs_tenant_id
    endpoint_type         = var.brs_endpoint_type
    instance_id           = module.protect_cluster.brs_instance_guid
    api_key               = sensitive(var.ibmcloud_api_key)
    timeout_minutes       = var.recovery_wait_timeout_minutes
    poll_interval_seconds = var.recovery_poll_interval_seconds
    binaries_path         = "/tmp"
    # protection_group_id is resolved from module outputs after apply.
    # It is passed via environment variable (not interpolated into the command
    # string) so that a null/unknown value at plan time does not cause
    # "Cannot include a null value in a string template".
    protection_group_id = coalesce(
      # explicit PG from for_each (used when protection_groups var is set)
      try(module.protect_cluster.protection_group_ids[local.recovery_pg_name], null),
      # auto-protect PG (used when enable_auto_protect=true)
      module.protect_cluster.auto_protect_pg_id,
      # plan-time placeholder — replaced by the real value at apply
      ""
    )
  }

  provisioner "local-exec" {
    command     = "${path.module}/../../scripts/wait_for_backup_run.sh '${self.input.url}' '${self.input.tenant}' '${self.input.endpoint_type}' '${self.input.instance_id}' \"$BRS_PG_ID\" '${self.input.timeout_minutes}' '${self.input.poll_interval_seconds}' '${self.input.binaries_path}' > /tmp/backup_snapshot_${self.input.instance_id}.json"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      IBMCLOUD_API_KEY = self.input.api_key # pragma: allowlist secret
      BRS_PG_ID        = self.input.protection_group_id
    }
  }
}

##############################################################################
# Same-Cluster Recovery
##############################################################################

resource "terraform_data" "same_cluster_recovery" {
  count = local.is_full_recovery && var.recovery_type == "same-cluster" ? 1 : 0

  input = {
    url           = module.protect_cluster.brs_instance_url
    tenant        = module.protect_cluster.brs_tenant_id
    endpoint_type = var.brs_endpoint_type
    instance_id   = module.protect_cluster.brs_instance_guid
    source_pg_id = coalesce(
      try(module.protect_cluster.protection_group_ids[local.recovery_pg_name], null),
      module.protect_cluster.auto_protect_pg_id,
      ""
    )
    target_source_id = split("::", module.protect_cluster.source_registration_id)[1]
    api_key          = sensitive(var.ibmcloud_api_key)
    recovery_name    = "recovery-${local.recovery_pg_name}-${formatdate("YYYYMMDD-hhmm", timestamp())}"
    binaries_path    = "/tmp"
    namespace_prefix = var.recovery_namespace_prefix
  }

  provisioner "local-exec" {
    # wait_for_backup_run.sh writes snapshot info to this file before this resource is applied.
    # jq is available in the Schematics environment (used by wait_for_backup_run.sh itself).
    command = <<-EOT
      SNAPSHOT_ID=$(jq -r '.snapshot_id' /tmp/backup_snapshot_${self.input.instance_id}.json)
      ${path.module}/../../scripts/trigger_cross_cluster_recovery.sh \
        '${self.input.url}' \
        '${self.input.tenant}' \
        '${self.input.endpoint_type}' \
        '${self.input.instance_id}' \
        "$BRS_PG_ID" \
        '${self.input.target_source_id}' \
        "$SNAPSHOT_ID" \
        '${self.input.recovery_name}' \
        '${self.input.namespace_prefix}' \
        '${self.input.binaries_path}'
    EOT
    environment = {
      IBMCLOUD_API_KEY = self.input.api_key # pragma: allowlist secret
      BRS_PG_ID        = self.input.source_pg_id
    }
  }

  depends_on = [terraform_data.wait_for_backup]
}

##############################################################################
# Cross-Cluster Recovery
##############################################################################

resource "terraform_data" "cross_cluster_recovery" {
  count = local.is_full_recovery && var.recovery_type == "cross-cluster" ? 1 : 0

  input = {
    url           = module.protect_cluster.brs_instance_url
    tenant        = module.protect_cluster.brs_tenant_id
    endpoint_type = var.brs_endpoint_type
    instance_id   = module.protect_cluster.brs_instance_guid
    source_pg_id = coalesce(
      try(module.protect_cluster.protection_group_ids[local.recovery_pg_name], null),
      module.protect_cluster.auto_protect_pg_id,
      ""
    )
    target_source_id = split("::", module.target_cluster_registration[0].source_registration_id)[1]
    api_key          = sensitive(var.ibmcloud_api_key)
    recovery_name    = "cross-cluster-recovery-${local.recovery_pg_name}-${formatdate("YYYYMMDD-hhmm", timestamp())}"
    binaries_path    = "/tmp"
    namespace_prefix = var.recovery_namespace_prefix
  }

  provisioner "local-exec" {
    # wait_for_backup_run.sh writes snapshot info to this file before this resource is applied.
    # jq is available in the Schematics environment (used by wait_for_backup_run.sh itself).
    command = <<-EOT
      SNAPSHOT_ID=$(jq -r '.snapshot_id' /tmp/backup_snapshot_${self.input.instance_id}.json)
      ${path.module}/../../scripts/trigger_cross_cluster_recovery.sh \
        '${self.input.url}' \
        '${self.input.tenant}' \
        '${self.input.endpoint_type}' \
        '${self.input.instance_id}' \
        "$BRS_PG_ID" \
        '${self.input.target_source_id}' \
        "$SNAPSHOT_ID" \
        '${self.input.recovery_name}' \
        '${self.input.namespace_prefix}' \
        '${self.input.binaries_path}'
    EOT
    environment = {
      IBMCLOUD_API_KEY = self.input.api_key # pragma: allowlist secret
      BRS_PG_ID        = self.input.source_pg_id
    }
  }

  depends_on = [
    terraform_data.wait_for_backup,
    module.target_cluster_registration,
    time_sleep.wait_for_target_registration
  ]
}

##############################################################################
# Wait for Recovery Completion
##############################################################################

# Poll recovery status and wait for completion before refreshing the protection source
# Recovery operations are asynchronous - this ensures namespaces are fully restored
resource "terraform_data" "wait_for_recovery_completion" {
  count = local.is_full_recovery ? 1 : 0

  input = {
    url                   = module.protect_cluster.brs_instance_url
    tenant                = module.protect_cluster.brs_tenant_id
    endpoint_type         = var.brs_endpoint_type
    instance_id           = module.protect_cluster.brs_instance_guid
    api_key               = sensitive(var.ibmcloud_api_key)
    timeout_minutes       = var.recovery_wait_timeout_minutes
    poll_interval_seconds = var.recovery_poll_interval_seconds
    binaries_path         = "/tmp"
  }

  provisioner "local-exec" {
    command = <<-EOT
      RECOVERY_ID=$(cat /tmp/recovery_id_${self.input.instance_id}.txt)
      ${path.module}/../../scripts/wait_for_recovery_completion.sh \
        '${self.input.url}' \
        '${self.input.tenant}' \
        '${self.input.endpoint_type}' \
        '${self.input.instance_id}' \
        "$RECOVERY_ID" \
        '${self.input.timeout_minutes}' \
        '${self.input.poll_interval_seconds}' \
        '${self.input.binaries_path}'
    EOT
    environment = {
      IBMCLOUD_API_KEY = self.input.api_key # pragma: allowlist secret
    }
  }

  depends_on = [
    terraform_data.same_cluster_recovery,
    terraform_data.cross_cluster_recovery
  ]
}

##############################################################################
# Refresh Protection Source After Recovery
##############################################################################

# Refresh the appropriate cluster after recovery to make recovered namespaces visible in the protection source UI
# - For same-cluster recovery: refresh the source cluster (where recovery happened)
# - For cross-cluster recovery: refresh the target cluster (where recovery happened)
resource "ibm_backup_recovery_protection_source_refresh" "post_recovery_refresh" {
  count = local.is_full_recovery ? 1 : 0

  x_ibm_tenant_id                      = module.protect_cluster.brs_tenant_id
  backup_recovery_protection_source_id = var.recovery_type == "cross-cluster" ? tonumber(split("::", module.target_cluster_registration[0].source_registration_id)[1]) : tonumber(split("::", module.protect_cluster.source_registration_id)[1])
  endpoint_type                        = var.brs_endpoint_type
  instance_id                          = module.protect_cluster.brs_instance_guid
  region                               = local.region

  depends_on = [
    terraform_data.wait_for_recovery_completion
  ]
}
