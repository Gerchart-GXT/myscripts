#/bin/bash

public_ip=$(curl -s ifconfig.me)
bk_upload_server=""
bk_upload_path=""

job="30 5 * * * $(pwd)/docker-compose_backup.sh"

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
        docker compose down
    fi
    cd ..
done

if test -e "/root/bk_file/docker_bk.zip"; then
    if test -e "/root/bk_file/docker_bk_past.zip"; then
        rm /root/bk_file/docker_bk_past.zip
    fi
    mv /root/bk_file/docker_bk.zip /root/bk_file/docker_bk_past.zip
fi

tar -czvf docker_bk.zip *
mkdir -p /root/bk_file
mv docker_bk.zip /root/bk_file/
# scp /root/docker_bk.zip ${bk_upload_server}:${bk_upload_path}${public_ip}.zip

for folder in "${docker_apps[@]}"; do
    cd $folder
    if test -e "./docker-compose.yml"; then
        docker compose pull
        docker compose up -d
    fi
    cd ..
done
