# DevOps Flask Project Runbook

## 1. Overview
- **Goal:** Deploy a public Python Flask application backed by a private MySQL database inside an AWS VPC with proper network segregation, HTTPS termination, and operational runbooks.
- **Infrastructure:** Provisioned via Terraform in `infra/terraform` (single source of truth).
- **Application:** Flask app with SQLAlchemy connectivity checks located under `app/flask_app`.
- **Automation Scripts:** Cloud-init style user data scripts in `scripts/` bootstrap both EC2 instances.
- **Bonus Features:** Optional IP allow-listing, post-mortem template, and detailed troubleshooting playbooks.

## 2. Architecture
```
                           +---------------------------+
                           |        Internet           |
                           +-------------+-------------+
                                         |
                                   HTTPS 443 / HTTP 80
                                         |
                              +----------v-----------+
                              |  Public Subnet 10.0.1.0/24 |
                              |  (AZ A)                   |
                              +-----+----------+----------+
                                    |          |
                                    |          |
                                    |   +------+-------+
                                    |   | NAT Gateway  |
                               +----v----+             |
                               | EC2     |             |
                               | Flask   |             |
                               | (sg-flask)            |
                               +---------+-------------+
                                         |
                     Private traffic 3306| (Security Group reference)
                                         |
                              +----------v-----------+
                              | Private Subnet 10.0.2.0/24 |
                              | (AZ A)                     |
                              +------------+---------------+
                                           |
                                 +---------v-----------+
                                 | EC2 MySQL           |
                                 | (sg-db)             |
                                 +---------------------+
```

### Routing & Networking
- **VPC:** `/16` CIDR (`10.0.0.0/16`).
- **Public subnet:** `10.0.1.0/24` with route table defaulting to Internet Gateway.
- **Private subnet:** `10.0.2.0/24` routing `0.0.0.0/0` via NAT Gateway in the public subnet.
- **IGW & NAT:** Internet Gateway enables inbound/outbound for the public subnet; NAT Gateway gives private hosts egress.
- **Elastic IP:** Allocated to the NAT Gateway.

### Security Groups
- **`sg-flask`:**
  - Inbound: `443` from configurable `flask_allowed_cidr` (defaults to `0.0.0.0/0`).
  - Inbound: `80` from `0.0.0.0/0` for Certbot HTTP challenges.
  - Inbound: `22` from configurable `ssh_allowed_cidr` (restrict in production).
  - Outbound: All traffic (needed for DB and package updates).
- **`sg-db`:**
  - Inbound: `3306` permitted **only** from `sg-flask` (security group reference).
  - Optional: `22` from `ssh_allowed_cidr` if direct SSH is allowed (consider SSM only).
  - Outbound: All.

### IAM & Access Control
- Terraform expects an IAM user/role with rights to manage EC2, VPC, IAM (PassRole), and related networking resources.
- EC2 instances assume an IAM role that grants:
  - `AmazonSSMManagedInstanceCore` – Systems Manager Session Manager access (replace SSH).
  - `CloudWatchAgentServerPolicy` – (Optional) allow pushing logs/metrics.

## 3. Prerequisites
1. **Workstation:** Terraform `>= 1.5`, AWS CLI v2, Git, Python 3.8+.
2. **AWS Account:** Admin or scoped permissions to create VPC, EC2, IAM roles, EIP, NAT, Route53 record (if using Certbot DNS auth), and ACM (if you opt out of Certbot).
3. **SSH Key Pair:** Existing key in target region (`key_pair_name` variable).
4. **Domain Name:** DNS A record pointing to the Flask EC2 public IP for SSL (optional but recommended).
5. **Secrets Management:** Decide on secure storage for DB password (e.g., Terraform variable file kept out of VCS).

## 4. Terraform Deployment Guide
1. **Clone repository & configure backend (optional):**
   ```bash
   git clone <repo-url>
   cd devops-flask-project/infra/terraform
   ```
2. **Create `terraform.tfvars` (never commit secrets):**
   ```hcl
   aws_region          = "us-east-1"
   key_pair_name       = "my-keypair"
   db_password         = "SuperS3cret!"
   app_repo_url        = "https://github.com/your-org/devops-flask-project.git"
   domain_name         = "app.example.com"        # optional
   acme_email          = "admin@example.com"       # optional
   flask_allowed_cidr  = "203.0.113.0/24"          # optional tightening
   ssh_allowed_cidr    = "198.51.100.25/32"        # restrict SSH
   ip_allowlist        = "203.0.113.5/32,198.51.100.25/32"  # optional
   db_allowed_host_pattern = "10.0.1.%"
   ```
3. **Initialize & validate:**
   ```bash
   terraform init
   terraform fmt
   terraform validate
   ```
4. **Plan & apply:**
   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   ```
5. **Outputs:**
   - `public_instance_public_ip` – use for DNS mapping & testing.
   - `private_instance_private_ip` – database connectivity.

> **Note:** NAT Gateway incurs hourly + data processing costs; destroy resources when testing is complete (`terraform destroy`).

## 5. Post-Provision Application Steps
1. **Verify Flask EC2 bootstrap:**
   ```bash
   ssh -i path/to/key.pem ubuntu@<public_instance_public_ip>
   sudo systemctl status flask-app
   sudo systemctl status nginx
   ```
2. **Configure SSL (if domain provided):** The user data invokes Certbot automatically when both `domain_name` and `acme_email` are non-empty. To rerun:
   ```bash
   sudo certbot --nginx --non-interactive --agree-tos \
       -m admin@example.com -d app.example.com
   ```
3. **Seed database:**
   ```bash
   ssh -i key.pem ubuntu@<public_ip>  # or use SSM Session Manager
   mysql -h <private_instance_private_ip> -u appuser -p
   mysql> SOURCE /opt/flask-app/db/init.sql;
   ```
   Alternatively, log into the DB instance (via SSM/SSH) and execute `mysql < /home/ubuntu/devops-flask-project/db/init.sql`.
4. **Adjust MySQL security:** Run `mysql_secure_installation` on the DB host and rotate default credentials.

## 6. Testing Checklist & Commands
| Check | Command | Expected Outcome |
|-------|---------|------------------|
| Flask health | `curl -I https://app.example.com` | `200 OK` with TLS | 
| App HTTP fallback | `curl -I http://app.example.com` | Auto-redirect to HTTPS |
| App internal health | `curl https://app.example.com/` | JSON `{status: "ok"}` |
| DB connectivity (from Flask) | `mysql -h 10.0.2.x -u appuser -p` | Authenticated prompt |
| Port check | `nc -vz 10.0.2.x 3306` | `succeeded!` |
| App logs | `sudo journalctl -u flask-app -n 200` | No errors |
| Nginx logs | `sudo tail -f /var/log/nginx/flask_access.log` | Request entries |
| System logs | `sudo tail -f /var/log/cloud-init-output.log` | User-data status |

## 7. Troubleshooting Playbook
1. **Flask returns 502/504:**
   - Check `sudo systemctl status flask-app` and `journalctl -u flask-app`.
   - Ensure `/opt/flask-app/app/flask_app/.env` exists and DB creds are correct.
2. **MySQL connection errors:**
   - Verify SG rules: `aws ec2 describe-security-groups --group-ids <sg-db>`.
   - Confirm MySQL listening: `sudo ss -tlnp | grep 3306` on DB host.
   - Validate route tables: `aws ec2 describe-route-tables`.
3. **SSL renewal issues:**
   - Check `/etc/letsencrypt/renewal` configs.
   - Manually renew: `sudo certbot renew --dry-run`.
   - Review deploy hook logs in `/var/log/letsencrypt/`. 
4. **Connectivity debugging:**
   - From Flask host: `ping 10.0.2.x`, `traceroute 10.0.2.x`, `curl -v mysql://...`.
   - Confirm NAT Gateway in `available` state if private host needs outbound updates.
5. **SSM Session Manager (preferred ssh alternative):**
   ```bash
   aws ssm start-session --target <instance-id>
   ```

## 8. Failure Simulation Scenarios
1. **Database outage:**
   ```bash
   # On DB host or via SSM
   sudo systemctl stop mysql
   ```
   - Observe app errors via `/db-check` endpoint, then restart. 
2. **Network isolation:**
   ```bash
   sudo iptables -A INPUT -p tcp --dport 3306 -j DROP
   ```
   - Validate alerting/monitoring responses, then `iptables -F` to recover.
3. **Expired certificate:**
   - Modify `/etc/letsencrypt/live` contents (lab only) or prevent renewal, then run `certbot renew` to simulate incident response.

## 9. Operational Runbook
1. **Restart Flask application:**
   ```bash
   sudo systemctl restart flask-app
   sudo systemctl status flask-app
   ```
2. **Restart Nginx:** `sudo systemctl restart nginx`
3. **Rotate DB credentials:**
   - Update credentials in MySQL: `ALTER USER ... IDENTIFIED BY ...;`
   - Update `/etc/flask-app.env` on Flask host and `sudo systemctl restart flask-app`.
4. **Deploy code updates:**
   - Push changes to GitHub repo defined by `app_repo_url`.
   - SSH to Flask host: `cd /opt/flask-app && git pull && sudo systemctl restart flask-app`.
5. **Scale vertically:**
   - Update `flask_instance_type` or `mysql_instance_type` in Terraform variables.
   - `terraform apply` to recreate with new sizes (downtime expected; consider RDS/ALB for production).

## 10. Bonus Features & Notes
- **IP Allow-list:**
  - Set `ip_allowlist` Terraform variable to comma-separated CIDRs. The user data script generates `/etc/nginx/ip-allowlist.conf` with `allow/deny` directives. Empty list defaults to `allow all`.
- **Post-mortem Template:** See [`docs/postmortem_template.md`](./postmortem_template.md) for incident documentation.
- **Secret Hygiene:** Replace placeholder credentials in scripts/configs or use AWS Secrets Manager.
- **Production Recommendations:** Migrate to RDS, ALB + ACM, centralized logging (CloudWatch Logs), and parameterize secrets via SSM Parameter Store.

## 11. Hashtags for Progress Updates
`#getfitwithsagar #SRELife #DevOpsForAll`
