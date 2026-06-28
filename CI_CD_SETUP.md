# One-time GitHub Actions setup

This repo's `.github/workflows/terraform.yml` runs `terraform plan` on every
PR and comments the diff, and runs `terraform apply` only when someone
manually triggers it. It authenticates to AWS via OIDC - no AWS access keys
are stored in GitHub. Do these steps once, in order.

## 1. Apply locally first

`github_oidc.tf` creates the IAM role the workflow will assume. It has to
exist before the workflow can run, so apply it the normal way you already do:

```bash
terraform init
terraform apply
```

## 2. Get the role ARN

```bash
terraform output -raw github_actions_role_arn
```

## 3. Add GitHub repo secrets

Repo Settings -> Secrets and variables -> Actions -> New repository secret.
Add all four:

- `AWS_OIDC_ROLE_ARN` - the value from step 2
- `AWS_ACCOUNT_ID` - same value you put in your local `terraform.tfvars`
- `GRAFANA_CLOUD_ACCOUNT_ID` - same value as your local `terraform.tfvars`
- `GRAFANA_API_TOKEN` - same value as your local `terraform.tfvars`

These mirror your local `terraform.tfvars` - the workflow passes them through
as `TF_VAR_*` environment variables instead of reading a `.tfvars` file.

## 4. Create the approval gate

Repo Settings -> Environments -> New environment -> name it exactly
`infra-apply` -> under "Deployment protection rules" check "Required
reviewers" and add yourself and/or teammates -> Save.

This is what makes `apply` manual: the workflow's apply job targets this
Environment, so GitHub pauses the run and waits for one of the listed
reviewers to click Approve before `terraform apply` actually executes.

## 5. Try it

- Open a PR that touches a `.tf` file or `index.py` -> the `plan` job runs
  automatically and comments the plan on the PR.
- To apply: Actions tab -> "Terraform CI/CD" workflow -> Run workflow ->
  approve the `infra-apply` request when it appears.

## Notes

- The lambda zip is rebuilt from `index.py` inside the workflow every run, so
  you no longer need to manually re-zip and commit `lambda_function.zip`
  after editing `index.py` - just commit the `.py` change.
- The role's permissions (`PowerUserAccess` + a scoped IAM policy in
  `github_oidc.tf`) are broad. That's acceptable for this training/capstone
  AWS account; narrow the IAM policy's `Resource` entries before ever
  reusing this pattern against a production account.
