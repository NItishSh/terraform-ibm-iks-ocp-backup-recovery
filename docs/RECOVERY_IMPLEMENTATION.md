# Recovery Implementation Guide

## Overview

This document describes the recovery functionality implementation for the IBM Backup & Recovery for IKS/ROKS module. The implementation enables **single-shot execution** where backup and recovery run in one continuous `terraform apply` with no manual intervention.

## Critical Design Principle: Single BRS Instance

**The module uses ONE Backup & Recovery Service (BRS) instance for all operations**, regardless of recovery mode:

- **Same-cluster recovery**: One BRS instance handles backup + recovery within that cluster
- **Cross-cluster recovery**: The **same single BRS instance** is reused for both source and target clusters
- **No second BRS instance is ever created** - even in cross-cluster mode

### How Cross-Cluster Recovery Works

```
┌─────────────────────────────────────────────────────────────┐
│              Single Shared BRS Instance                      │
│  - Manages all backup and recovery operations               │
│  - Has multiple source registrations (one per cluster)      │
└─────────────────────────────────────────────────────────────┘
                    │                    │
                    │                    │
        ┌───────────▼──────────┐    ┌───▼──────────────┐
        │  Source Cluster      │    │  Target Cluster  │
        │  Registration A      │    │  Registration B  │
        │  - DSC Installed     │    │  - DSC Installed │
        │  - Backup Source     │    │  - Recovery Dest │
        └──────────────────────┘    └──────────────────┘
```

**Key Points:**

1. One BRS instance can have **multiple source registrations** (one per cluster)
2. Each cluster gets its own DSC deployment and registration
3. Recovery operations reference **source registration IDs**, not separate BRS instances
4. Cross-cluster recovery = backup from registration A, restore to registration B, **same BRS instance**

### Implementation in Code

The module uses `existing_brs_instance_crn` to share the BRS instance:

```hcl
# Source cluster module
module "source_backup_recovery" {
  source = "terraform-ibm-modules/iks-ocp-backup-recovery/ibm"

  # Creates BRS instance (or uses existing)
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_instance_name         = "shared-brs-instance"
  brs_connection_name       = "source-connection"
  # ... backup configuration ...
}

# Target cluster module (reuses same BRS instance)
module "target_backup_recovery" {
  source = "terraform-ibm-modules/iks-ocp-backup-recovery/ibm"

  # CRITICAL: Reuse the BRS instance from source
  existing_brs_instance_crn = module.source_backup_recovery.brs_instance_crn
  brs_connection_name       = "target-connection"
  # ... no backup configuration needed ...
}
```

## Architecture

### Single-Shot Execution Flow

```
terraform apply
    ↓
1. Create Protection Groups
    ↓
2. Wait for Backup Completion (configurable wait time)
    ↓
3. Query Backup Runs (snapshot discovery)
    ↓
4. Trigger Recovery (automatic, using latest snapshots)
    ↓
5. Complete (backup + recovery done)
```

### Key Components

#### 1. **Protection Groups** (`ibm_backup_recovery_protection_group`)

- Define what to backup (namespaces, resources)
- Trigger automatic backups based on policy schedule
- Located in [`main.tf:479-775`](main.tf:479-775)

#### 2. **Wait for Backup Completion** (`time_sleep.wait_for_backup_completion`)

- Configurable wait period for initial backup to complete
- Default: 30 minutes (adjustable via `wait_for_backup_completion`)
- Only created when `enable_recovery = true`
- Located in [`main.tf:830-845`](main.tf:830-845)

#### 3. **Snapshot Discovery** (`data.ibm_backup_recovery_protection_group_runs`)

- Queries completed backup runs after wait period
- Discovers available snapshots for recovery
- Provides latest snapshot IDs automatically
- Located in [`main.tf:847-865`](main.tf:847-865)

#### 4. **Recovery Resource** (`ibm_backup_recovery.recover_snapshot`)

- Executes recovery operations using discovered snapshots
- Supports same-cluster and cross-cluster recovery
- Only created when `enable_recovery = true`
- Located in [`main.tf:907-965`](main.tf:907-965)

## Configuration Variables

### Core Recovery Variables

| Variable                     | Type         | Default          | Description                                         |
| ---------------------------- | ------------ | ---------------- | --------------------------------------------------- |
| `enable_recovery`            | bool         | `false`          | Enable automatic recovery after backup completion   |
| `recovery_mode`              | string       | `"same-cluster"` | Recovery mode: `same-cluster` or `cross-cluster`    |
| `wait_for_backup_completion` | number       | `30`             | Wait time in minutes for initial backup to complete |
| `recoveries`                 | list(object) | `[]`             | List of recovery operations to perform              |

### Cross-Cluster Variables

| Variable                           | Type   | Default | Description                                                                    |
| ---------------------------------- | ------ | ------- | ------------------------------------------------------------------------------ |
| `target_cluster_id`                | string | `null`  | Target cluster ID for cross-cluster recovery (required for cross-cluster mode) |
| `target_cluster_resource_group_id` | string | `null`  | Target cluster resource group ID (required for cross-cluster mode)             |

## Usage Examples

### Example 1: Same-Cluster Recovery (Basic)

```hcl
module "backup_recovery" {
  source  = "terraform-ibm-modules/iks-ocp-backup-recovery/ibm"
  version = "X.Y.Z"

  cluster_id                    = "my-cluster"
  cluster_resource_group_id     = "xxxx"
  ibmcloud_api_key              = var.ibmcloud_api_key # pragma: allowlist secret
  region                        = "us-south"
  brs_instance_name             = "my-brs-instance"
  brs_connection_name           = "my-connection"

  # Backup configuration
  policies = [{
    name              = "daily-backup"
    create_new_policy = true
    schedule = {
      unit      = "Days"
      frequency = 1
    }
    retention = {
      duration = 7
      unit     = "Days"
    }
  }]

  protection_groups = [{
    name        = "production-backup"
    policy_name = "daily-backup"
    objects     = [{ name = "production-namespace" }]
  }]

  # Recovery configuration (single-shot execution)
  enable_recovery            = true
  recovery_mode              = "same-cluster"
  wait_for_backup_completion = 30

  recoveries = [{
    name                 = "restore-production"
    snapshot_environment = "kKubernetes"
    kubernetes_params = {
      recovery_action = "RecoverNamespaces"
      objects = [{
        protection_group_name = "production-backup"
        snapshot_id           = "latest"
      }]
    }
  }]
}
```

### Example 2: Cross-Cluster Recovery

```hcl
module "backup_recovery" {
  source  = "terraform-ibm-modules/iks-ocp-backup-recovery/ibm"
  version = "X.Y.Z"

  # Source cluster configuration
  cluster_id                = "source-cluster"
  cluster_resource_group_id = "source-rg-id"
  ibmcloud_api_key          = var.ibmcloud_api_key  # pragma: allowlist secret
  region                    = "us-south"
  brs_instance_name         = "shared-brs-instance"
  brs_connection_name       = "source-connection"

  # Backup configuration
  policies = [{
    name              = "daily-backup"
    create_new_policy = true
    schedule = {
      unit      = "Days"
      frequency = 1
    }
    retention = {
      duration = 7
      unit     = "Days"
    }
  }]

  protection_groups = [{
    name        = "app-backup"
    policy_name = "daily-backup"
    objects     = [{ name = "app-namespace" }]
  }]

  # Cross-cluster recovery configuration
  enable_recovery                    = true
  recovery_mode                      = "cross-cluster"
  target_cluster_id                  = "target-cluster"
  target_cluster_resource_group_id   = "target-rg-id"
  wait_for_backup_completion         = 45

  recoveries = [{
    name                 = "restore-to-target"
    snapshot_environment = "kKubernetes"
    kubernetes_params = {
      recovery_action = "RecoverNamespaces"
      objects = [{
        protection_group_name = "app-backup"
        snapshot_id           = "latest"
      }]
    }
  }]
}
```

### Example 3: Multiple Recovery Operations

```hcl
module "backup_recovery" {
  source  = "terraform-ibm-modules/iks-ocp-backup-recovery/ibm"
  version = "X.Y.Z"

  # ... cluster and BRS configuration ...

  protection_groups = [
    {
      name        = "frontend-backup"
      policy_name = "daily-backup"
      objects     = [{ name = "frontend-namespace" }]
    },
    {
      name        = "backend-backup"
      policy_name = "daily-backup"
      objects     = [{ name = "backend-namespace" }]
    }
  ]

  enable_recovery            = true
  recovery_mode              = "same-cluster"
  wait_for_backup_completion = 30

  # Multiple recovery operations
  recoveries = [
    {
      name                 = "restore-frontend"
      snapshot_environment = "kKubernetes"
      kubernetes_params = {
        recovery_action = "RecoverNamespaces"
        objects = [{
          protection_group_name = "frontend-backup"
          snapshot_id           = "latest"
        }]
      }
    },
    {
      name                 = "restore-backend"
      snapshot_environment = "kKubernetes"
      kubernetes_params = {
        recovery_action = "RecoverNamespaces"
        objects = [{
          protection_group_name = "backend-backup"
          snapshot_id           = "latest"
        }]
      }
    }
  ]
}
```

## Chaining Mechanism

### Dependency Chain

The implementation uses Terraform's `depends_on` and data source refresh to create a dependency chain:

```hcl
Protection Groups
    ↓ (depends_on)
time_sleep.wait_for_backup_completion
    ↓ (depends_on)
data.ibm_backup_recovery_protection_group_runs
    ↓ (depends_on)
ibm_backup_recovery.recover_snapshot
```

### How It Works

1. **Protection Groups Created**: Terraform creates protection groups, which trigger automatic backups based on the policy schedule.

2. **Wait Period**: `time_sleep` resource waits for the configured duration (default 30 minutes) to allow the initial backup to complete.

3. **Snapshot Discovery**: After the wait period, the data source queries the BRS API to discover completed backup runs and extract snapshot IDs.

4. **Recovery Execution**: The recovery resource uses the discovered snapshot IDs to restore the backup. The `depends_on` ensures recovery only starts after snapshots are available.

5. **Error Handling**: Lifecycle preconditions validate that snapshots exist before attempting recovery.

## Resource References

### IBM Terraform Provider Resources Used

1. **[`ibm_backup_recovery_protection_group`](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery_protection_group)**
   - Creates protection groups for backup
   - Triggers automatic backups based on policy

2. **[`ibm_backup_recovery_protection_group_runs`](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/data-sources/backup_recovery_protection_group_runs)** (Data Source)
   - Queries completed backup runs
   - Provides snapshot IDs for recovery

3. **[`ibm_backup_recovery`](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/resources/backup_recovery)**
   - Executes recovery operations
   - Restores backups to same or different cluster

4. **[`time_sleep`](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep)**
   - Provides configurable wait period
   - Ensures backups complete before recovery

## Error Handling

### Precondition Checks

The implementation includes several precondition checks to prevent errors:

#### 1. Snapshot Availability Check

```hcl
lifecycle {
  precondition {
    condition     = !var.enable_recovery || length(local.latest_snapshots) > 0
    error_message = <<-EOT
      No backup snapshots found. Recovery cannot proceed without completed backups.
      Either:
      1. Increase wait_for_backup_completion to allow more time for backups to complete
      2. Ensure protection groups have run at least one successful backup
      3. Set enable_recovery = false to skip automatic recovery
    EOT
  }
}
```

#### 2. Cross-Cluster Configuration Check

```hcl
lifecycle {
  precondition {
    condition = (
      var.recovery_mode == "same-cluster" ||
      (var.recovery_mode == "cross-cluster" && var.target_cluster_id != null && var.target_cluster_resource_group_id != null)
    )
    error_message = "For cross-cluster recovery, both target_cluster_id and target_cluster_resource_group_id must be provided."
  }
}
```

### Common Issues and Solutions

#### Issue 1: No Snapshots Found

**Error:**

```
No backup snapshots found. Recovery cannot proceed without completed backups.
```

**Solutions:**

1. Increase `wait_for_backup_completion` to allow more time for backups
2. Verify protection group policy schedule is configured correctly
3. Check BRS instance logs for backup failures
4. Ensure Data Source Connector is running properly

#### Issue 2: Cross-Cluster Configuration Missing

**Error:**

```
For cross-cluster recovery, both target_cluster_id and target_cluster_resource_group_id must be provided.
```

**Solution:**
Provide both required variables:

```hcl
recovery_mode                      = "cross-cluster"
target_cluster_id                  = "target-cluster-id"
target_cluster_resource_group_id   = "target-rg-id"
```

#### Issue 3: Target Cluster Not Registered

**Error:**

```
Target cluster not found in protection sources
```

**Solution:**
Ensure the target cluster is registered with the BRS instance:

1. Deploy the module to the target cluster first
2. Verify target cluster appears in BRS protection sources
3. Then configure cross-cluster recovery from source cluster

## Outputs

The module provides several outputs for monitoring recovery operations:

| Output                | Description                                                 |
| --------------------- | ----------------------------------------------------------- |
| `recovery_ids`        | Map of recovery operation names to their IDs                |
| `recovery_status`     | Map of recovery operation names to their status information |
| `latest_snapshots`    | Map of protection group names to their latest snapshot IDs  |
| `recovery_mode`       | Current recovery mode (same-cluster or cross-cluster)       |
| `target_cluster_id`   | Target cluster ID for recovery operations                   |
| `backup_runs_summary` | Summary of backup runs per protection group                 |

### Example Output Usage

```hcl
output "recovery_info" {
  value = {
    mode              = module.backup_recovery.recovery_mode
    target_cluster    = module.backup_recovery.target_cluster_id
    latest_snapshots  = module.backup_recovery.latest_snapshots
    recovery_status   = module.backup_recovery.recovery_status
  }
}
```

## Best Practices

### 1. Wait Time Configuration

- **Small clusters (<10 namespaces)**: 15-30 minutes
- **Medium clusters (10-50 namespaces)**: 30-60 minutes
- **Large clusters (>50 namespaces)**: 60-120 minutes
- **Cross-cluster recovery**: Add 15-30 minutes to account for network transfer

### 2. Recovery Mode Selection

**Use Same-Cluster Recovery When:**

- Testing backup/restore functionality
- Recovering from accidental deletions
- Restoring to a previous state in the same environment

**Use Cross-Cluster Recovery When:**

- Disaster recovery scenarios
- Migrating workloads between clusters
- Creating test environments from production backups
- Geographic failover requirements

### 3. Snapshot Management

- Use `snapshot_id = "latest"` for automatic recovery with the most recent backup
- Specify explicit snapshot IDs for point-in-time recovery
- Monitor `backup_runs_summary` output to track backup completion

### 4. Error Recovery

If recovery fails:

1. Check `recovery_status` output for error details
2. Verify snapshot availability in `latest_snapshots` output
3. Increase `wait_for_backup_completion` if snapshots aren't ready
4. Check BRS instance logs for detailed error messages

## Validation Checklist

Before deploying with recovery enabled:

- [ ] Protection groups are configured correctly
- [ ] Backup policy schedule is appropriate for your needs
- [ ] `wait_for_backup_completion` is set based on cluster size
- [ ] For cross-cluster: Target cluster is pre-registered with BRS
- [ ] For cross-cluster: Network connectivity exists between clusters
- [ ] Recovery operations reference correct protection group names
- [ ] Sufficient resources exist in target cluster for restored workloads

## Limitations and Considerations

### Current Limitations

1. **Initial Backup Required**: Recovery requires at least one completed backup. First `terraform apply` will only create protection groups and wait.

2. **Fixed Wait Time**: The wait period is fixed. If backups take longer than configured, recovery will fail with "no snapshots found" error.

3. **Target Cluster Pre-registration**: For cross-cluster recovery, the target cluster must be pre-registered with the BRS instance.

4. **Snapshot Selection**: Currently supports "latest" snapshot or explicit snapshot ID. Time-based snapshot selection requires manual snapshot ID lookup.

### Future Enhancements

Potential improvements for future versions:

1. **Dynamic Wait**: Poll for backup completion instead of fixed wait time
2. **Auto-registration**: Automatically register target cluster for cross-cluster recovery
3. **Snapshot Filtering**: Advanced snapshot selection (by time range, tags, etc.)
4. **Namespace Mapping**: Map source namespaces to different target namespaces
5. **Selective Recovery**: Recover specific resources within a namespace

## Support and Troubleshooting

### Debug Mode

Enable detailed logging by setting:

```bash
export TF_LOG=DEBUG
terraform apply
```

### Useful Commands

Check backup runs:

```bash
ibmcloud backup-recovery protection-group-runs list \
  --protection-group-id <pg-id> \
  --instance-id <brs-instance-guid>
```

Check recovery status:

```bash
ibmcloud backup-recovery recovery get \
  --recovery-id <recovery-id> \
  --instance-id <brs-instance-guid>
```

### Additional Resources

- [IBM Backup Recovery Documentation](https://cloud.ibm.com/docs/backup-recovery)
- [Terraform IBM Provider Documentation](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs)
- [Module README](./README.md)
- [Protection Group Configuration Guide](./ProtectionGroup.md)

---

**Last Updated:** 2026-05-08
**Module Version:** 2.0.0+
**Tested With:**

- Terraform >= 1.9.0
- IBM Provider >= 1.88.3
- IBM Backup Recovery Service v7.2.18+
