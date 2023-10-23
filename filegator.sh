#!/usr/bin/env bash

LOGFILE="/home/filegator_logfile.log"

function log () {
    local message=$1
    echo "$(date): $message" >> $LOGFILE
}

ip_server=$(echo $SSH_CONNECTION | awk '{print $3}')
host=$(hostname)

function password_root() {
clear
  echo ""
  echo -n "Enter ROOT password: " >/dev/tty
  stty -echo
  IFS= read -r -d '' -n 1 char
  password=""
  while [[ $char != $'\0' && $char != $'\n' ]]; do
    password+="$char"
    echo -n "*"
    IFS= read -r -d '' -n 1 char
  done
  stty echo
  echo ""
}



function hash_password() {
    log "Starting hash_password function"

    if [[ -d /usr/share/filegator/ ]]; then
        log "Directory /usr/share/filegator/ found"

        password_hash=$password
        salt="$2y$10$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 22)"
        hash=$(php -r '
           require_once "/usr/share/filegator/backend/Utils/PasswordHash.php";
           $password = "'"$password_hash"'";
           $salt = "'"$salt"'";
           $hash = crypt($password, $salt);
           echo $hash;
       ')

        log "Password has been hashed: **********"

        wget -q http://$ip_server/filegator/
        log "Made request to http://$ip_server/filegator/"

        sleep 1

        sed -i '0,/"password":/{s#"password":"[^"]*"#"password":"'"$hash"'"#}' /usr/share/filegator/private/users.json
        log "Password in /usr/share/filegator/private/users.json has been updated"
    else
        log "Directory /usr/share/filegator/ not found"
        echo ""
    fi

    log "Ending hash_password function"
}

function install_filegator() {
    log "Starting install_filegator function"

        echo ""

    msg "${ORANGE}[Progress]${NOFORMAT} Installing Filegator (Apache + Nginx)..."

        echo ""

    # Check PHP version
    log "Checking PHP version"
    PHP_VERSION=$(php -r "echo PHP_VERSION;")
    REQUIRED_PHP_VERSION="7.2.5"

    if [ "$(printf '%s\n' "$REQUIRED_PHP_VERSION" "$PHP_VERSION" | sort -V | head -n1)" != "$REQUIRED_PHP_VERSION" ]; then
        log "Filegator requires PHP $REQUIRED_PHP_VERSION or later. Your current version is $PHP_VERSION."
        echo "Filegator requires PHP $REQUIRED_PHP_VERSION or later. Your current version is $PHP_VERSION."
        return
    fi

    if [[ -d /usr/share/filegator ]]; then
        log "Filegator is already installed."
        echo "Filegator is already installed."
        echo ""

    else
        log "Filegator is not installed. Starting installation process..."
        echo "Filegator is not installed. Installing now..."
        echo ""

        for attempt in {1..3}; do
            log "Downloading Filegator, attempt $attempt"
            wget https://github.com/filegator/static/raw/master/builds/filegator_latest.zip -P /usr/share/ &> /dev/null
            if [ $? -eq 0 ]; then
                log "Filegator download successful on attempt $attempt"
                break
            fi
            log "Attempt $attempt failed. Retrying in 5 seconds..."
            echo "Attempt $attempt failed. Retrying in 5 seconds..."
            sleep 5
        done

        log "Unzipping and setting permissions for Filegator"
        unzip -o /usr/share/filegator_latest.zip -d /usr/share/ >/dev/null
        chown -R admin:admin /usr/share/filegator && chmod -R 775 /usr/share/filegator >/dev/null && chmod +rx /home/backup >/dev/null

        # Make config for Apache
        log "Configuring Apache for Filegator"
        if [[ -f /etc/httpd/conf.d/filegator.conf ]]; then
            log "Removing existing Apache config for Filegator"
            sudo rm /etc/httpd/conf.d/filegator.conf
        fi
        touch /etc/httpd/conf.d/filegator.conf
        tee -a /etc/httpd/conf.d/filegator.conf << END >/dev/null
        Alias /filegator /usr/share/filegator

        <Directory /usr/share/filegator>
            Order Deny,Allow
            Deny from All
            Allow from All
        </Directory>

        <Directory /usr/share/filegator/dist>
            Order Deny,Allow
            Deny from All
            Allow from All
        </Directory>
END
        log "Apache configuration for Filegator has been set"

        # Change root directory configuration.php
        log "Updating root directory in configuration.php for Filegator"
        sudo sed -i "s#__DIR__\.'/repository'#'/home'#g" /usr/share/filegator/configuration.php

        log "Restarting httpd service"
        systemctl restart httpd
    fi

    log "Making a test request to Filegator"
    wget -q http://$ip_server/filegator/

    log "Ending install_filegator function"
}

function install_filegator_fpm() {
    log "Starting install_filegator_fpm function"

    echo ""
    msg "${ORANGE}[Progress]${NOFORMAT} Installing Filegator (Nginx+PHP-FPM)..."
    echo ""

    # Check PHP version
    log "Checking PHP version"
    PHP_VERSION=$(php -r "echo PHP_VERSION;")
    REQUIRED_PHP_VERSION="7.2.5"

    if [ "$(printf '%s\n' "$REQUIRED_PHP_VERSION" "$PHP_VERSION" | sort -V | head -n1)" != "$REQUIRED_PHP_VERSION" ]; then
        log "Filegator requires PHP $REQUIRED_PHP_VERSION or later. Your current version is $PHP_VERSION."
        echo "Filegator requires PHP $REQUIRED_PHP_VERSION or later. Your current version is $PHP_VERSION."
        return
    fi

    if [[ -d /usr/share/filegator ]]; then
        log "Filegator is already installed."
        echo "Filegator is already installed."
        echo ""
    else
        log "Filegator is not installed. Starting installation process..."
        echo "Filegator is not installed. Installing now..."
        echo ""

        for attempt in {1..3}; do
            log "Downloading Filegator, attempt $attempt"
            wget https://github.com/filegator/static/raw/master/builds/filegator_latest.zip -P /usr/share/ &> /dev/null
            if [ $? -eq 0 ]; then
                log "Filegator download successful on attempt $attempt"
                break
            fi
            log "Attempt $attempt failed. Retrying in 5 seconds..."
            echo "Attempt $attempt failed. Retrying in 5 seconds..."
            sleep 5
        done

        log "Unzipping and setting permissions for Filegator"
        unzip -o /usr/share/filegator_latest.zip -d /usr/share/ &>/dev/null && chown -R root:admin /usr/share/filegator && chmod -R 775 /usr/share/filegator

        log "Creating Nginx configuration for Filegator, phpMyAdmin, and Roundcube"
        touch /etc/nginx/conf.d/filegator-phpmyadmin-roundcube.conf
        tee -a /etc/nginx/conf.d/filegator-phpmyadmin-roundcube.conf << EOF >/dev/null
server {
    listen $ip_server:80;
    server_name _;

    root /usr/share/filegator;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location /filegator {
        alias /usr/share/filegator;

        location ~ \.php\$ {
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
            fastcgi_pass 127.0.0.1:9000;
        }
    }

    location /phpmyadmin {
        alias /usr/share/phpMyAdmin;

        location ~ \.php\$ {
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
            fastcgi_pass 127.0.0.1:9000;
        }
    }

    location /phpMyAdmin {
        alias /usr/share/phpMyAdmin;

        location ~ \.php\$ {
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
            fastcgi_pass 127.0.0.1:9000;
        }
    }

    location /roundcubemail {
       index index.php;
       alias /usr/share/roundcubemail;

         location ~ \.php\$ {
         include fastcgi_params;
         fastcgi_param SCRIPT_FILENAME \$request_filename;
         fastcgi_pass 127.0.0.1:9000;
    }
}
    location /webmail {
         index index.php;
         alias /usr/share/roundcubemail;

            location ~ \.php\$ {
                include fastcgi_params;
                fastcgi_param SCRIPT_FILENAME \$request_filename;
                fastcgi_pass 127.0.0.1:9000;
    }
}

    include /etc/nginx/conf.d/filegator.inc*;
}

EOF

        log "Restarting Nginx and php-fpm services"
        systemctl restart nginx && systemctl restart php-fpm

        log "Updating root directory in configuration.php for Filegator"
        sed -i "s#__DIR__\.'/repository'#'/home'#g" /usr/share/filegator/configuration.php

        log "Modifying user groups and setting permissions"
        usermod -a -G admin apache && chmod +rx /home/admin && chmod +rx /home/backup && chmod -R 775 /home/admin/web && chown -R apache:apache /usr/share/filegator/private/logs && chown -R apache:apache /usr/share/filegator/repository
    fi

    log "Making a test request to Filegator"
    wget -q http://$ip_server/filegator/

    log "Ending install_filegator_fpm function"
}


function info_filegator() {
    log "Starting info_filegator function"

    clear

    # Check IP accessibility
    log "Checking IP accessibility for FileGator"
    IP_CHECK_HTTP=$(curl --insecure -I -L http://$ip_server/filegator/ 2>/dev/null | head -n 1 | cut -d$' ' -f2)

    # If IP accessibility is confirmed
    if [[ "$IP_CHECK_HTTP" == 200 ]]; then
        log "FileGator is accessible at http://$ip_server/filegator/"
        echo " "
        for i in {17..21} {21..17} ; do echo -en "\e[38;5;${i}m#####\e[0m" ; done ; echo
        echo -e ""
        msg "The FileGator has been installed. The credentials:"
        echo ""
        msg "${ORANGE}File Manager:"
        msg "http://$ip_server/filegator/"
        msg "User: admin"
        msg "Password: $password\n"
        msg "${ORANGE}Applications:${NOFORMAT}"
        msg "${GREEN}[Ok]${NOFORMAT} Filegator http://$ip_server/filegator/"
        for i in {17..21} {21..17} ; do echo -en "\e[38;5;${i}m#####\e[0m" ; done ; echo
        echo " "
    else
        log "Failed to get a response when accessing FileGator at http://$ip_server/filegator/"
        msg "${RED}[Error]${NOFORMAT} Failed to get a response when accessing FileGator (http://$ip_server/filegator/), most likely an error occurred during installation."
    fi

    log "Saving FileGator credentials to /root/.filegator_data"
    echo -e "username = admin\npassword = $password" > /root/.filegator_data

    log "Ending info_filegator function"
}

function filegator_centos() {
    log "Starting filegator_centos function"

    clear

    # Check PHP version
    log "Checking PHP version"
    PHP_VERSION=$(php -r "echo PHP_VERSION;")
    REQUIRED_PHP_VERSION="7.2.5"

    if [ "$(printf '%s\n' "$REQUIRED_PHP_VERSION" "$PHP_VERSION" | sort -V | head -n1)" != "$REQUIRED_PHP_VERSION" ]; then
        log "Filegator requires PHP $REQUIRED_PHP_VERSION or later. Your current version is $PHP_VERSION."
        msg "${RED}[Error]${NOFORMAT} Filegator requires PHP $REQUIRED_PHP_VERSION or later. Your current version is $PHP_VERSION."
        return
    fi

    # Check for Apache and Nginx
    log "Checking for running Apache and Nginx services"
    APACHE_RUNNING=$(ps aux | grep httpd | grep -v grep)
    NGINX_RUNNING=$(ps aux | grep nginx | grep -v grep)
    PHP_FPM_RUNNING=$(ps aux | grep php-fpm | grep -v grep)

    if [[ ! -z "$APACHE_RUNNING" && ! -z "$NGINX_RUNNING" ]]; then
        log "Detected Apache + Nginx configuration"
        msg "${ORANGE}Detected:${NOFORMAT} Apache + Nginx"
        password_root ; install_filegator ; hash_password ;
    elif [[ ! -z "$NGINX_RUNNING" && ! -z "$PHP_FPM_RUNNING" ]]; then
        log "Detected Nginx + PHP-FPM configuration"
        msg "${ORANGE}Detected:${NOFORMAT} Nginx + PHP-FPM"
        password_root ; install_filegator_fpm ; hash_password ;
    else
        log "No supported configurations detected. Please ensure either Apache + Nginx or Nginx + PHP-FPM are running."
        msg "${RED}[Error]${NOFORMAT} No supported configurations detected. Please ensure either Apache + Nginx or Nginx + PHP-FPM are running." && exit 0;
    fi

    log "Ending filegator_centos function"
}


#function filegator_centos() {
#clear
#  msg "${ORANGE} 1) CentOS 7:${NOFORMAT} Apache + Nginx"
#  msg "${ORANGE} 2) CentOS 7:${NOFORMAT} Nginx + PHP-FPM"
#
#    echo -e "Choose 1-2 option to install: " && read type_filegator
#
#    case $type_filegator in
#
#          1)
#          password_root ; install_filegator ; hash_password ;
#
#          ;;
#
#          2)
#          password_root ; install_filegator_fpm ; hash_password
#
#          ;;
#
#          *)
#
#          msg "${RED}[Error]${NOFORMAT} No valid options have been selected. Reload the script and try again." && exit 0;
#
#          ;;
#
#          esac
#}

function setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}
function msg() {
  echo >&2 -e "${1-}"
}

setup_colors ; filegator_centos ; info_filegator