#!/bin/bash

current_user=$(whoami)

if [ "$current_user" == "root" ]; then
    echo "当前用户是 root。"
else
    echo "当前用户不是 root。请使用 root 权限运行此脚本。"
    exit 1
fi
function installFromApt()
{
    local soft=$1
    if command -v $soft &> /dev/null; then
        echo "$soft 已安装"
    else
        echo "安装 $soft"
        apt install $soft -y
    fi
}
function getOSInfo()
{
    if [ -f /etc/os-release ]; then
        # 读取版本信息
        source /etc/os-release

        # 输出系统版本信息
        echo "系统名称: $NAME"
        echo "版本号: $VERSION"
        echo "ID: $ID"
        echo "ID版本: $VERSION_ID"
        return 1
    else
        echo "无法获取系统版本信息。"
        return 0
    fi
}

function checkActive()
{
    if [ "$(systemctl is-active $1)" = "active" ]; then
        echo "$1正在运行"
        return 0
    else
        echo "$1 未在运行"
        return 1
    fi
}

getOSInfo
ret=$?

# 判断系统是否为Debian/Ubuntu
if [ $ret -ne 1 ]; then
    exit 1
elif [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
    echo "本脚本仅用于Debian/Ubuntu"安装
    exit 2
fi

# 基本更新

echo "进行基本更新"

apt update
apt full-upgrade

echo "获取最新XRAY内核"

installFromApt "curl"

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo "安装acme.sh"

installFromApt "socat"

curl https://get.acme.sh| sh
ln -s  /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
acme.sh --set-default-ca --server letsencrypt

domain=""
while true; do
    echo "请输入您的域名，确保已经解析："
    read domain
    domain="${domain// /}"
    installFromApt "dnsutils"
    resolved_ip=$(dig +short "$domain")

    if [ -z "$resolved_ip" ]; then
        echo "无法解析域名 $domain，请重新输入"
        continue
    fi
    current_ip=$(curl -s https://api.ipify.org)

    # 比较两者是否一致
    if [ "$resolved_ip" == "$current_ip" ]; then
        echo "域名 $domain 的解析与当前机器的公网IP($current_ip)一致。"
        break
    else
        echo "域名 $domain 的解析与当前机器的公网IP($current_ip)不一致。"
    fi
done

echo "查看Nginx运行状态"
checkActive "nginx"
if [ $? -eq 1 ]; then
    echo "正在停止Nginx"
    systemctl stop nginx
fi

checkActive "xray"
echo "查看XRAY运行状态"
if [ $? -eq 1 ]; then
    echo "正在停止XRAY"
    systemctl stop xray
fi

echo "正在为 $domain 申请证书"
acme.sh --issue  -d $domain  --standalone

echo "证书为您安装至/root/ssl下"

ssl_dir="/root/ssl"

# 检查目录是否存在
if [ ! -d "$ssl_dir" ]; then
    echo "目录 $ssl_dir 不存在，正在创建..."
    mkdir -p "$ssl_dir"
    echo "目录 $ssl_dir 创建完成."
fi

keyPath="${ssl_dir}/${domain}.key"
crtPath="${ssl_dir}/${domain}.crt"
acme.sh --installcert -d $domain --ecc  --key-file   $keyPath   --fullchain-file $crtPath

echo "安装Nginx"
installFromApt "nginx"

nginxConfigPath="/etc/nginx/nginx.conf"

cat <<'EOF' > ${nginxConfigPath}
user www-data;
worker_processes auto;

error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format main '[$time_local] $proxy_protocol_addr "$http_referer" "$http_user_agent"';
    access_log /var/log/nginx/access.log main;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        ""      close;
    }

    map $proxy_protocol_addr $proxy_forwarded_elem {
        ~^[0-9.]+$        "for=$proxy_protocol_addr";
        ~^[0-9A-Fa-f:.]+$ "for=\"[$proxy_protocol_addr]\"";
        default           "for=unknown";
    }

    map $http_forwarded $proxy_add_forwarded {
        "~^(,[ \t]*)*([!#$%&'*+.^_`|~0-9A-Za-z-]+=([!#$%&'*+.^_`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?(;([!#$%&'*+.^_`|~0-9A-Za-z-]+=([!#$%&'*+.^_`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?)*([ \t]*,([ \t]*([!#$%&'*+.^_`|~0-9A-Za-z-]+=([!#$%&'*+.^_`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?(;([!#$%&'*+.^_`|~0-9A-Za-z-]+=([!#$%&'*+.^_`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?)*)?)*$" "$http_forwarded, $proxy_forwarded_elem";
        default "$proxy_forwarded_elem";
    }

    server {
        listen 80;
        return 301 https://$host$request_uri;
    }

    server {
        listen 127.0.0.1:8001 proxy_protocol;
        listen 127.0.0.1:8002 http2 proxy_protocol;
        set_real_ip_from 127.0.0.1;

        location / {
            sub_filter                         $proxy_host $host;
            sub_filter_once                    off;

            proxy_pass                         https://www.superbed.cn;
            proxy_set_header Host              $proxy_host;

            proxy_http_version                 1.1;
            proxy_cache_bypass                 $http_upgrade;

            proxy_ssl_server_name on;

            proxy_set_header Upgrade           $http_upgrade;
            proxy_set_header Connection        $connection_upgrade;
            proxy_set_header X-Real-IP         $proxy_protocol_addr;
            proxy_set_header Forwarded         $proxy_add_forwarded;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host  $host;
            proxy_set_header X-Forwarded-Port  $server_port;

            proxy_connect_timeout              60s;
            proxy_send_timeout                 60s;
            proxy_read_timeout                 60s;

            resolver 1.1.1.1;
        }
    }
}
EOF

echo "Nginx配置写入完成，正在重启Nginx"
systemctl restart nginx

echo "正在随机生成uuid"
uuid="$(cat /proc/sys/kernel/random/uuid)"
echo $uuid

xrayConfigPath="/usr/local/etc/xray/config.json"
echo "写入XRAY配置"

cat <<EOF > "${xrayConfigPath}"
{
    "log": {
        "loglevel": "warning"
    },
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "ip": [
                    "geoip:cn",
                    "geoip:private"
                ],
                "outboundTag": "block"
            }
        ]
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": "8001",
                        "xver": 1
                    },
                    {
                        "alpn": "h2",
                        "dest": "8002",
                        "xver": 1
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "rejectUnknownSni": true,
                    "fingerprint": "chrome",
                    "minVersion": "1.2",
                    "certificates": [
                        {
                            "ocspStapling": 3600,
                            "certificateFile": "$crtPath",
                            "keyFile": "$keyPath"
                        }
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls"
                ]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
}
EOF

echo "给予Xray证书权限"
chmod -R 777 /root

echo "写入配置完成，正在重启XRAY"
systemctl restart xray

# 获取Nginx运行状态：
echo "获取Nginx运行状态"
checkActive "nginx"

# 获取XRAY运行状态：
echo "获取XRAY运行状态"
checkActive "xray"