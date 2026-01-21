## Protection Policy Variable

The `policy` variable defines backup **schedule**, **retention**, and optional advanced settings for a protection policy.


### Main Policy Types

| Policy Style       | Name must be       | Schedule | Retention | Description                                  |
|--------------------|--------------------|----------|-----------|----------------------------------------------|
| **Built-in**       | Gold / Silver / Bronze | **not allowed** | **not allowed** | Use predefined vendor policy |
| **Custom**         | anything else      | **required**    | **required**    | Fully customizable schedule + retention      |

> **Validation rule** — enforced automatically:
> - If name = Gold/Silver/Bronze → schedule & retention must be **null/omitted**
> - For any other name → both schedule **and** retention are **mandatory**

### Examples

#### 1. Using Built-in Policy (Recommended for quick/standard protection)

```
 {
  name                      = "Gold"
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

### Quick Reference Table – Schedule Units

| Unit      | Required Fields                     | Optional Fine-tuning fields                     | Typical Use-case                     |
|-----------|-------------------------------------|--------------------------------------------------|--------------------------------------|
| Minutes   | frequency                           | minute_schedule, hour_schedule                  | Very frequent (log shipping style)   |
| Hours     | frequency                           | hour_schedule                                   | Common (4h, 6h, 12h, 24h)            |
| Days      | frequency                           | hour_schedule, day_schedule                     | Daily backups                        |
| Weeks     | —                                   | week_schedule.day_of_week                       | Weekly full + incrementals           |
| Months    | —                                   | month_schedule.{day_of_week, week_of_month, day_of_month} | Monthly/quarterly long-term     |
| Years     | —                                   | year_schedule.day_of_year                       | Yearly archival                      |

### Policy Best Practices

- Start with built-in **Gold / Silver / Bronze** policies when suitable
- Always set both **schedule** + **retention** for custom policies
- Use descriptive names: `daily-2am-30d`, `weekly-2y`, `hourly-7d`
- [Policy creation](https://cloud.ibm.com/docs/backup-recovery?topic=backup-recovery-baas-policy-creation)
