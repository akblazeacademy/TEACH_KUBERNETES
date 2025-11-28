#!/bin/bash
set -e

DOMAIN="akblazeacademy.net"

# Kubernetes Node IPs
NODE1="172.16.0.4"
NODE2="172.16.0.5"

# Working HTTP NodePort for ingress-nginx
NODEPORT=32407

echo "=========================================="
echo " CLEANING OLD NGINX CONFIGS COMPLETELY"
echo "=========================================="

# Remove ALL references to ingress_nodes
FILES=$(sudo grep -Rl "ingress_nodes" /etc/nginx || true)

if [ ! -z "$FILES" ]; then
    echo "Removing old files:"
    echo "$FILES"
    echo "$FILES" | sudo xargs rm -f
fi

# Clean sites-enabled & sites-available fully
sudo rm -f /etc/nginx/sites-enabled/k8s-ingress.conf
sudo rm -f /etc/nginx/sites-available/k8s-ingress.conf

# Clean conf.d completely if any leftover exist
sudo rm -f /etc/nginx/conf.d/k8s-ingress.conf || true

echo "=========================================="
echo " INSTALLING CERTBOT & NGINX PLUGIN"
echo "=========================================="

sudo apt update -y
sudo apt install -y certbot python3-certbot-nginx

echo "=========================================="
echo " CREATING NEW NGINX CONFIG"
echo "=========================================="

sudo bash -c "cat >/etc/nginx/sites-available/k8s-ingress.conf" <<EOF
upstream ingress_nodes {
    server ${NODE1}:${NODEPORT};
    server ${NODE2}:${NODEPORT};
}

server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://ingress_nodes;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

echo "=========================================="
echo " ENABLING NEW SITE"
echo "=========================================="

sudo ln -sf /etc/nginx/sites-available/k8s-ingress.conf /etc/nginx/sites-enabled/k8s-ingress.conf

echo "=========================================="
echo " TESTING NGINX CONFIG"
echo "=========================================="

sudo nginx -t

echo "=========================================="
echo " RESTARTING NGINX"
echo "=========================================="

sudo systemctl restart nginx

echo "=========================================="
echo " OBTAINING SSL CERTIFICATE"
echo "=========================================="

sudo certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos -m admin@${DOMAIN}

echo "=========================================="
echo " SSL SETUP COMPLETE"
echo "=========================================="
echo "Test URLs:"
echo "  https://${DOMAIN}/app1"
echo "  https://${DOMAIN}/app2"

