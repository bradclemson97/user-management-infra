#!/bin/bash
# First-time EC2 setup. Run once after provisioning.
set -euo pipefail

echo "=== Installing system packages ==="
dnf update -y
dnf install -y docker git nginx certbot python3-certbot-nginx

echo "=== Configuring Docker ==="
systemctl enable --now docker
usermod -aG docker ec2-user

echo "=== Installing Docker Compose v2 ==="
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
  | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)".*/\1/')
curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "=== Installing Java 17 (for building services) ==="
dnf install -y java-17-amazon-corretto-devel

echo "=== Installing Node.js 20 (for building UI) ==="
dnf install -y nodejs20 npm

echo "=== Installing Maven ==="
dnf install -y maven

echo "=== Enabling Nginx ==="
systemctl enable nginx

echo "=== Cloning repositories ==="
mkdir -p /opt/user-management
cd /opt/user-management

# Replace with your actual GitHub repo URLs
git clone https://github.com/bradclemson97/user-management-service.git       || true
git clone https://github.com/bradclemson97/access-control-manager.git         || true
git clone https://github.com/bradclemson97/keycloak-manager.git               || true
git clone https://github.com/bradclemson97/user-management-ui.git             || true
git clone https://github.com/bradclemson97/user-management-infra.git          || true

chown -R ec2-user:ec2-user /opt/user-management

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo ""
echo "=== Bootstrap complete ==="
echo "Next steps:"
echo "  1. Point DNS:  app.bradleyclemson.com -> ${PUBLIC_IP}"
echo "  2. Wait for DNS to propagate, then run:"
echo "       certbot --nginx -d app.bradleyclemson.com"
echo "  3. Copy nginx config:"
echo "       cp /opt/user-management/user-management-infra/nginx/app.conf /etc/nginx/conf.d/"
echo "       nginx -t && systemctl reload nginx"
echo "  4. Create /opt/user-management/user-management-infra/.env.prod from .env.prod.example"
echo "  5. Run: /opt/user-management/user-management-infra/scripts/deploy.sh"
