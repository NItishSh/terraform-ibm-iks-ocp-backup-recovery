# Retrieve information about an existing VPC cluster
resource "time_sleep" "wait_before_cluster_config_download" {
  create_duration = "15m"

  triggers = {
    cluster_id     = var.cluster_id
    endpoint_type  = var.cluster_config_endpoint_type
    resource_group = var.cluster_resource_group_id
  }
}
data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  config_dir        = "${path.module}/kubeconfig"
  endpoint_type     = var.cluster_config_endpoint_type != "default" ? var.cluster_config_endpoint_type : null
  admin             = true

  depends_on = [time_sleep.wait_before_cluster_config_download]
}

module "existing_brs_crn_parser" {
  count   = var.existing_brs_instance_crn != null ? 1 : 0
  source  = "terraform-ibm-modules/common-utilities/ibm//modules/crn-parser"
  version = "1.4.2"
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
  # --- Registration Settings ---
  registration_images = var.registration_images
  enable_auto_protect = var.enable_auto_protect
  # --- Policies ---
  policies = var.policies
  # --- Resource Tags ---
  resource_tags = var.resource_tags
  access_tags   = var.access_tags
}

########################################################################################################################
# Cleanup BRS-agent runtime resources on destroy
# BRS agent creates a namespace and ClusterRoleBinding (brs-backup-agent-<uuid>) that Terraform does not manage.
# This null_resource runs a local-exec on destroy to clean them up.
#
# Cluster credentials (host, CA, cert, key) are stored in triggers at apply time so they are available
# at destroy time without any dependency on kubeconfig files on disk.
# Schematics runs refresh and destroy in separate phases/containers, so file-based kubeconfig approaches
# are unreliable. Storing credentials in triggers is the only reliable approach.
# Note: these values are already present in Terraform state via the data source; Schematics encrypts state.
########################################################################################################################
resource "null_resource" "cleanup_brs_agent_resources" {
  triggers = {
    cluster_id = var.cluster_id
    kube_host  = data.ibm_container_cluster_config.cluster_config.host
    kube_ca    = data.ibm_container_cluster_config.cluster_config.ca_certificate
    kube_cert  = data.ibm_container_cluster_config.cluster_config.admin_certificate
    kube_key   = data.ibm_container_cluster_config.cluster_config.admin_key
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up BRS-agent-created namespaces and cluster role bindings..."

      if ! command -v kubectl >/dev/null 2>&1; then
        echo "kubectl not found; skipping BRS-agent cleanup."
        exit 0
      fi

      # Build a temporary kubeconfig from stored cluster credentials.
      # Use PEM files plus explicit kubectl TLS flags so we do not need inline kubeconfig YAML.
      TMPDIR=$(mktemp -d /tmp/brs-cleanup-XXXXXX)
      trap 'rm -rf "$TMPDIR"' EXIT

      printf '%s\n' "${self.triggers.kube_ca}" > "$TMPDIR/ca.pem"
      printf '%s\n' "${self.triggers.kube_cert}" > "$TMPDIR/client.crt"
      printf '%s\n' "${self.triggers.kube_key}" > "$TMPDIR/client.key"

      kctl() {
        kubectl \
          --server="${self.triggers.kube_host}" \
          --certificate-authority="$TMPDIR/ca.pem" \
          --client-certificate="$TMPDIR/client.crt" \
          --client-key="$TMPDIR/client.key" \
          "$@"
      }

      if ! kctl version --request-timeout=15s >/dev/null 2>&1; then
        echo "kubectl cannot reach the target cluster; skipping BRS-agent cleanup."
        exit 0
      fi

      # Delete by runtime-generated naming pattern.
      kctl get namespace --no-headers | awk '{print $1}' | grep -E '^brs-backup-agent-' | while read -r ns; do
        [ -n "$ns" ] && kctl delete namespace "$ns" --ignore-not-found=true
      done

      kctl get clusterrolebinding --no-headers | awk '{print $1}' | grep -E '^brs-backup-agent-' | while read -r crb; do
        [ -n "$crb" ] && kctl delete clusterrolebinding "$crb" --ignore-not-found=true
      done

      echo "Cleanup complete."
    EOT
  }

  depends_on = [
    module.protect_cluster
  ]
}
