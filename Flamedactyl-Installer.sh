#!/bin/bash


banner(){
cat << "EOF"
███████ ██       █████  ███    ███ ███████ ██████   █████   ██████ ████████ ██    ██ ██      
██      ██      ██   ██ ████  ████ ██      ██   ██ ██   ██ ██         ██     ██  ██  ██      
█████   ██      ███████ ██ ████ ██ █████   ██   ██ ███████ ██         ██      ████   ██      
██      ██      ██   ██ ██  ██  ██ ██      ██   ██ ██   ██ ██         ██       ██    ██      
██      ███████ ██   ██ ██      ██ ███████ ██████  ██   ██  ██████    ██       ██    ███████ 
                                                                                             
EOF
}


panel_install(){

#!/bin/bash

# Default DB values
panel_db_host="127.0.0.1"
panel_db_name="panel"
panel_db_user="flamedactyl"
panel_db_password="flamedactyl"

user_email=""
user_username=""
user_firstname=""
user_lastname=""
user_password=""

# Function to prompt with default
prompt() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"

    read -p "$prompt_text [$default_value]: " input
    if [[ -n "$input" ]]; then
        eval "$var_name=\"$input\""
    else
        eval "$var_name=\"$default_value\""
    fi
}

# Function for required text (non-empty)
prompt_required() {
    local var_name="$1"
    local prompt_text="$2"
    local input=""
    while [[ -z "$input" ]]; do
        read -p "$prompt_text: " input
    done
    eval "$var_name=\"$input\""
}

# Function for password with length check
prompt_password() {
    local var_name="$1"
    local prompt_text="$2"
    local input=""
    while true; do
        read -sp "$prompt_text: " input
        echo
        if [[ ${#input} -lt 8 ]]; then
            echo "❌ Password must be at least 8 characters."
        else
            break
        fi
    done
    eval "$var_name=\"$input\""
}

# Prompt for DB config
prompt panel_db_host "Enter database host" "$panel_db_host"
prompt panel_db_name "Enter database name" "$panel_db_name"
prompt panel_db_user "Enter database user" "$panel_db_user"
prompt panel_db_password "Enter database password" "$panel_db_password"

# Prompt for user account
prompt_required user_email "Enter admin email"
prompt_required user_username "Enter admin username"
prompt_required user_firstname "Enter admin first name"
prompt_required user_lastname "Enter admin last name"
prompt_password user_password "Enter admin password (min 8 chars)"

# Display summary
echo
echo "✅ Configuration Summary:"
echo "DB Host: $panel_db_host"
echo "DB Name: $panel_db_name"
echo "DB User: $panel_db_user"
echo "DB Password: (hidden)"
echo "Admin Email: $user_email"
echo "Admin Username: $user_username"
echo "Admin Name: $user_firstname $user_lastname"
echo "Admin Password: (hidden)"


 # Add "add-apt-repository" command
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

# Add additional repositories for PHP (Ubuntu 22.04)
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php

# Add Redis official APT repository
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list

# Update repositories list
apt update

# Install Dependencies
apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

mysql -u root <<EOF
CREATE USER '$panel_db_user'@'127.0.0.1' IDENTIFIED BY '$panel_db_password';
CREATE DATABASE $panel_db_name;
GRANT ALL PRIVILEGES ON $panel_db_name.* TO '$panel_db_user'@'127.0.0.1' WITH GRANT OPTION;
EXIT;
EOF

cp .env.example .env
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

# Only run the command below if you are installing this Panel for
# the first time and do not have any Pterodactyl Panel data in the database.
php artisan key:generate --force

php artisan p:environment:setup <<EOF
$user_email
$panel_url
$panel_timezone
redis
redis
redis
yes
yes




EOF

php artisan p:environment:database <<EOF
$panel_db_host
3306
$panel_db_name
$panel_db_user
$panel_db_password
EOF

php artisan migrate --seed --force
php artisan p:user:make <<EOF
yes
$user_email
$user_username
$user_firstname
$user_lastname
$user_password
EOF

chown -R www-data:www-data /var/www/pterodactyl/*
chown -R nginx:nginx /var/www/pterodactyl/*
chown -R apache:apache /var/www/pterodactyl/*

mkdir -p /etc/systemd/system/
# Create the systemd service file
cat <<EOF > "$SERVICE_FILE"
# Pterodactyl Queue Worker File
# ----------------------------------

[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
# On some systems the user and group might be different.
# Some systems use \`apache\` or \`nginx\` as the user and group.
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable + start the service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable pteroq.service
systemctl start pteroq.service

echo "✅ pteroq.service created and started."


sudo systemctl enable --now redis-server
sudo systemctl enable --now pteroq.service


rm /etc/nginx/sites-enabled/default


CONFIG_FILE="/etc/nginx/sites-available/pterodactyl.conf"

# Check if run as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Please run this script as root."
   exit 1
fi

# Create Nginx config
cat << 'EOF' > "$CONFIG_FILE"
server {
    # Replace the example <domain> with your domain name or IP address
    listen 80;
    server_name <domain>;
    return 301 https://$server_name$request_uri;
}

server {
    # Replace the example <domain> with your domain name or IP address
    listen 443 ssl http2;
    server_name <domain>;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    # SSL Configuration - Replace the example <domain> with your domain
    ssl_certificate /etc/letsencrypt/live/<domain>/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<domain>/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    # See https://hstspreload.org/ before uncommenting the line below.
    # add_header Strict-Transport-Security "max-age=15768000; preload;";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

echo "✅ Nginx config created at $CONFIG_FILE"

sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
sudo systemctl restart nginx
}

wings_install() {
# Ask whether to install Wings with SSL
read -p "Do you want to install Wings with SSL? (yes/no): " install_ssl

if [[ "$install_ssl" == "yes" ]]; then
    echo "🚀 Installing Wings with SSL for domain: $domain"
    echo "Installing certbot..."
    sudo apt install -y certbot

    # Ask for domain input
    read -p "Enter your domain: " domain
    echo "You entered: $domain"
    certbot certonly --standalone -d "$domain"
    echo "✅ SSL certificates have been requested and saved by certbot."
else
    echo "⏭️ Skipping SSL setup for Wings."
fi


echo "Installing Docker"
curl -sSL https://get.docker.com/ | CHANNEL=stable bash
sudo systemctl enable --now docker

echo "Installing wings"
sudo mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
sudo chmod u+x /usr/local/bin/wings
mkdir -p /etc/systemd/system
#!/bin/bash

SERVICE_FILE="/etc/systemd/system/wings.service"

# Ensure you’re root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Please run this script as root."
    exit 1
fi

# Write the service content
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/usr/local/bin
ExecStart=/usr/local/bin/wings
Restart=on-failure
LimitNOFILE=4096
TimeoutStartSec=0
SyslogIdentifier=wings

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd to recognize the new service
systemctl daemon-reload

echo "Wings.service created at $SERVICE_FILE"

echo "Wings Installed Successfully"


echo "
Now add the configuration command from the panel node config.
Then run 
systemctl enable --now wings 
or do 
sudo wings 
to test it
"

}


blueprint_install(){
echo "Installing blueprint please wait..."
cd /var/www/pterodactyl
sudo apt-get install -y ca-certificates curl gnupg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y nodejs
npm i -g yarn
cd /var/www/pterodactyl
yarn
apt install -y zip unzip git curl wget
wget "$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest | grep 'browser_download_url' | cut -d '"' -f 4)" -O release.zip
mv release.zip /var/www/pterodactyl/release.zip
cd /var/www/pterodactyl
unzip release.zip
touch /var/www/pterodactyl/.blueprintrc
echo \
'WEBUSER="www-data";
OWNERSHIP="www-data:www-data";
USERSHELL="/bin/bash";' >> /var/www/pterodactyl/.blueprintrc
chmod +x blueprint.sh
bash blueprint.sh
echo "Blueprint installed successfully!"
}

panel_fixer() {
  echo "🛠️ Running Panel Fixer..."
  bash <(curl -sSL https://gist.githubusercontent.com/aislxflames/33d15dce8e832913f4402c9e15a857cf/raw/f7c6bd7982c492bbbad817fb513e6fcf7a77bdb0/pterodactyl-fixer.sh)
}


uninstall_panel() {
  echo "⚠️ Uninstalling Panel..."
  rm -rf /var/www/pterodactyl
  rm -f /etc/nginx/sites-enabled/pterodactyl.conf
  rm -f /etc/nginx/sites-available/pterodactyl.conf
  systemctl disable --now pteroq.service
  rm -f /etc/systemd/system/pteroq.service
  systemctl reload nginx
  echo "✅ Panel uninstalled."
}

uninstall_wings() {
  echo "⚠️ Uninstalling Wings..."
  systemctl disable --now wings
  rm -f /usr/local/bin/wings
  rm -f /etc/systemd/system/wings.service
  systemctl daemon-reload
  echo "✅ Wings uninstalled."
}

uninstall_blueprint() {
  echo "⚠️ Uninstalling Blueprint..."
  cd /var/www/pterodactyl
  rm -f release.zip
  rm -rf blueprint.sh .blueprintrc resources/scripts resources/styles
  echo "✅ Blueprint files removed."
}



main_menu() {
  while true; do
    clear
    banner
    echo "==== Main Menu ===="
    echo "1) Install Panel"
    echo "2) Install Wings"
    echo "3) Install Blueprint"
    echo "4) Run Panel Fixer"
    echo "5) Uninstall Panel"
    echo "6) Uninstall Wings"
    echo "7) Uninstall Blueprint"
    echo "8) Exit"
    echo "===================="
    read -p "Enter your choice: " choice

    case "$choice" in
      1) panel_install ;;
      2) wings_install ;;
      3) blueprint_install ;;
      4) panel_fixer ;;
      5) uninstall_panel ;;
      6) uninstall_wings ;;
      7) uninstall_blueprint ;;
      8) echo "Goodbye!"; exit 0 ;;
      *) echo "❌ Invalid option. Please try again."; sleep 1 ;;
    esac
  done
}

main_menu




