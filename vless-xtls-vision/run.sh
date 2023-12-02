#!/bin/bash

currentUser=$(whoami)

if [ "$currentUser" == "root" ]; then
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
    resolvedIp=$(dig +short "$domain")

    if [ -z "$resolvedIp" ]; then
        echo "无法解析域名 $domain，请重新输入"
        continue
    fi
    currentIp=$(curl -s https://api.ipify.org)

    # 比较两者是否一致
    if [ "$resolvedIp" == "$currentIp" ]; then
        echo "域名 $domain 的解析与当前机器的公网IP($currentIp)一致。"
        break
    else
        echo "域名 $domain 的解析与当前机器的公网IP($currentIp)不一致。"
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

sslDir="/root/ssl"

# 检查目录是否存在
if [ ! -d "$sslDir" ]; then
    echo "目录 $sslDir 不存在，正在创建..."
    mkdir -p "$sslDir"
    echo "目录 $sslDir 创建完成."
fi

keyPath="${sslDir}/${domain}.key"
crtPath="${sslDir}/${domain}.crt"
acme.sh --installcert -d $domain --ecc  --key-file   $keyPath   --fullchain-file $crtPath

echo "安装Nginx"
installFromApt "nginx"

while true; do
    echo "请输入您回落伪装的域名："
    read guiseDomain
    guiseDomain="${guiseDomain// /}"
    installFromApt "dnsutils"
    resolvedIp=$(dig +short "$guiseDomain")

    if [ -z "$resolvedIp" ]; then
        echo "无法解析域名 $guiseDomain，请重新输入"
        continue
    else
        break
    fi
done

nginxConfigPath="/etc/nginx/nginx.conf"

sed -e "s/\[guiseDomain\]/$guiseDomain/g" "$(curl ${nginxConfigPath})" > "output.txt"

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
