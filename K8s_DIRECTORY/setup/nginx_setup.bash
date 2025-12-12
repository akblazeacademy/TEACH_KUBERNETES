#!/bin/bash

# Install nginx
sudo apt update -y
sudo apt install -y nginx

# Create custom HTML page
sudo bash -c 'cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
<title>vm1</title>
</head>
<body style="font-family: Arial; text-align: center; margin-top: 50px;">
<h1>Hello, you hit vm1 on port 30080</h1>
</body>
</html>
EOF'

# Change nginx to listen on port 30080
sudo sed -i 's/listen 80 default_server;/listen 30080 default_server;/g' /etc/nginx/sites-available/default
sudo sed -i 's/listen \[::\]:80 default_server;/listen [::]:30080 default_server;/g' /etc/nginx/sites-available/default

# Restart nginx
sudo systemctl restart nginx

echo "Nginx running on port 30080 – visit http://<server-ip>:30080"
