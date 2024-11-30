#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

echo "Updating and installing basic dependencies..."
apt update -y
apt upgrade -y
apt install -y curl sudo gnupg lsb-release wget apt-transport-https

echo "Installing Docker..."
curl -fsSL https://get.docker.com | bash
systemctl start docker
systemctl enable docker

echo "Installing necessary dependencies for Pterodactyl Panel and Wings..."
apt install -y php php-cli php-fpm php-mbstring php-curl php-xml php-bcmath php-zip php-sqlite3 php-mysql unzip redis-server

echo "Installing Cloudflared (Cloudflare Tunnel)..."
curl -fsSL https://pkg.cloudflare.com/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflare-mainline/deb stable main" | sudo tee /etc/apt/sources.list.d/cloudflare-mainline.list
apt update -y
apt install -y cloudflare-warp

echo "Setting up Cloudflare Tunnel..."
read -p "Enter your Cloudflare Tunnel subdomain (e.g., panel.yourdomain.com): " subdomain
read -p "Enter the email associated with your Cloudflare account: " cf_email

cloudflared login
cloudflared tunnel create pterodactyl-tunnel
cloudflared tunnel route dns pterodactyl-tunnel $subdomain

echo "Starting Cloudflare Tunnel..."
cloudflared tunnel run pterodactyl-tunnel &

echo "Installing Pterodactyl Panel..."
echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

cd /var/www
git clone https://github.com/pterodactyl/panel.git
cd panel
git checkout $(curl -s https://api.github.com/repos/pterodactyl/panel/releases/latest | jq -r '.tag_name')

chown -R www-data:www-data /var/www/panel
chmod -R 755 /var/www/panel

cp .env.example .env

composer install --no-dev --optimize-autoloader

php artisan key:generate

echo "Setting up the MySQL database for Pterodactyl..."
read -p "Enter your MySQL root password: " mysql_root_pass
mysql -u root -p$mysql_root_pass -e "CREATE DATABASE pterodactyl; CREATE USER 'pterodactyl'@'localhost' IDENTIFIED BY 'your_password_here'; GRANT ALL PRIVILEGES ON pterodactyl.* TO 'pterodactyl'@'localhost'; FLUSH PRIVILEGES;"

sed -i 's/DB_PASSWORD=/.*/DB_PASSWORD=your_password_here/g' .env

php artisan migrate --seed --force

php artisan serve --host=0.0.0.0 --port=80 &

echo "Installing Pterodactyl Wings Daemon..."
curl -Lo wings https://github.com/pterodactyl/wings/releases/download/v1.0.0-beta.5/wings-linux-amd64
chmod +x wings
mv wings /usr/local/bin/wings

cat <<EOL > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service

[Service]
ExecStart=/usr/local/bin/wings
WorkingDirectory=/var/lib/pterodactyl
Restart=always
User=pterodactyl
Group=pterodactyl
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOL

systemctl start wings
systemctl enable wings

echo "Installation complete! Here are the next steps:"
echo "1. The Pterodactyl Panel should be accessible at: http://$subdomain"
echo "2. Log in to the Pterodactyl Panel using your admin account."
echo "3. You can configure and manage your game servers in the panel."
echo "4. Wings Daemon is now running and managing game servers."
