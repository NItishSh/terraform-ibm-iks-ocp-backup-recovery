##############################################################################
# Cross-Cluster Backup and Recovery Example
#
# This example demonstrates:
# 1. Single shared BRS instance for both source and target clusters
# 2. Backup from source cluster
# 3. Automatic recovery to target cluster in one terraform apply
# 4. Both same-cluster and cross-cluster recovery modes
##############################################################################

locals {
  source_cluster_id = var.source_cluster_name_id != null ? var.source_cluster_name_id : ibm_container_vpc_cluster.source_cluster[0].id
  target_cluster_id = var.target_cluster_name_id != null ? var.target_cluster_name_id : ibm_container_vpc_cluster.target_cluster[0].id
}

##############################################################################
# Resource Group
##############################################################################

module "resource_group" {
  source                       = "terraform-ibm-modules/resource-group/ibm"
  version                      = "1.6.0"
  resource_group_name          = var.resource_group == null ? "${var.prefix}-resource-group" : null
  existing_resource_group_name = var.resource_group
}

##############################################################################
# VPC Infrastructure for Source Cluster
##############################################################################

resource "ibm_is_vpc" "source_vpc" {
  count                     = var.source_cluster_name_id == null ? 1 : 0
  name                      = "${var.prefix}-source-vpc"
  resource_group            = module.resource_group.resource_group_id
  address_prefix_management = "auto"
  tags                      = var.resource_tags
}

resource "ibm_is_public_gateway" "source_gateway" {
  count          = var.source_cluster_name_id == null ? 1 : 0
  name           = "${var.prefix}-source-gateway"
  vpc            = ibm_is_vpc.source_vpc[0].id
  resource_group = module.resource_group.resource_group_id
  zone           = "${var.region}-1"
}

resource "ibm_is_subnet" "source_subnet" {
  count                    = var.source_cluster_name_id == null ? 1 : 0
  name                     = "${var.prefix}-source-subnet"
  vpc                      = ibm_is_vpc.source_vpc[0].id
  resource_group           = module.resource_group.resource_group_id
  zone                     = "${var.region}-1"
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.source_gateway[0].id
}

##############################################################################
# VPC Infrastructure for Target Cluster
##############################################################################

resource "ibm_is_vpc" "target_vpc" {
  count                     = var.target_cluster_name_id == null ? 1 : 0
  name                      = "${var.prefix}-target-vpc"
  resource_group            = module.resource_group.resource_group_id
  address_prefix_management = "auto"
  tags                      = var.resource_tags
}

resource "ibm_is_public_gateway" "target_gateway" {
  count          = var.target_cluster_name_id == null ? 1 : 0
  name           = "${var.prefix}-target-gateway"
  vpc            = ibm_is_vpc.target_vpc[0].id
  resource_group = module.resource_group.resource_group_id
  zone           = "${var.region}-1"
}

resource "ibm_is_subnet" "target_subnet" {
  count                    = var.target_cluster_name_id == null ? 1 : 0
  name                     = "${var.prefix}-target-subnet"
  vpc                      = ibm_is_vpc.target_vpc[0].id
  resource_group           = module.resource_group.resource_group_id
  zone                     = "${var.region}-1"
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.target_gateway[0].id
}

##############################################################################
# Source Kubernetes Cluster
##############################################################################

resource "ibm_container_vpc_cluster" "source_cluster" {
  count                = var.source_cluster_name_id == null ? 1 : 0
  name                 = "${var.prefix}-source-cluster"
  vpc_id               = ibm_is_vpc.source_vpc[0].id
  flavor               = "bx2.4x16"
  force_delete_storage = true
  resource_group_id    = module.resource_group.resource_group_id
  worker_count         = 2
  zones {
    subnet_id = ibm_is_subnet.source_subnet[0].id
    name      = "${var.region}-1"
  }
  disable_outbound_traffic_protection = true
  tags                                = var.resource_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

data "ibm_container_cluster_config" "source_cluster_config" {
  cluster_name_id   = local.source_cluster_id
  resource_group_id = module.resource_group.resource_group_id
  admin             = true
}

##############################################################################
# Target Kubernetes Cluster
##############################################################################

resource "ibm_container_vpc_cluster" "target_cluster" {
  count                = var.target_cluster_name_id == null ? 1 : 0
  name                 = "${var.prefix}-target-cluster"
  vpc_id               = ibm_is_vpc.target_vpc[0].id
  flavor               = "bx2.4x16"
  force_delete_storage = true
  resource_group_id    = module.resource_group.resource_group_id
  worker_count         = 2
  zones {
    subnet_id = ibm_is_subnet.target_subnet[0].id
    name      = "${var.region}-1"
  }
  disable_outbound_traffic_protection = true
  tags                                = var.resource_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

data "ibm_container_cluster_config" "target_cluster_config" {
  cluster_name_id   = local.target_cluster_id
  resource_group_id = module.resource_group.resource_group_id
  admin             = true
}

# Sleep to allow RBAC sync on clusters
resource "time_sleep" "wait_clusters" {
  depends_on = [
    data.ibm_container_cluster_config.source_cluster_config,
    data.ibm_container_cluster_config.target_cluster_config
  ]
  create_duration = "60s"
}

##############################################################################
# Test Workload Namespace (Source Cluster)
##############################################################################

# Create namespace using null_resource with kubectl
# This avoids Kubernetes provider initialization timing issues with aliased providers
resource "null_resource" "create_source_namespace" {
  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG="${data.ibm_container_cluster_config.source_cluster_config.config_file_path}"
      kubectl create namespace ${var.prefix}-source-app --dry-run=client -o yaml | kubectl apply -f -
      kubectl label namespace ${var.prefix}-source-app backup-enabled=true environment=production --overwrite
      # Wait for namespace to be fully ready
      kubectl wait --for=jsonpath='{.status.phase}'=Active --timeout=60s namespace/${var.prefix}-source-app
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      export KUBECONFIG="${self.triggers.kubeconfig}"
      kubectl delete namespace ${self.triggers.namespace} --ignore-not-found=true || true
    EOT
  }

  triggers = {
    namespace  = "${var.prefix}-source-app"
    kubeconfig = data.ibm_container_cluster_config.source_cluster_config.config_file_path
  }

  depends_on = [time_sleep.wait_clusters]
}

locals {
  source_namespace = "${var.prefix}-source-app"
}

# StatefulSet with volumeClaimTemplates for BRS-compatible recovery
# StatefulSets automatically create unique PVCs per pod, avoiding PV binding conflicts during restore
resource "kubernetes_stateful_set_v1" "source_app" {
  #checkov:skip=CKV_K8S_8:Test workload - liveness probe not required
  #checkov:skip=CKV_K8S_9:Test workload - readiness probe not required
  #checkov:skip=CKV_K8S_28:Test workload - NET_RAW capability not dropped
  #checkov:skip=CKV_K8S_29:Test workload - security context not applied
  #checkov:skip=CKV_K8S_30:Test workload - container security context not applied
  #checkov:skip=CKV_K8S_14:Test workload - using latest tag for simplicity
  #checkov:skip=CKV_K8S_43:Test workload - image digest not used
  provider = kubernetes.source

  metadata {
    name      = "sample-app-with-data"
    namespace = local.source_namespace
  }

  depends_on = [
    null_resource.create_source_namespace
  ]

  spec {
    replicas     = 1
    service_name = "sample-app"

    selector {
      match_labels = {
        app = "sample-app-with-data"
      }
    }

    # volumeClaimTemplates - Each pod gets its own PVC automatically
    # This is required for BRS recovery to work properly
    # Using DELETE reclaim policy (without -retain) to allow BRS to create new PVs during restore
    volume_claim_template {
      metadata {
        name = "data-storage"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "ibmc-vpc-block-metro-5iops-tier"
        resources {
          requests = {
            storage = "10Gi"
          }
        }
      }
    }

    template {
      metadata {
        labels = {
          app = "sample-app-with-data"
        }
      }
      spec {
        # Init container writes data once, then exits
        init_container {
          name    = "data-writer"
          image   = "icr.io/ext/cohesity/busybox:latest"
          command = ["sh", "-c"]
          args = [
            <<-EOT
              echo 'Starting data generation for cross-cluster backup test...'
              # Create a test file with data in the PVC
              dd if=/dev/urandom of=/data/testfile.dat bs=1M count=100
              echo 'Data generation complete. File created at /data/testfile.dat'
              echo "Backup test data - Timestamp: $(date)" > /data/backup-info.txt
              echo 'Init container complete'
            EOT
          ]
          volume_mount {
            name       = "data-storage"
            mount_path = "/data"
          }
        }

        # Main container keeps pod alive
        container {
          name    = "app"
          image   = "icr.io/ext/cohesity/busybox:latest"
          command = ["sh", "-c", "echo 'App running'; sleep infinity"]
          volume_mount {
            name       = "data-storage"
            mount_path = "/data"
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}

# Wait for workload to be ready before proceeding with backup
resource "terraform_data" "wait_for_source_workload" {
  triggers_replace = {
    namespace   = local.source_namespace
    statefulset = kubernetes_stateful_set_v1.source_app.metadata[0].name
    kubeconfig  = data.ibm_container_cluster_config.source_cluster_config.config_file_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG="${self.triggers_replace.kubeconfig}"
      echo "Waiting for StatefulSet ${self.triggers_replace.statefulset} in namespace ${self.triggers_replace.namespace}..."
      kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 --timeout=300s \
        statefulset/${self.triggers_replace.statefulset} \
        -n ${self.triggers_replace.namespace}
      echo "StatefulSet is ready!"
    EOT
  }

  depends_on = [
    kubernetes_stateful_set_v1.source_app,
    null_resource.create_source_namespace
  ]
}

##############################################################################
# Source Cluster: Backup & Recovery with DSC
##############################################################################

module "source_backup_recovery" {
  source = "../.."
  providers = {
    helm       = helm.source
    kubernetes = kubernetes.source
  }

  cluster_id                   = local.source_cluster_id
  cluster_resource_group_id    = module.resource_group.resource_group_id
  cluster_config_endpoint_type = "private"
  add_dsc_rules_to_cluster_sg  = false
  kube_type                    = "kubernetes"
  ibmcloud_api_key             = var.ibmcloud_api_key
  enable_auto_protect          = false

  # BRS instance: create new or use existing
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_endpoint_type         = "public"
  brs_instance_name         = "${var.prefix}-brs-instance"
  brs_connection_name       = "${var.prefix}-source-connection"
  brs_create_new_connection = true
  region                    = var.region
  connection_env_type       = "kIksVpc"

  # Backup policy - 240-minute backup schedule
  policies = [{
    name              = "${var.prefix}-continuous-backup"
    create_new_policy = true
    schedule = {
      unit = "Minutes"
      minute_schedule = {
        frequency = 240 # Backup every 240 minutes
      }
    }
    retention = {
      unit     = "Days"
      duration = 7
    }
  }]

  # Protection group for source cluster
  protection_groups = [{
    name        = "${var.prefix}-source-pg"
    policy_name = "${var.prefix}-continuous-backup"
    description = "Backup source cluster workloads with continuous schedule"
    priority    = "kHigh"

    # Kubernetes-specific backup features
    enable_indexing       = true  # Enable search/indexing of backed up data
    leverage_csi_snapshot = true  # Use CSI snapshots for faster backups
    non_snapshot_backup   = false # Use snapshot-based backups
    volume_backup_failure = false # Don't fail entire backup if volume fails

    objects = [{
      name = local.source_namespace

      # Backup configuration
      backup_only_pvc             = false # Backup entire namespace, not just PVCs
      fail_backup_on_hook_failure = false # Continue backup even if hooks fail

      # No exclusions needed - deployment-based workload is safe to restore
      exclude_params = null
      include_params = null
    }]
  }]

  # Disable recovery in source module - will be handled separately
  enable_recovery                  = false
  recovery_mode                    = var.recovery_mode
  target_cluster_id                = local.target_cluster_id
  target_cluster_resource_group_id = module.resource_group.resource_group_id
  wait_for_backup_completion       = var.wait_for_backup_completion
  recoveries                       = []

  resource_tags = var.resource_tags
  access_tags   = var.access_tags

  depends_on = [
    time_sleep.wait_clusters,
    terraform_data.wait_for_source_workload # Wait for deployment to be ready before backup
  ]
}

##############################################################################
# Target Cluster: Backup & Recovery with DSC (Reuses Same BRS Instance)
##############################################################################

module "target_backup_recovery" {
  source = "../.."
  providers = {
    helm       = helm.target
    kubernetes = kubernetes.target
  }

  cluster_id                   = local.target_cluster_id
  cluster_resource_group_id    = module.resource_group.resource_group_id
  cluster_config_endpoint_type = "private"
  add_dsc_rules_to_cluster_sg  = false
  kube_type                    = "kubernetes"
  ibmcloud_api_key             = var.ibmcloud_api_key
  enable_auto_protect          = false

  # Use the same BRS instance CRN from variable (not module output)
  # This ensures the value is known at plan time, avoiding count/for_each errors
  existing_brs_instance_crn = var.existing_brs_instance_crn != null ? var.existing_brs_instance_crn : module.source_backup_recovery.brs_instance_crn
  brs_endpoint_type         = "public"
  brs_connection_name       = "${var.prefix}-target-connection"
  brs_create_new_connection = true
  region                    = var.region
  connection_env_type       = "kIksVpc"

  # Target cluster: NO protection groups (recovery destination only)
  # It will use policies from the source cluster's BRS instance
  policies          = []
  protection_groups = []

  # No recovery operations on target cluster
  enable_recovery = false
  recoveries      = []

  resource_tags = var.resource_tags
  access_tags   = var.access_tags

  depends_on = [
    time_sleep.wait_clusters
  ]
}

##############################################################################
# Cross-Cluster Recovery (After Both Clusters Are Registered)
##############################################################################

# Wait for target cluster registration to complete
resource "time_sleep" "wait_for_target_registration" {
  count = var.enable_recovery ? 1 : 0

  depends_on = [
    module.target_backup_recovery
  ]

  create_duration = "30s" # Allow time for target registration to propagate
}

# Poll for backup completion before attempting recovery
# This is separate from the main module's polling to avoid dependency issues
resource "terraform_data" "wait_for_source_backup" {
  count = var.enable_recovery ? 1 : 0

  depends_on = [
    module.source_backup_recovery,
    time_sleep.wait_for_target_registration
  ]

  input = {
    url                   = "https://${module.source_backup_recovery.brs_instance_guid}.${var.region}.backup-recovery.cloud.ibm.com"
    tenant                = module.source_backup_recovery.brs_tenant_id
    endpoint_type         = "public"
    instance_id           = module.source_backup_recovery.brs_instance_guid
    protection_group_id   = module.source_backup_recovery.protection_group_ids["${var.prefix}-source-pg"]
    api_key               = sensitive(var.ibmcloud_api_key)
    timeout_minutes       = 45
    poll_interval_seconds = 30
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

  filename = "/tmp/backup_snapshot_${module.source_backup_recovery.brs_instance_guid}.json"

  depends_on = [terraform_data.wait_for_source_backup]
}

locals {
  snapshot_data = var.enable_recovery ? jsondecode(data.local_file.snapshot_info[0].content) : null
}

# Cross-cluster recovery using BRS API directly
# The Terraform provider doesn't yet support specifying target cluster for recovery
# This uses the working script with correct API payload structure
resource "terraform_data" "cross_cluster_recovery" {
  count = var.enable_recovery ? 1 : 0

  input = {
    url              = "https://${module.source_backup_recovery.brs_instance_guid}.${var.region}.backup-recovery.cloud.ibm.com"
    tenant           = module.source_backup_recovery.brs_tenant_id
    endpoint_type    = "public"
    instance_id      = module.source_backup_recovery.brs_instance_guid
    source_pg_id     = split("::", module.source_backup_recovery.protection_group_ids["${var.prefix}-source-pg"])[1]
    target_source_id = split("::", module.target_backup_recovery.source_registration_id)[1]
    snapshot_id      = local.snapshot_data.snapshot_id
    api_key          = sensitive(var.ibmcloud_api_key)
    recovery_name    = "${var.prefix}-restore-to-target"
    namespace_prefix = "restored-"
    binaries_path    = "/tmp"
  }

  provisioner "local-exec" {
    command     = <<-EOT
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
    interpreter = ["/bin/bash", "-c"]
    environment = {
      IBMCLOUD_API_KEY = self.input.api_key # pragma: allowlist secret
    }
  }

  depends_on = [
    module.source_backup_recovery,
    module.target_backup_recovery,
    terraform_data.wait_for_source_backup
  ]
}
