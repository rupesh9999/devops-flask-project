# DevOps Flask Project

Single-source specification to deploy a public Flask application with a private MySQL backend on AWS using Terraform, complete with automation scripts, SSL configuration, troubleshooting runbook, and post-mortem template.

## Repository Structure
```
project-root/
├─ app/
│  ├─ flask_app/        # Flask service (Gunicorn-ready)
│  └─ nginx/            # Reference Nginx config & Certbot hook
├─ db/
│  ├─ init.sql          # Sample schema & seed data
│  └─ my.cnf            # Client config template
├─ docs/
│  ├─ README.md         # Detailed architecture, runbook, troubleshooting
│  └─ postmortem_template.md
├─ infra/
│  └─ terraform/        # Terraform IaC (VPC, NAT, EC2, IAM, SGs)
├─ scripts/
│  ├─ ec2_user_data_flask.sh
│  └─ ec2_user_data_mysql.sh
└─ README.md            # (this file)
```

## High-Level Architecture
- **VPC (10.0.0.0/16)** with public (`10.0.1.0/24`) and private (`10.0.2.0/24`) subnets.
- **Public EC2** runs Flask + Nginx + Certbot. Accessible over HTTPS (IP allow-list optional).
- **Private EC2** runs MySQL; no public IP. Only `sg-flask` may reach port `3306`.
- **Internet Gateway** for the public subnet and **NAT Gateway** for outbound from the private subnet.
- **IAM role + instance profile** enabling SSM Session Manager and (optional) CloudWatch logs.

## Getting Started
1. Install prerequisites: Terraform (>= 1.5), AWS CLI v2, Git, Python 3, and configure AWS credentials.
2. Supply Terraform variables (`infra/terraform/terraform.tfvars`) including:
   - `aws_region`, `key_pair_name`, `app_repo_url`, `db_password`
   - Optional: `domain_name`, `acme_email`, `flask_allowed_cidr`, `ssh_allowed_cidr`, `ip_allowlist`
3. Deploy infrastructure:
   ```bash
   cd infra/terraform
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```
4. Map the Flask EC2 public IP to your domain (if using SSL) and confirm Certbot success.
5. Review `docs/README.md` for detailed runbook, testing commands, troubleshooting, and failure simulation steps.

## Operations & Runbook
Key operational guidance (testing matrix, troubleshooting checklist, failure drills, IAM requirements, NAT configuration notes) lives in [`docs/README.md`](docs/README.md). Treat it as the authoritative runbook.

## Bonus Items
- **IP-based Access Control:** Configure `ip_allowlist` variable to auto-generate Nginx `allow/deny` directives.
- **Post-Mortem Template:** Located at [`docs/postmortem_template.md`](docs/postmortem_template.md) for incident documentation.

## Hashtags for Progress Updates
`#getfitwithsagar #SRELife #DevOpsForAll`
