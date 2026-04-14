# Kubernetes Protection Group Configuration Guide

This document provides comprehensive guidance on configuring IBM Backup Recovery Protection Groups for Kubernetes clusters, including limitations, best practices, and working examples discovered through testing.

## Table of Contents

- [Overview](#overview)
- [Key Limitations](#key-limitations)
- [Supported Features](#supported-features)
- [Configuration Examples](#configuration-examples)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

Protection Groups in IBM Backup Recovery provide granular control over which Kubernetes resources are backed up and how. This guide documents the specific limitations and requirements for Kubernetes protection groups that differ from other source types.

---

## Key Limitations

### 1. Blackout Window Controls

**❌ NOT SUPPORTED for Kubernetes:**

```terraform
# These parameters cause errors for Kubernetes protection groups
abort_in_blackouts = true   # Error: Not supported for this source type
pause_in_blackouts = true   # Error: Not supported for this source type
```

**✅ SUPPORTED Alternative:**

```terraform
is_paused = true  # Use this to manually pause/resume backups
```

**Validation Rule:**
- Kubernetes protection groups do not support blackout window controls
- Use `is_paused` for manual pause/resume functionality
- Blackout windows are only supported for other source types (VMs, databases, etc.)

---

### 2. Resource Filtering Restrictions

#### Cannot Use Both Include and Exclude

**❌ INVALID Configuration:**

```terraform
objects = [
  {
    name = "my-namespace"

    included_resources = [
      "deployments",
      "statefulsets"
    ]

    excluded_resources = [  # Error: Cannot use both
      "events",
      "replicasets"
    ]
  }
]
```

**Error Message:**
```
Both include and exclude resource options can't be used
```

**✅ VALID Configurations:**

**Option 1: Include Only (Whitelist)**
```terraform
objects = [
  {
    name = "my-namespace"
    included_resources = [
      "deployments",
      "statefulsets",
      "secrets"
    ]
  }
]
```

**Option 2: Exclude Only (Blacklist)**
```terraform
objects = [
  {
    name = "my-namespace"
    excluded_resources = [
      "events",
      "replicasets"
    ]
  }
]
```

**Option 3: No Filtering (Backup Everything)**
```terraform
objects = [
  {
    name = "my-namespace"
    # No resource filtering - backs up all resources
  }
]
```

---

### 3. PVC-Related Resources Cannot Be Explicitly Included

**❌ INVALID Configuration:**

```terraform
included_resources = [
  "deployments",
  "persistentvolumeclaims",  # Error: PVC-related resources not allowed
  "configmaps",              # Error: PVC-related resources not allowed
  "storageclasses"           # Error: PVC-related resources not allowed
]
```

**Error Message:**
```
PVC-related resources (like pvc, configmap, sc, etc.) cannot be included in resource selection.
```

**✅ VALID Configuration:**

```terraform
included_resources = [
  "deployments",
  "statefulsets",
  "daemonsets",
  "secrets",
  "services",
  "ingresses"
]
# PVCs and ConfigMaps are automatically backed up with the namespace
```

**Explanation:**
- PVCs, ConfigMaps, and StorageClasses are automatically included in namespace backups
- Explicitly listing them in `included_resources` causes an error
- They are handled by the backup system based on the namespace selection

---

### 4. Blackout Configuration Mutual Exclusivity

**❌ INVALID Configuration:**

```terraform
abort_in_blackouts = true
pause_in_blackouts = true  # Error: Cannot both be true
```

**Error Message:**
```
Protection can not be created/updated if both 'abortInBlackouts' and 'pauseInBlackouts' are set as true
```

**Note:** This limitation applies to all source types, not just Kubernetes. However, since Kubernetes doesn't support blackout controls at all, this is documented for completeness.

---

## Supported Features

### ✅ Fully Supported Features

| Feature | Parameter | Values | Description |
|---------|-----------|--------|-------------|
| **Priority** | `priority` | `kLow`, `kMedium`, `kHigh` | Backup job execution priority |
| **QoS Policy** | `qos_policy` | `kBackupHDD`, `kBackupSSD`, `kBackupAll` | Storage tier for backups |
| **Start Time** | `start_time` | Object with hour, minute, timezone | Schedule backup start time |
| **Pause Control** | `is_paused` | `true`, `false` | Manually pause/resume backups |
| **CSI Snapshots** | `leverage_csi_snapshot` | `true`, `false` | Use CSI for faster backups |
| **Indexing** | `enable_indexing` | `true`, `false` | Enable search/indexing |
| **Label Filtering** | `include_params`, `exclude_params` | Label vectors | Filter by Kubernetes labels |
| **Alerts** | `alert_policy` | Object | Email notifications |
| **SLA** | `sla` | Array of SLA objects | Backup time SLA monitoring |

---

## Configuration Examples

### Example 1: Minimal Production Configuration

```terraform
protection_groups = [
  {
    name        = "production-backup"
    policy_name = "daily-retention"
    description = "Production workload backup"

    # High priority for production
    priority   = "kHigh"
    qos_policy = "kBackupSSD"

    # Schedule for 2 AM EST
    start_time = {
      hour      = 2
      minute    = 0
      time_zone = "America/New_York"
    }

    # Backup specific namespace
    objects = [
      {
        name = "production-namespace"
      }
    ]
  }
]
```

---

### Example 2: Selective Resource Backup

```terraform
protection_groups = [
  {
    name        = "app-backup"
    policy_name = "weekly-retention"
    description = "Application-specific backup"

    priority = "kMedium"

    objects = [
      {
        name = "app-namespace"

        # Only backup specific resource types
        included_resources = [
          "deployments",
          "statefulsets",
          "secrets",
          "services"
        ]
      }
    ]
  }
]
```

---

### Example 3: Label-Based Filtering

```terraform
protection_groups = [
  {
    name        = "labeled-backup"
    policy_name = "daily-retention"
    description = "Backup resources with specific labels"

    priority = "kHigh"

    objects = [
      {
        name = "my-namespace"
      }
    ]

    # Include resources with ANY of these labels
    include_params = {
      label_combination_method = "OR"
      label_vector = [
        {
          key   = "backup-enabled"
          value = "true"
        },
        {
          key   = "environment"
          value = "production"
        }
      ]
    }

    # Exclude resources with ALL of these labels
    exclude_params = {
      label_combination_method = "AND"
      label_vector = [
        {
          key   = "backup-exclude"
          value = "true"
        }
      ]
    }
  }
]
```

---

### Example 4: Complete Advanced Configuration

```terraform
protection_groups = [
  {
    # Basic Configuration
    name        = "advanced-backup"
    policy_name = "comprehensive-retention"
    description = "Comprehensive protection group with all features"

    # Priority & Performance
    priority   = "kHigh"
    qos_policy = "kBackupSSD"

    # Scheduling
    start_time = {
      hour      = 2
      minute    = 30
      time_zone = "America/New_York"
    }

    # Pause Control
    is_paused = false

    # Kubernetes Features
    enable_indexing       = true
    leverage_csi_snapshot = true
    non_snapshot_backup   = false
    volume_backup_failure = false

    # Objects to Protect
    objects = [
      {
        name = "production-namespace"

        backup_only_pvc             = false
        fail_backup_on_hook_failure = false

        # Resource filtering (include only)
        included_resources = [
          "deployments",
          "statefulsets",
          "secrets",
          "services"
        ]
      }
    ]

    # Label-Based Filtering
    include_params = {
      label_combination_method = "OR"
      label_vector = [
        {
          key   = "backup-enabled"
          value = "true"
        },
        {
          key   = "tier"
          value = "critical"
        }
      ]
    }

    exclude_params = {
      label_combination_method = "AND"
      label_vector = [
        {
          key   = "backup-exclude"
          value = "true"
        }
      ]
    }

    # Email Alerts
    alert_policy = {
      backup_run_status = [
        "kFailure",
        "kSlaViolation",
        "kWarning"
      ]

      alert_targets = [
        {
          email_address  = "ops-team@example.com"
          language       = "en-us"
          recipient_type = "kTo"
        },
        {
          email_address  = "backup-admin@example.com"
          language       = "en-us"
          recipient_type = "kCc"
        }
      ]

      raise_object_level_failure_alert                    = true
      raise_object_level_failure_alert_after_last_attempt = true
      raise_object_level_failure_alert_after_each_attempt = false
    }

    # SLA Configuration
    sla = [
      {
        backup_run_type = "kFull"
        sla_minutes     = 120  # 2 hours
      },
      {
        backup_run_type = "kIncremental"
        sla_minutes     = 60   # 1 hour
      }
    ]
  }
]
```

---

## Troubleshooting

### Common Errors and Solutions

#### Error 1: Blackout Controls Not Supported

**Error:**
```
Pause in quiet times is not supported for this source type.
```

**Solution:**
Remove `abort_in_blackouts` and `pause_in_blackouts` parameters:
```terraform
# Remove these lines
# abort_in_blackouts = false
# pause_in_blackouts = true

# Use this instead
is_paused = false
```

---

#### Error 2: Both Include and Exclude Resources

**Error:**
```
Both include and exclude resource options can't be used
```

**Solution:**
Choose either `included_resources` OR `excluded_resources`, not both:
```terraform
# Option 1: Include only
included_resources = ["deployments", "statefulsets"]

# Option 2: Exclude only
# excluded_resources = ["events", "replicasets"]
```

---

#### Error 3: PVC-Related Resources

**Error:**
```
PVC-related resources (like pvc, configmap, sc, etc.) cannot be included in resource selection.
```

**Solution:**
Remove PVC-related resources from `included_resources`:
```terraform
# Remove these from included_resources:
# - persistentvolumeclaims
# - configmaps
# - storageclasses

# Valid configuration:
included_resources = [
  "deployments",
  "statefulsets",
  "secrets"
]
```

---

#### Error 4: Namespace Not Found

**Error:**
```
Cannot resolve namespace 'my-namespace' to an ID
```

**Solution:**
1. Ensure the namespace exists in the cluster
2. Wait for Data Source Connector to discover the namespace (3-5 minutes)
3. Verify namespace is visible in protection sources:
```bash
kubectl get namespace my-namespace
```

---

## Best Practices

### 1. Resource Selection Strategy

**Whitelist Approach (Recommended for Production):**
```terraform
included_resources = [
  "deployments",
  "statefulsets",
  "secrets",
  "services"
]
```
- ✅ Explicit control over what's backed up
- ✅ Prevents accidental backup of unnecessary resources
- ✅ Faster backups with smaller backup size

**Blacklist Approach:**
```terraform
excluded_resources = [
  "events",
  "replicasets"
]
```
- ✅ Easier to implement
- ✅ Backs up everything except specified resources
- ⚠️ May backup unnecessary data

---

### 2. Label-Based Filtering

**Opt-In Strategy (Recommended):**
```terraform
include_params = {
  label_combination_method = "AND"
  label_vector = [
    { key = "backup-enabled", value = "true" }
  ]
}
```
- ✅ Only backs up explicitly labeled resources
- ✅ Prevents accidental backups
- ✅ Clear backup intent

**Opt-Out Strategy:**
```terraform
exclude_params = {
  label_combination_method = "AND"
  label_vector = [
    { key = "backup-exclude", value = "true" }
  ]
}
```
- ✅ Backs up everything except labeled resources
- ⚠️ Risk of backing up unnecessary data

---

### 3. Scheduling Best Practices

```terraform
start_time = {
  hour      = 2      # Off-peak hours (2-4 AM)
  minute    = 30     # Stagger multiple protection groups
  time_zone = "America/New_York"  # Match operations team timezone
}
```

**Recommendations:**
- Schedule during low-traffic periods (typically 2-4 AM)
- Stagger multiple protection groups by 15-30 minutes
- Use timezone of your operations team
- Consider backup window duration when scheduling

---

### 4. Alert Configuration

```terraform
alert_policy = {
  backup_run_status = [
    "kFailure",        # Always alert on failures
    "kSlaViolation",   # Alert on SLA breaches
    # "kWarning",      # Optional: may be noisy
    # "kSuccess"       # Optional: for audit trail
  ]

  alert_targets = [
    {
      email_address  = "ops-team@example.com"
      recipient_type = "kTo"
    }
  ]

  raise_object_level_failure_alert_after_last_attempt = true
}
```

**Recommendations:**
- Always alert on failures and SLA violations
- Use object-level alerts for granular failure tracking
- Alert after last attempt to reduce noise
- Separate distribution lists for different severity levels

---

### 5. SLA Configuration

```terraform
sla = [
  {
    backup_run_type = "kFull"
    sla_minutes     = 120  # Based on data size and network
  },
  {
    backup_run_type = "kIncremental"
    sla_minutes     = 60   # Typically faster than full
  }
]
```

**Recommendations:**
- Set realistic SLAs based on actual backup times
- Monitor SLA violations and adjust as needed
- Different SLAs for full vs incremental backups
- Consider network bandwidth and storage performance

---

### 6. CSI Snapshot Usage

```terraform
leverage_csi_snapshot = true   # Enable for faster backups
non_snapshot_backup   = false  # Use snapshot-based backups
```

**When to Enable:**
- ✅ Storage supports CSI snapshots (IBM VPC Block Storage)
- ✅ Need application-consistent backups
- ✅ Want faster backup/restore times
- ✅ Have snapshot-capable storage class

**When to Disable:**
- ❌ Storage doesn't support CSI
- ❌ Using non-CSI storage drivers
- ❌ Need file-level backup granularity

---

## Allowed Resource Types

### Safe to Include in `included_resources`

```terraform
included_resources = [
  # Workload Resources
  "deployments",
  "statefulsets",
  "daemonsets",
  "replicasets",
  "jobs",
  "cronjobs",

  # Configuration & Secrets
  "secrets",

  # Networking
  "services",
  "ingresses",
  "networkpolicies",

  # RBAC
  "roles",
  "rolebindings",
  "serviceaccounts"
]
```

### Automatically Handled (Do Not Include)

These resources are automatically backed up with the namespace:
- `persistentvolumeclaims`
- `configmaps`
- `storageclasses`
- `persistentvolumes`

### Typically Excluded

These resources are usually not needed in backups:
- `events` (ephemeral)
- `endpoints` (auto-generated)
- `pods` (managed by controllers)

---

## Summary

### Key Takeaways

1. **❌ Do NOT use** `abort_in_blackouts` or `pause_in_blackouts` for Kubernetes
2. **❌ Do NOT use** both `included_resources` and `excluded_resources`
3. **❌ Do NOT include** PVC-related resources in `included_resources`
4. **✅ DO use** `is_paused` for manual pause control
5. **✅ DO choose** either whitelist or blacklist approach for resources
6. **✅ DO wait** 3-5 minutes for DSC to discover new namespaces
7. **✅ DO use** label-based filtering for dynamic resource selection
8. **✅ DO configure** alerts and SLAs for production workloads

---

## Additional Resources

- [IBM Backup Recovery Documentation](https://cloud.ibm.com/docs/backup-recovery)
- [Terraform IBM Provider Documentation](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs)
- [Module README](./README.md)
- [Main Module Documentation](../../README.md)

---

**Last Updated:** 2026-03-09
**Tested With:**
- Terraform IBM Provider v1.89.0
- IBM Backup Recovery Service v7.2.17
- Kubernetes v1.28+
