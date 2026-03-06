## Protection Policy Variable

The `policy` variable defines backup **schedule**, **retention**, and optional advanced settings for a protection policy.


### Main Policy Types

| Policy Style       | Name               | Schedule | Retention | Description                                  |
|--------------------|--------------------|----------|-----------|----------------------------------------------|
| **Existing**       | any existing policy name | **not allowed** | **not allowed** | Use pre-existing policy by name |
| **Custom**         | any custom name    | **required**    | **required**    | Fully customizable schedule + retention      |

> **Validation rule** — enforced automatically:
> - If schedule & retention are **null/omitted** → treated as an existing policy (any name is valid)
> - If both schedule **and** retention are provided → a new custom policy is created

---

### Advanced Policy Attributes

You can further customize your policy with these optional blocks:

| Attribute | Purpose |
|-----------|---------|
| **Blackout Windows** | Define specific times when backups should **not** run (e.g., peak business hours). |
| **Run Timeouts** | Set maximum duration for backup jobs to prevent hung processes from consuming resources. |
| **Full Backups** | Configure periodic full backups on top of incrementals, with their own retention period. |
| **Extended Retention** | "Pin" specific snapshots (e.g., weekly or monthly) to be kept longer than the standard retention. |

---

### Examples

#### 1. Using an Existing Policy (Recommended for quick/standard protection)

```
 {
  name                      = "my-existing-policy"
  use_default_backup_target = true
  # schedule and retention must NOT be set
}
```

#### 2. Every 4 hours + keep 31 days

```
 {
  name = "frequent-daily"

  schedule = {
    unit      = "Hours"
    frequency = 4
  }

  retention = {
    duration = 31
    unit     = "Days"
  }

  use_default_backup_target = true
}
```

#### 3. Daily at 2:00 AM + keep for 12 weeks

```
 {
  name = "daily-backup-2am"

  schedule = {
    unit      = "Days"
    frequency = 1

    # Optional - forces run at 2:00 (many systems interpret this as start-of-day offset)
    hour_schedule = {
      frequency = 2   # many vendors use this for hour of day (0-23)
    }
  }

  retention = {
    duration = 12
    unit     = "Weeks"
  }
}
```

#### 4. Weekly (every Sunday) + monthly retention + WORM/Compliance lock

```
 {
  name = "weekly-compliance-critical"

  schedule = {
    unit = "Weeks"
    week_schedule = {
      day_of_week = ["Sunday"]
    }
  }

  retention = {
    duration = 7
    unit     = "Years"

    data_lock_config = {
      mode                           = "Compliance"
      unit                           = "Years"
      duration                       = 7
      enable_worm_on_external_target = true
    }
  }
}
```

#### 5. Monthly on last day of month + yearly last day

```
 {
  name = "end-of-month-critical"

  schedule = {
    unit = "Months"

    month_schedule = {
      day_of_month = -1           # many systems accept -1 = last day
      # Alternative styles some vendors support:
      # day_of_week   = ["Friday"]
      # week_of_month = "Last"
    }
  }

  retention = {
    duration = 10
    unit     = "Years"
  }
}
```

#### 6. Advanced: Blackout Windows & Extended Retention

```hcl
{
  name = "advanced-production-policy"
  schedule = {
    unit      = "Hours"
    frequency = 4
  }
  retention = {
    duration = 30
    unit     = "Days"
  }
  # Don't run backups during Monday morning maintenance
  blackout_window = [
    {
      day = "Monday"
      start_time = { hour = 8, minute = 0 }
      end_time   = { hour = 12, minute = 0 }
    }
  ]
  # Keep a monthly snapshot for 2 years
  extended_retention = [
    {
      schedule  = { unit = "Months", frequency = 1 }
      retention = { duration = 2, unit = "Years" }
    }
  ]
}
```

### Quick Reference Table – Schedule Units

| Unit      | Required Fields                     | Optional Fine-tuning fields                     | Typical Use-case                     |
|-----------|-------------------------------------|--------------------------------------------------|--------------------------------------|
| Minutes   | frequency                           | minute_schedule, hour_schedule                  | Very frequent (log shipping style)   |
| Hours     | frequency                           | hour_schedule                                   | Common (4h, 6h, 12h)                 |
| Days      | frequency                           | hour_schedule, day_schedule                     | Daily backups                        |
| Weeks     | —                                   | week_schedule.day_of_week                       | Weekly full + incrementals           |
| Months    | —                                   | month_schedule.{day_of_week, week_of_month, day_of_month} | Monthly long-term archival       |
| Years     | —                                   | year_schedule.day_of_year                       | Yearly compliance snapshots          |

### Policy Best Practices

- Start with an existing policy when suitable (omit schedule and retention)
- Always set both **schedule** + **retention** for custom policies
- Use **Blackout Windows** to avoid performance impact during peak hours
- Use **Extended Retention** instead of keeping ALL backups for a long time (saves storage costs)
- Use descriptive names: `daily-2am-30d`, `weekly-2y`, `hourly-7d`
- [Policy creation](https://cloud.ibm.com/docs/backup-recovery?topic=backup-recovery-baas-policy-creation)
