#!/usr/bin/env bash
#
# Try `install_agnudp.sh --help` for usage.
#
# (c) 2023 Khaled AGN
#

set -e

# Domain Name
DOMAIN="vpn.khaledagn.me"

# Protocol
PROTOCOL="udp"

# UDP Port
UDP_PORT=":36712"

# OBFS
OBFS="pieudp"

# Passwords
PASSWORD="pieudp"

# Script paths
SCRIPT_NAME="$(basename "$0")"
SCRIPT_ARGS=("$@")
EXECUTABLE_INSTALL_PATH="/usr/local/bin/hysteria"
SYSTEMD_SERVICES_DIR="/etc/systemd/system"
CONFIG_DIR="/etc/hysteria"
USER_DB="$CONFIG_DIR/udpusers.db"
REPO_URL="https://github.com/apernet/hysteria"
CONFIG_FILE="$CONFIG_DIR/config.json"
API_BASE_URL="https://api.github.com/repos/apernet/hysteria"
CURL_FLAGS=(-L -f -q --retry 5 --retry-delay 10 --retry-max-time 60)
SYSTEMD_SERVICE="$SYSTEMD_SERVICES_DIR/hysteria-server.service"

# Ensure required directories exist
mkdir -p "$CONFIG_DIR"
touch "$USER_DB"

# Other configurations
OPERATING_SYSTEM=""
ARCHITECTURE=""
VERSION=""
LOCAL_FILE=""
FORCE_NO_ROOT=""
FORCE_NO_SYSTEMD=""

# Utility functions
has_command() {
    local _command=$1
    type -P "$_command" > /dev/null 2>&1
}

curl_download() {
    command curl "${CURL_FLAGS[@]}" "$@"
}

mktemp() {
    command mktemp "$@" "hyservinst.XXXXXXXXXX"
}

tput_color() {
    if has_command tput; then
        tput "$@"
    fi
}

tred() {
    tput_color setaf 1
}

tgreen() {
    tput_color setaf 2
}

tyellow() {
    tput_color setaf 3
}

treset() {
    tput_color sgr0
}

note() {
    echo -e "$SCRIPT_NAME: $(tgreen)note: $1$(treset)"
}

error() {
    echo -e "$SCRIPT_NAME: $(tred)error: $1$(treset)"
    exit 1
}

install_software() {
    local package="$1"
    if has_command apt-get; then
        echo "Installing $package using apt-get..."
        apt-get update && apt-get install -y "$package"
    elif has_command dnf; then
        echo "Installing $package using dnf..."
        dnf install -y "$package"
    elif has_command yum; then
        echo "Installing $package using yum..."
        yum install -y "$package"
    elif has_command zypper; then
        echo "Installing $package using zypper..."
        zypper install -y "$package"
    elif has_command pacman; then
        echo "Installing $package using pacman..."
        pacman -Sy --noconfirm "$package"
    else
        error "No supported package manager found. Please install $package manually."
    fi
}

check_dependencies() {
    # Check required commands and install if missing
    if ! has_command curl; then
        install_software "curl"
    fi

    if ! has_command sqlite3; then
        install_software "sqlite3"
    fi

    if ! has_command openssl; then
        install_software "openssl"
    fi
}

setup_db() {
    echo "Setting up database"
    if [[ ! -f "$USER_DB" ]]; then
        sqlite3 "$USER_DB" ".databases"
        if [[ $? -ne 0 ]]; then
            error "Unable to create database file at $USER_DB"
        fi
    fi

    sqlite3 "$USER_DB" <<EOF
CREATE TABLE IF NOT EXISTS users (
    username TEXT PRIMARY KEY,
    password TEXT NOT NULL
);
EOF

    # Add a default user
    default_username="default"
    default_password="password"
    user_exists=$(sqlite3 "$USER_DB" "SELECT username FROM users WHERE username='$default_username';")
    if [[ -z "$user_exists" ]]; then
        sqlite3 "$USER_DB" "INSERT INTO users (username, password) VALUES ('$default_username', '$default_password');"
        if [[ $? -eq 0 ]]; then
            echo "Default user created successfully."
        else
            error "Failed to create default user."
        fi
    else
        echo "Default user already exists."
    fi
}

setup_ssl() {
    echo "Generating SSL certificates..."
    mkdir -p /etc/hysteria
    openssl genrsa -out /etc/hysteria/hysteria.ca.key 2048
    openssl req -new -x509 -days 3650 -key /etc/hysteria/hysteria.ca.key -subj "/C=CN/ST=GD/L=SZ/O=Hysteria, Inc./CN=Hysteria Root CA" -out /etc/hysteria/hysteria.ca.crt
    openssl req -newkey rsa:2048 -nodes -keyout /etc/hysteria/hysteria.server.key -subj "/C=CN/ST=GD/L=SZ/O=Hysteria, Inc./CN=$DOMAIN" -out /etc/hysteria/hysteria.server.csr
    openssl x509 -req -extfile <(printf "subjectAltName=DNS:$DOMAIN,DNS:$DOMAIN") -days 3650 -in /etc/hysteria/hysteria.server.csr -CA /etc/hysteria/hysteria.ca.crt -CAkey /etc/hysteria/hysteria.ca.key -CAcreateserial -out /etc/hysteria/hysteria.server.crt
}

install_hysteria() {
    echo "Installing Hysteria..."

    local _tmpfile
    _tmpfile=$(mktemp)
    local download_url="$REPO_URL/releases/download/v1.3.5/hysteria-linux-amd64"

    echo "Downloading hysteria binary from $download_url..."
    if ! curl_download -o "$_tmpfile" "$download_url"; then
        error "Download failed! Check your network."
    fi

    echo "Installing hysteria binary..."
    if install -Dm755 "$_tmpfile" "$EXECUTABLE_INSTALL_PATH"; then
        echo "Installation successful."
    else
        error "Failed to install hysteria binary."
    fi

    rm -f "$_tmpfile"
}

install_systemd_service() {
    echo "Installing systemd service..."
    cat <<EOF > "$SYSTEMD_SERVICE"
[Unit]
Description=AGN-UDP Service
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$EXECUTABLE_INSTALL_PATH server --config $CONFIG_FILE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hysteria-server.service
    systemctl start hysteria-server.service
}

start_services() {
    echo "Starting AGN-UDP services..."
    if systemctl start hysteria-server.service; then
        echo "AGN-UDP service started."
    else
        error "Failed to start AGN-UDP service."
    fi
}

main() {
    check_dependencies
    setup_db
    setup_ssl
    install_hysteria
    install_systemd_service
    start_services
    echo -e "$(tgreen)AGN-UDP has been successfully installed and started!$(treset)"
}

main "$@"
