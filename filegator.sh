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
  echo "The password is: $password"
}



function hash_password() {
if [[ -d /usr/share/filegator/ ]]; then
  password_hash=$password
  salt="$2y$10$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 22)"
  hash=$(php -r '
           require_once "/usr/share/filegator/backend/Utils/PasswordHash.php";
           $password = "'"$password_hash"'";
           $salt = "'"$salt"'";
           $hash = crypt($password, $salt);
           echo $hash;
       ')

  wget -q http://$ip_server/filegator/

  sleep 1

  sed -i '0,/"password":/{s#"password":"[^"]*"#"password":"'"$hash"'"#}' /usr/share/filegator/private/users.json
else
  echo ""
fi
}

function install_filegator() {

msg "${ORANGE}[Progress]${NOFORMAT} Installing Filegator (Apache + Nginx)..."

  # Check PHP version
  PHP_VERSION=$(php -r "echo PHP_VERSION;")
  REQUIRED_PHP_VERSION="7.2.5"

  if [ "$(printf '%s\n' "$REQUIRED_PHP_VERSION" "$PHP_VERSION" | sort -V | head -n1)" != "$REQUIRED_PHP_VERSION" ]; then
    echo "Filegator requires PHP $REQUIRED_PHP_VERSION or later. Your current version is $PHP_VERSION."
    return
  fi

  if [[ -d /usr/share/filegator ]]; then
    echo "Filegator is already installed."
  else
    echo "Filegator is not installed. Installing now..."

    for attempt in {1..3}; do
      wget https://github.com/filegator/static/raw/master/builds/filegator_latest.zip -P /usr/share/
      if [ $? -eq 0 ]; then
        break
      fi
      echo "Attempt $attempt failed. Retrying in 5 seconds..."
      sleep 5
    done

    unzip -o /usr/share/filegator_latest.zip -d /usr/share/ >/dev/null
    chown -R admin:admin /usr/share/filegator &&  chmod -R 775 /usr/share/filegator >/dev/null && chmod +rx /home/backup >/dev/null

    # Make config for Apache
    if [[ -f /etc/httpd/conf.d/filegator.conf ]]; then
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

    # Change root directory configuration.php
    sudo sed -i "s#__DIR__\.'/repository'#'/home'#g" /usr/share/filegator/configuration.php

    systemctl restart httpd
  fi

  wget -q http://$ip_server/filegator/
}

function install_filegator_fpm() {
echo ""
msg "${ORANGE}[Progress]${NOFORMAT} Installing Filegator (Nginx+PHP-FPM)..."
echo ""
  # Check PHP version
  PHP_VERSION=$(php -r "echo PHP_VERSION;")
  REQUIRED_PHP_VERSION="7.2.5"

  if [ "$(printf '%s\n' "$REQUIRED_PHP_VERSION" "$PHP_VERSION" | sort -V | head -n1)" != "$REQUIRED_PHP_VERSION" ]; then
    echo "Filegator requires PHP $REQUIRED_PHP_VERSION or later. Your current version is $PHP_VERSION."
    return
  fi

  if [[ -d /usr/share/filegator ]]; then
    echo "Filegator is already installed."
  else
    echo "Filegator is not installed. Installing now..."

    for attempt in {1..3}; do
      wget https://github.com/filegator/static/raw/master/builds/filegator_latest.zip -P /usr/share/
      if [ $? -eq 0 ]; then
        break
      fi
      echo "Attempt $attempt failed. Retrying in 5 seconds..."
      sleep 5
    done

    unzip -o /usr/share/filegator_latest.zip -d /usr/share/ &>/dev/null && chown -R root:admin /usr/share/filegator && chmod -R 775 /usr/share/filegator

# create file /etc/nginx/conf.d/filegator-phpmyadmin-roundcube.conf

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

# Restart Nginx & php-fpm
systemctl restart nginx && systemctl restart php-fpm

# Change root directory configuration.php
sed -i "s#__DIR__\.'/repository'#'/home'#g" /usr/share/filegator/configuration.php

usermod -a -G admin apache && chmod +rx /home/admin && chmod +rx /home/backup && chmod -R 775 /home/admin/web && chown -R apache:apache /usr/share/filegator/private/logs && chown -R apache:apache /usr/share/filegator/repository
fi

wget -q http://$ip_server/filegator/
}


function info_filegator() {
  clear

  # Проверка доступности по IP
  IP_CHECK_HTTP=$(curl --insecure -I -L http://$ip_server/filegator/ 2>/dev/null | head -n 1 | cut -d$' ' -f2)

  # Если доступность по IP подтверждена
  if [[ "$IP_CHECK_HTTP" == 200 ]]; then
    echo " "
    for i in {17..21} {21..17} ; do echo -en "\e[38;5;${i}m#####\e[0m" ; done ; echo
    echo -e ""
    msg "The FileGator has been installed. The credentials:"
    echo ""
    msg "${ORANGE}File Manager${NOFORMAT} Start From PHP 7.2"
    msg "http://$ip_server/filegator/"
    msg "User: admin"
    msg "Password: $password\n"
    msg "${ORANGE}Applications:${NOFORMAT}"
    msg "${GREEN}[Ok]${NOFORMAT} Filegator http://$ip_server/filegator/"
    for i in {17..21} {21..17} ; do echo -en "\e[38;5;${i}m#####\e[0m" ; done ; echo
    echo " "

  else
    msg "${RED}[Error]${NOFORMAT} Failed to get a response when accessing FileGator (http://$ip_server/filegator/), most likely an error occurred during installation."
  fi

  echo -e "username = admin\npassword = $password" > /root/.filegator_data
}

function filegator_centos() {
  clear

  # Check PHP version
  PHP_VERSION=$(php -r "echo PHP_VERSION;")
  REQUIRED_PHP_VERSION="7.2.5"

  if [ "$(printf '%s\n' "$REQUIRED_PHP_VERSION" "$PHP_VERSION" | sort -V | head -n1)" != "$REQUIRED_PHP_VERSION" ]; then
    msg "${RED}[Error]${NOFORMAT} Filegator requires PHP $REQUIRED_PHP_VERSION or later. Your current version is $PHP_VERSION."
    return
  fi

  # Проверка на наличие Apache и Nginx
  APACHE_RUNNING=$(ps aux | grep httpd | grep -v grep)
  NGINX_RUNNING=$(ps aux | grep nginx | grep -v grep)
  PHP_FPM_RUNNING=$(ps aux | grep php-fpm | grep -v grep)

  if [[ ! -z "$APACHE_RUNNING" && ! -z "$NGINX_RUNNING" ]]; then
    msg "${ORANGE}Detected:${NOFORMAT} Apache + Nginx"
    password_root ; install_filegator ; hash_password ;
  elif [[ ! -z "$NGINX_RUNNING" && ! -z "$PHP_FPM_RUNNING" ]]; then
    msg "${ORANGE}Detected:${NOFORMAT} Nginx + PHP-FPM"
    password_root ; install_filegator_fpm ; hash_password ;
  else
    msg "${RED}[Error]${NOFORMAT} No supported configurations detected. Please ensure either Apache + Nginx or Nginx + PHP-FPM are running." && exit 0;
  fi
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