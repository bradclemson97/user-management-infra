# User Management — Infrastructure & Deployment

This repository contains everything needed to deploy the User Management application to AWS.

The live application is served at `https://app.bradleyclemson.com`, reachable via a redirect from `bradleyclemson.com/user-management`.

## Architecture

```
Internet
  │
  ├── bradleyclemson.com (Netlify portfolio)
  │     └── /user-management  ──301──►  https://app.bradleyclemson.com
  │
  └── app.bradleyclemson.com  (AWS EC2 — Elastic IP)
        │
        └── Nginx (SSL termination, Let's Encrypt)
              ├── /realms, /admin, /resources, /js  ──►  Keycloak   (127.0.0.1:9000)
              └── /                                 ──►  UI          (127.0.0.1:3000)
                                                           │
                                                    Docker bridge network
                                                           │
                                      ┌────────────────────┼────────────────────┐
                                   UMS :8080          ACM :8130           KM :8210
                                      └────────────────────┼────────────────────┘
                                                     PostgreSQL :5432
```

**EC2 instance:** `t3.small` (2 vCPU, 2 GB RAM) — approximately $15–20/month.

All six services (postgres, keycloak, ums, acm, km, ui) run in Docker containers on the same instance via `docker-compose.prod.yml`. The local `docker-compose.yml` (postgres + keycloak only) is unchanged and continues to be used for local development.

## Repository layout

```
user-management-infra/
├── docker-compose.yml          # Local development (postgres + keycloak only — unchanged)
├── docker-compose.prod.yml     # Production (all six services)
├── .env.prod.example           # Template for production secrets
├── nginx/
│   └── app.conf                # Nginx server block for app.bradleyclemson.com
├── scripts/
│   ├── bootstrap.sh            # Run once on a fresh EC2 instance
│   └── deploy.sh               # Run on every deployment
└── terraform/
    ├── main.tf                 # Provider configuration
    ├── variables.tf            # Input variables
    ├── vpc.tf                  # Uses the default VPC
    ├── security_groups.tf      # Ports 22, 80, 443
    ├── ec2.tf                  # EC2 instance + Elastic IP
    └── outputs.tf              # Prints public IP after apply
```

Each service repository also has a `Dockerfile` added at its root:

- `user-management-service/Dockerfile`
- `access-control-manager/Dockerfile` — builds `security-library` first, then the main app
- `keycloak-manager/Dockerfile`
- `user-management-ui/Dockerfile`

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5 installed locally
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured (`aws configure`)
- An EC2 key pair created in the `eu-west-2` region (AWS Console → EC2 → Key Pairs)
- Access to the DNS settings for `bradleyclemson.com`


How to create EC2 key pair:

1. Go to AWS Console → EC2 → Key Pairs → Create key pair
2. Give it a name (e.g. user-management)
3. Choose RSA and .pem format
4. Click Create — the file downloads automatically (e.g. user-management.pem)
5. Move it to your SSH directory and lock down its permissions:

mv ~/Downloads/user-management.pem ~/.ssh/                                                                                                                                           
chmod 400 ~/.ssh/user-management.pem

The chmod 400 is required — SSH refuses to use a key file that others can read.

---

## Initial deployment

### 1. Provision infrastructure with Terraform

```bash
cd terraform
terraform init
terraform apply \
  -var="key_name=your-ec2-key-pair-name" \
  -var="your_ip_cidr=$(curl -s ifconfig.me)/32"
```
Only update the your-ec2-key-pair-name variable to what you named your key-pair e.g. key_name=user-management.
curl ifconfig.me automatically find yours current public IP. 

Terraform creates:

| Resource | Detail |
|---|---|
| EC2 instance | `t3.small`, Amazon Linux 2023, 30 GB gp3 |
| Elastic IP | Static public IP, associated with the instance |
| Security group | Inbound: 22 (your IP only), 80, 443 (0.0.0.0/0) |

The `public_ip` output is the IP to use for DNS.

> To destroy all resources later: `terraform destroy`

---

### 2. Point DNS

In your domain registrar (or wherever `bradleyclemson.com` DNS is managed), add an **A record**:

```
app.bradleyclemson.com  →  <public_ip from terraform output>
```

Allow a few minutes for propagation before continuing.

---

### 3. Bootstrap the EC2 instance

SSH into the instance and run the bootstrap script. This installs Docker, Docker Compose, Nginx, Java, Node.js, Maven, and clones all service repositories.

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@<public_ip>
```
Update your-key.pem to the name of your .pem file e.g. user-management.pem
Update <public_ip> to `public_ip` from terraform output after running terraform apply above.
e.g. ssh_command = "ssh -i ~/.ssh/user-management.pem ec2-user@18.134.56.78".

Once connected, run:

```bash
sudo bash /opt/user-management/user-management-infra/scripts/bootstrap.sh
```

> The script clones all repos into `/opt/user-management/`. If the repositories are private, configure SSH deploy keys or a GitHub personal access token first.

---

### 4. Issue an SSL certificate

After DNS has propagated, issue a Let's Encrypt certificate and install the Nginx configuration:

```bash
sudo certbot --nginx -d app.bradleyclemson.com

sudo cp /opt/user-management/user-management-infra/nginx/app.conf /etc/nginx/conf.d/app.conf
sudo nginx -t
sudo systemctl reload nginx
```

Certbot will automatically renew the certificate via a cron job. Test renewal at any time with:

```bash
sudo certbot renew --dry-run
```

---

### 5. Create the production secrets file

```bash
cd /opt/user-management/user-management-infra
cp .env.prod.example .env.prod
nano .env.prod   # fill in all values
```

| Variable | Description |
|---|---|
| `POSTGRES_PASSWORD` | Database password |
| `KEYCLOAK_ADMIN` | Keycloak admin username (e.g. `admin`) |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password |
| `KEYCLOAK_MANAGER_SECRET` | Client secret for `system-manager-service` (set this after step 6) |
| `KEYCLOAK_CLIENT_SECRET` | Client secret for `user-management-ui` (set this after step 6) |
| `SESSION_SECRET` | Random string for Express session signing — generate with `openssl rand -base64 32` |

> **Never commit `.env.prod` to git.** It is listed in `.gitignore`.

---

### 6. Start all services

```bash
cd /opt/user-management/user-management-infra
sudo ./scripts/deploy.sh
```

The first run builds all Docker images from source (this takes several minutes). Subsequent runs are faster.

Check that all containers are running:

```bash
docker ps
```

Expected containers: `userdb`, `keycloak`, `ums`, `acm`, `km`, `ui`.

---

### 7. Configure Keycloak (first boot only)

Open `https://app.bradleyclemson.com/admin` and log in with the admin credentials from `.env.prod`.

Follow the same realm setup steps documented in the main project README (sections 9.1–10.0) to recreate the `system` realm, clients, groups, and superuser. The key difference from local setup is that all redirect URIs should use `https://app.bradleyclemson.com` instead of `http://localhost:3000`.

After creating the `system-manager-service` and `user-management-ui` clients, copy their client secrets back into `.env.prod` and redeploy:

```bash
./scripts/deploy.sh
```

---

### 8. Verify

Navigate to `https://app.bradleyclemson.com` — the login page should appear.

Visiting `bradleyclemson.com/user-management` will redirect to `https://app.bradleyclemson.com` via the Netlify redirect rule added to the portfolio's `netlify.toml`.

---

## Subsequent deployments

To deploy updated code, run the deploy script from the EC2 instance:

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@<public_ip>
cd /opt/user-management/user-management-infra
sudo ./scripts/deploy.sh
```

The script:
1. Pulls the latest commits from all five repositories
2. Rebuilds all Docker images in parallel
3. Restarts containers with zero-downtime (replace strategy)

---

## Useful commands

```bash
# View logs for a specific service
docker logs ums -f
docker logs acm -f
docker logs km -f
docker logs ui -f
docker logs keycloak -f

# Restart a single service
docker-compose -f docker-compose.prod.yml --env-file .env.prod restart ums

# Stop everything
docker-compose -f docker-compose.prod.yml --env-file .env.prod down

# Open a shell inside a container
docker exec -it ums sh

# Connect to the database
docker exec -it userdb psql -U postgres -d userdb
```

---

## Local development

Local development is unchanged. From the infra repo root:

```bash
docker-compose up -d   # starts postgres and keycloak only
```

Then start each service locally as before (IntelliJ / `mvn spring-boot:run` / `npm run dev`).

---

## Troubleshooting

**Keycloak fails to start**

Check logs with `docker logs keycloak`. The most common cause on first boot is the database not being ready — the health check retries for up to 90 seconds, so give it time.

**Spring services fail JWT validation**

The `extra_hosts: ["app.bradleyclemson.com:host-gateway"]` entry in `docker-compose.prod.yml` is critical — it lets containers resolve `app.bradleyclemson.com` through the host's Nginx (which proxies to Keycloak) rather than going to the public internet. If JWT validation fails, verify this is present and that Nginx is running on the host.

**SSL certificate not renewing**

Certbot installs a cron job automatically. Check with `sudo systemctl status certbot.timer` or `sudo crontab -l`.

**Out of disk space**

Old Docker images accumulate over time. Clean up with:

```bash
docker image prune -f
docker volume prune -f   # WARNING: removes unused volumes — do not use if postgres_data is unmounted
```

## reset-users.sh 

**Local**

Run from the user-management-infra directory — the defaults match your local docker-compose setup:

```bash
cd /path/to/user-management-infra                                                                                                                                                    
./scripts/reset-users.sh
```

**Production**

SSH into the server first, then run the script with your production credentials. The KC_URL stays as the internal container URL — kcadm.sh runs inside the container so it doesn't go
through Nginx.

# 1. SSH into the server
```bash
ssh user@app.bradleyclemson.com
```

# 2. Navigate to the infra repo
```bash
cd /path/to/user-management-infra
```

# 3. Run with production credentials
```bash
KC_ADMIN=admin \                                                                                                                                                                     
KC_ADMIN_PASSWORD=<your-keycloak-admin-password> \                                                                                                                                   
KC_URL=http://localhost:8080 \                                                                                                                                                       
./scripts/reset-users.sh
```
If the infra repo isn't on the server, copy just the script up first:
```bash
scp scripts/reset-users.sh user@app.bradleyclemson.com:/tmp/reset-users.sh                                                                                                           
ssh user@app.bradleyclemson.com "chmod +x /tmp/reset-users.sh && KC_ADMIN=admin KC_ADMIN_PASSWORD=<password> /tmp/reset-users.sh"
```
The Keycloak admin password is whatever you set as KEYCLOAK_ADMIN_PASSWORD in your production .env file on the server