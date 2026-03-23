# Cross-Region Recovery Runbook (IKS)

Run from examples/kubernetes.

## Inputs you must have

- Source snapshot_id
- Source protection_group_id
- Target source_registration_id (target region cluster already registered in BRS)

## 1) Prepare variables

Edit recovery-cross-region.tfvars and set:

- recovery_snapshot_id
- recovery_protection_group_id
- recovery_target_source_registration_id
- recovery_name (new value each run)

## 2) Validate + Plan

```bash
terraform validate
terraform plan \
  -refresh=false \
  -target=module.backup_recover_protect_iks.ibm_backup_recovery.recover_snapshot \
  -var-file=backup.tfvars \
  -var-file=recovery-cross-region.tfvars \
  -out=plan.recovery.cross-region.tfplan
```

## 3) Apply

```bash
terraform apply plan.recovery.cross-region.tfplan
```

## 4) Observe recovery state

```bash
terraform output recovery_ids
terraform output recovery_status
```

## 5) Verify on target cluster

Use target cluster kubeconfig and check restored namespace/resources:

```bash
kubectl get ns
kubectl -n <restored-namespace> get deploy,pod,pvc
```

For PVC data validation:

```bash
kubectl -n <restored-namespace> exec <pod> -- sh -c 'ls -lah /data && wc -c /data/testfile.dat'
```

## Notes

- If plan complains about immutable recovery updates, change recovery_name and retry.
- Keep backup.tfvars in the command, because it carries required base variables.
- Use the same account/API key context that owns the tracked infra state.
