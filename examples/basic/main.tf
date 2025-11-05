module "backup_recovery" {
  source = "../.."

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