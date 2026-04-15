# Cloud automation for OpenShift workloads Backup Recovery (Fully configurable)

:exclamation: **Important:** This solution is not intended to be called by other modules because it contains a provider configuration and is not compatible with the `for_each`, `count`, and `depends_on` arguments. For more information, see [Providers Within Modules](https://developer.hashicorp.com/terraform/language/modules/develop/providers).

## Overview

This Deployable Architecture (DA) solution provides a fully configurable implementation of IBM Backup Recovery Service for OpenShift and Kubernetes workloads. It supports:

- **Backup Protection**: Automated backup of cluster resources via Protection Groups
- **Data Source Connector**: Deployment of backup agents in your clusters
- **Recovery Operations**: Full, selective, and cross-region recovery capabilities
- **Flexible Configuration**: Comprehensive variable support for all backup and recovery scenarios

## Features

### Backup Capabilities

- Create multiple protection groups with custom policies
- Support for namespace-based and label-based resource selection
- Configurable backup schedules and retention policies
- Automatic snapshot management

### Recovery Capabilities

- **Full Recovery**: Restore all resources from a protection group
- **Selective Recovery**: Restore specific namespaces or resources
- **Cross-Region Recovery**: Restore to a different cluster/region
- Automatic snapshot ID retrieval for easy recovery operations
- Namespace and storage class mapping for cross-region scenarios

## Usage

### Basic Backup Setup

```hcl
module "backup_recovery" {
  source = "terraform-ibm-modules/iks-ocp-backup-recovery/ibm//solutions/fully-configurable"

  ibmcloud_api_key                = var.ibmcloud_api_key
  resource_group_id               = var.resource_group_id
  region                          = var.region
  brs_instance_name               = "my-backup-instance"
  cluster_id                      = var.cluster_id

  protection_groups = {
    "production-apps" = {
      policy_id = "policy-123"
      objects = [{
        namespaces = ["prod-app1", "prod-app2"]
      }]
    }
  }
}
```

### Recovery Operations

The solution outputs snapshot IDs automatically, making recovery operations straightforward:

```hcl
# Use the latest_snapshot_ids output for recovery
recoveries = {
  "restore-production" = {
    protection_group_name = "production-apps"
    snapshot_id          = module.backup_recovery.latest_snapshot_ids["production-apps"]
    recovery_type        = "full"
  }
}
```

### Recovery Examples

#### 1. Full Recovery (Same Cluster)

Restore all resources from a protection group to the same cluster:

```hcl
recoveries = {
  "full-restore" = {
    protection_group_name = "production-apps"
    snapshot_id          = module.backup_recovery.latest_snapshot_ids["production-apps"]
    recovery_type        = "full"
  }
}
```

#### 2. Selective Recovery (Specific Namespaces)

Restore only specific namespaces:

```hcl
recoveries = {
  "selective-restore" = {
    protection_group_name = "production-apps"
    snapshot_id          = module.backup_recovery.latest_snapshot_ids["production-apps"]
    recovery_type        = "selective"
    namespaces           = ["prod-app1"]
  }
}
```

#### 3. Cross-Region Recovery

Restore to a different cluster in another region:

```hcl
recoveries = {
  "cross-region-restore" = {
    protection_group_name    = "production-apps"
    snapshot_id             = module.backup_recovery.latest_snapshot_ids["production-apps"]
    recovery_type           = "cross_region"
    target_cluster_id       = "target-cluster-id"
    target_brs_instance_id  = "target-brs-instance-id"
    namespace_mapping = {
      "prod-app1" = "dr-app1"
    }
  }
}
```

## Variables

### Required Variables

| Name                | Description           | Type     |
| ------------------- | --------------------- | -------- |
| `ibmcloud_api_key`  | IBM Cloud API key     | `string` |
| `resource_group_id` | Resource group ID     | `string` |
| `region`            | IBM Cloud region      | `string` |
| `cluster_id`        | Cluster ID to protect | `string` |

### Protection Groups

Configure protection groups using the `protection_groups` variable:

```hcl
protection_groups = {
  "group-name" = {
    policy_id = "policy-id"
    objects = [{
      namespaces = ["namespace1", "namespace2"]
      # OR
      label_selector = {
        match_labels = {
          "app" = "myapp"
        }
      }
    }]
  }
}
```

### Recovery Configuration

Configure recovery operations using the `recoveries` variable:

```hcl
recoveries = {
  "recovery-name" = {
    protection_group_name = "group-name"
    snapshot_id          = "snapshot-id"  # Use module outputs
    recovery_type        = "full"         # full, selective, or cross_region

    # For selective recovery
    namespaces = ["namespace1"]

    # For cross-region recovery
    target_cluster_id      = "target-cluster-id"
    target_brs_instance_id = "target-brs-instance-id"
    namespace_mapping = {
      "source-ns" = "target-ns"
    }
  }
}
```

## Outputs

| Name                   | Description                                  |
| ---------------------- | -------------------------------------------- |
| `brs_instance_id`      | ID of the Backup Recovery Service instance   |
| `protection_group_ids` | Map of protection group names to IDs         |
| `latest_snapshot_ids`  | Latest snapshot ID for each protection group |
| `available_snapshots`  | All available snapshots with details         |
| `recovery_ids`         | Map of recovery operation names to IDs       |

## Recovery Workflow

1. **Setup Protection**: Configure protection groups to backup your workloads
2. **Monitor Snapshots**: Use `latest_snapshot_ids` output to see available backups
3. **Plan Recovery**: Determine recovery type (full, selective, or cross-region)
4. **Execute Recovery**: Add recovery configuration and apply
5. **Verify**: Check recovered resources in target cluster

## Important Notes

- Recovery operations are **manual** - you must explicitly configure them
- Snapshot IDs are automatically fetched via data sources
- Cross-region recovery uses the same snapshot IDs (BRS replicates data)
- Always test recovery procedures in non-production environments first
- Recovery to the same cluster will overwrite existing resources

## Support

For issues and questions:

- GitHub Issues: [terraform-ibm-iks-ocp-backup-recovery](https://github.com/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery/issues)
- IBM Cloud Docs: [Backup Recovery Service](https://cloud.ibm.com/docs/backup-recovery)
