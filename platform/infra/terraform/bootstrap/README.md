# Bootstrap

The small, permanent part of the AWS side: everything else can be created and destroyed per session, this stays.

| Resource | Purpose |
|---|---|
| S3 bucket `<project>-state-<account>` | Terraform state, versioned, encrypted, TLS only, native lock file (`use_lockfile`) |
| S3 bucket `<project>-backups-<account>` | Backups with lifecycle rules |
| GitHub OIDC provider | CI authenticates with short-lived tokens, no access keys in GitHub |
| Role `<project>-gha-plan` | Read-only plans for pull requests of this repository |
| Role `<project>-gha-apply` | Apply jobs that run in the protected GitHub Environment (`aws-apply` by default) |
| Budget and anomaly monitor | Alerts at 50, 80, 100 percent of actual and 100 percent of forecasted cost |

Cost: cents per month. The roles and buckets are named with the project prefix so the CI policy can stay narrow.

## Checks without an AWS account

```bash
task lint:tf     # fmt, init -backend=false, validate, terraform test with a mocked provider, tflint
```

The same checks run in CI on every push. No credentials are needed.

## Apply (needs an AWS account)

Do the first-hour steps in `features/AWS-SANDBOX.md` first: MFA on the root user, a working non-root identity, one region. Then:

```bash
cd platform/infra/terraform/bootstrap
cp bootstrap.example.tfvars terraform.tfvars    # edit: region, owner, repository, alert e-mail
terraform init
terraform plan
terraform apply
```

The first apply keeps its state on your machine, because the state bucket does not exist yet. Move the state into the bucket right after:

1. Create `backend.tf` next to the other files with `terraform { backend "s3" {} }`.
2. Copy `backend.hcl.example` to `backend.hcl` and fill in the account id and region (the file is ignored by git).
3. Run `terraform init -migrate-state -backend-config=backend.hcl` and answer `yes`.
4. Delete the local `terraform.tfstate` files after checking `terraform state list`.

If you created a budget by hand during the first hour, delete the manual one once the Terraform budget exists, to avoid duplicate alerts.

## After apply

- Create a GitHub Environment named `aws-apply` and add yourself as a required reviewer.
- Store `plan_role_arn` and `apply_role_arn` from the outputs as repository variables for the workflows.
- Confirm the e-mail subscription messages from AWS Budgets and Cost Anomaly Detection.

## Destroying

Do not destroy this module while other state files live in the state bucket. Empty both buckets (including old versions) before `terraform destroy`; the buckets are not created with `force_destroy` on purpose.
