#/bin/bash

job="30 5 * * * /root/docker-compose_backup.sh"

crontab -l | grep -qF "$job"
if [ $? -ne 0 ]; then
    (crontab -l 2>/dev/null; echo "$job") | crontab
fi



cd /opt
docker_apps=($(ls -d */))

for folder in "${docker_apps[@]}"; do
    cd $folder
    echo $folder
    if test -e "./docker-compose.yml"; then
        docker compose stop
    fi
    cd ..
done

if test -e "/root/docker_bk.zip"; then
    if test -e "/root/docker_bk_past.zip"; then
        rm /root/docker_bk_past.zip
    fi
    mv /root/docker_bk.zip /root/docker_bk_past.zip
fi

zip -q -r /root/docker_bk.zip *

for folder in "${docker_apps[@]}"; do
    cd $folder
    if test -e "./docker-compose.yml"; then
        docker compose up -d
    fi
    cd ..
done

root@TencentHK:~# vim docker-compose_backup.sh
root@TencentHK:~# cat docker-compose_backup.sh
#/bin/bash

public_ip=$(curl -s ifconfig.me)
bk_upload_server=""
bk_upload_path=""

job="30 5 * * * /root/docker-compose_backup.sh"

crontab -l | grep -qF "$job"
if [ $? -ne 0 ]; then
    (crontab -l 2>/dev/null; echo "$job") | crontab
fi

cd /opt
docker_apps=($(ls -d */))

for folder in "${docker_apps[@]}"; do
    cd $folder
    echo $folder
    if test -e "./docker-compose.yml"; then
        docker compose stop
    fi
    cd ..
done

if test -e "/root/docker_bk.zip"; then
    if test -e "/root/docker_bk_past.zip"; then
        rm /root/docker_bk_past.zip
    fi
    mv /root/docker_bk.zip /root/docker_bk_past.zip
fi

zip -q -r /root/docker_bk.zip *
# scp /root/docker_bk.zip ${bk_upload_server}:${bk_upload_path}${public_ip}.zip

for folder in "${docker_apps[@]}"; do
    cd $folder
    if test -e "./docker-compose.yml"; then
        docker-compose pull
        docker compose up -d
    fi
    cd ..
done
