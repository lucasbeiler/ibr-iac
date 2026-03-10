## Instructions
1. Set the environment variables (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`) accordingly. Note that the account must have the proper permissions to interact with IAM, EC2 and S3. Keep these variables inside a .env file in order to source it when needed if you are going to develop on top of this codebase.
2. Terraform state file is stored centrally in an S3 bucket, this is configured in `backend.tf`. Note that this bucket must already exist beforehand. If you don't want a remote state file, delete the `backend.tf` file from here.
3. Run `terraform init` to download the dependencies and initialize Terraform.
4. Run `terraform apply` to see the Terraform provisioning plan and enter "yes" to apply (or run with `--auto-approve` right away). The `terraform plan` command can also be used to view the provisioning plan.
5. For now, run `terraform output -raw private_key > ec2_spot_private_key && chmod 400 ec2_spot_private_key` to output the SSH private key.
6. For now, obtain the instances' public IPs from the EC2 dashboard. Note that the working SSH port is 65535.
7. SSH into `alpine@IP_ADDRESS -p 65535` when needed.

NOTE: Certain AWS regions require you to opt-in, you should opt-in and wait some time before applying the Terraform resources. You can edit `locals.tf` to set the regions and other preferences.
