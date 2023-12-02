#!/bin/bash

# 配置文件
xrayDownloadLink="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
nginxConfigLink="https://raw.githubusercontent.com/Gerchart-GXT/myscripts/main/vless-xtls-vision/nginx.conf"
xrayConfigLink="https://raw.githubusercontent.com/Gerchart-GXT/myscripts/main/vless-xtls-vision/config.json"
uuid="$(cat /proc/sys/kernel/random/uuid)"

# 创建临时目录
mkdir -p "/tmp/$uuid"

# 用apt安装软件
function installFromApt()
{
    local soft=$1
    if command -v $soft &> /dev/null; then
        echo "$soft 已安装"
    else
        echo "安装 $soft"
        apt install $soft -y > /dev/null
    fi
}

# 用于配置关键字替换及写入
function customConfig()
{
    # link path org1 now1 ...
    argc=$#
    argv=("${@}")
    configlink=$1
    configPath=$2
    tmpFilePath="/tmp/${uuid}/config.tmp"
    curl $configlink > $tmpFilePath
    for ((i=2;i<argc;i+=2)); do
        echo ${argv[i]}
        sed -i "s/${argv[i]}/${argv[i+1]}/g" "$tmpFilePath"
    done
    mv $tmpFilePath $configPath
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

function customConfig()
{
    argc=$#
    argv=("${@}")
    configlink=$1
    configPath=$2
    tmpFilePath="/tmp/${uuid}/config.tmp"
    curl $configlink > $tmpFilePath
    for ((i=2;i<argc;i+=2)); do
        echo ${argv[i]}
        sed -i "s/${argv[i]}/${argv[i+1]}/g" "$tmpFilePath"
    done
    mv $tmpFilePath $configPath
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

# Main--------------------------------------------------
echo "欢迎使用本脚本，项目地址为https://github.com/Gerchart-GXT/myscripts/tree/main"
echo "本脚本为vless+xtls+vision一键搭建脚本，仅适用于Debian/Ubuntu，支持自定义回落伪装域名，按任意键开始安装"
read startToInstall

# 确认当前用户为root
currentUser=$(whoami)
if [ "$currentUser" == "root" ]; then
    echo "当前用户是 root。"
else
    echo "当前用户不是 root。请使用 root 权限运行此脚本。"
    exit 1
fi
# 判断系统是否为Debian/Ubuntu
getOSInfo
ret=$?

if [ $ret -ne 1 ]; then
    exit 1
elif [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
    echo "本脚本仅用于Debian/Ubuntu"安装
    exit 2
fi

echo "进行基本更新"
apt update > /dev/null
apt full-upgrade -y > /dev/null

echo "获取最新XRAY内核"
installFromApt "curl"
bash -c "$(curl -L ${xrayDownloadLink})" @ install

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
mkdir -p "$sslDir"

keyPath="${sslDir}/${domain}.key"
crtPath="${sslDir}/${domain}.crt"

acme.sh --installcert -d $domain --ecc  --key-file   $keyPath   --fullchain-file $crtPath > /dev/null

echo "安装Nginx"
installFromApt "nginx"

guiseDomain=""
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

customConfig $nginxConfigLink $nginxConfigPath "\[guiseDomain\]" "https:\/\/$guiseDomain"

echo "Nginx配置写入完成，正在重启Nginx"
systemctl restart nginx

echo "正在随机生成uuid"
echo $uuid

xrayConfigPath="/usr/local/etc/xray/config.json"
echo "写入XRAY配置"
customConfig $xrayConfigLink $xrayConfigPath "\[uuid\]" $uuid

echo "给予Xray证书权限"
chmod -R 777 /root # 这里很奇怪，如果只给acme和ssl 还是无法读取

echo "写入配置完成，正在重启XRAY"
systemctl restart xray

# 获取Nginx运行状态：
echo "获取Nginx运行状态"
checkActive "nginx"

# 获取XRAY运行状态：
echo "获取XRAY运行状态"
checkActive "xray"

echo "您的节点为"
echo "vless://${uuid}@${domain}:443?encryption=none&flow=xtls-rprx-vision&security=tls&sni=${domain}&fp=chrome&type=tcp&headerType=none&host=${domain}"
