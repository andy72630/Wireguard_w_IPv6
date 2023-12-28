#!/bin/bash

rand(){
    min=$1
    max=$(($2-$min+1))
    num=$(cat /dev/urandom | head -n 10 | cksum | awk -F ' ' '{print $1}')
    echo $(($num%$max+$min))  
}

wireguard_install(){
    version=$(cat /etc/os-release | awk -F '[".]' '$1=="VERSION="{print $2}')
    if [ $version >= 18 ]
    then
        apt-get update -y
        apt-get install software-properties-common -y
    #else
     #   apt-get update -y
      #  apt-get install -y software-properties-common
    fi
    apt-get update -y
    apt-get install -y wireguard curl
    apt install resolvconf

    echo net.ipv4.ip_forward = 1 >> /etc/sysctl.conf
    echo net.ipv6.conf.lo.disable_ipv6 = 1 >> /etc/sysctl.conf
    echo net.ipv6.conf.default.disable_ipv6 = 1 >> /etc/sysctl.conf
    echo net.ipv6.conf.all.disable_ipv6 = 1 >> /etc/sysctl.conf
    sysctl -p
    
    mkdir /etc/wireguard
    cd /etc/wireguard
    wg genkey | tee sprivatekey | wg pubkey > spublickey
    wg genkey | tee cprivatekey | wg pubkey > cpublickey
    s1=$(cat sprivatekey)
    s2=$(cat spublickey)
    c1=$(cat cprivatekey)
    c2=$(cat cpublickey)
    serverip=$(curl ipv4.icanhazip.com)
    port=$(rand 20000 50000)
    eth=$(ls /sys/class/net | awk '/^e/{print}')
    random_number=$(( RANDOM % 255 ))



cat > /etc/wireguard/wg0.conf <<-EOF
[Interface]
PrivateKey = $s1
Address = 10.100.$random_number.1/24
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT;
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT;
ListenPort = $port
DNS = 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $c2
AllowedIPs = 10.100.$random_number.2/32
EOF


cat > /etc/wireguard/client.conf <<-EOF
[Interface]
PrivateKey = $c1
Address = 10.100.$random_number.2/24
DNS = 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $s2
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 21
EOF

    apt-get install -y qrencode

cat > /etc/init.d/wgstart <<-EOF
#! /bin/bash
### BEGIN INIT INFO
# Provides:		wgstart
# Required-Start:	$remote_fs $syslog
# Required-Stop:    $remote_fs $syslog
# Default-Start:	2 3 4 5
# Default-Stop:		0 1 6
# Short-Description:	wgstart
### END INIT INFO
wg-quick up wg0
EOF

    chmod +x /etc/init.d/wgstart
    cd /etc/init.d
    if [ $version == 14 ]
    then
        update-rc.d wgstart defaults 90
    else
        update-rc.d wgstart defaults
    fi
    
    wg-quick up wg0
    
    content=$(cat /etc/wireguard/client.conf)
    echo -e "\033[37;41m电脑端请下载/etc/wireguard/client.conf，手机端可直接使用软件扫码\033[0m"
    echo "${content}" | qrencode -o - -t UTF8
}

wireguard_remove(){

    wg-quick down wg0
    apt-get remove -y wireguard
    rm -rf /etc/wireguard

}

add_user(){
    echo -e "\033[37;41m给新用户起个名字，不能和已有用户重复\033[0m"
    read -p "请输入用户名：" newname
    cd /etc/wireguard/
    cp client.conf $newname.conf
    wg genkey | tee temprikey | wg pubkey > tempubkey
    ipnum=$(grep Allowed /etc/wireguard/wg0.conf | tail -1 | awk -F '[ ./]' '{print $6}')
    lanip=$(grep Address /etc/wireguard/wg0.conf | tail -1 | awk -F '[ ./]' '{print $5}')
    newnum=$((10#${ipnum}+1))
    sed -i 's%^PrivateKey.*$%'"PrivateKey = $(cat temprikey)"'%' $newname.conf
    sed -i 's%^Address.*$%'"Address = 10.100.$lanip.$newnum\/24"'%' $newname.conf

cat >> /etc/wireguard/wg0.conf <<-EOF
[Peer]
PublicKey = $(cat tempubkey)
AllowedIPs = 10.100.$lanip.$newnum/32
EOF
    wg set wg0 peer $(cat tempubkey) allowed-ips 10.100.$lanip.$newnum/32
    echo -e "\033[37;41m添加完成，文件：/etc/wireguard/$newname.conf\033[0m"
    rm -f temprikey tempubkey
}

#开始菜单
start_menu(){
    if ! command -v wg &> /dev/null; then
        # WireGuard is not installed, update and install net-tools
        apt update -y
        apt install net-tools -y
    fi
    clear
    wireguard_install
    echo -e "\033[43;42m ====================================\033[0m"
    echo -e "\033[43;42m 介绍：wireguard_tun2Socks一键脚本ipv4               \033[0m"
    echo -e "\033[43;42m 系统：Ubuntu                         \033[0m"
    echo -e "\033[43;42m 原作者：A                              \033[0m"
    echo -e "\033[43;42m 修改者：Andy                         \033[0m"
    echo -e "\033[43;42m ====================================\033[0m"
    echo
    echo -e "\033[0;33m 1. 安装wireguard\033[0m"
    echo -e "\033[0;33m 2. 查看客户端二维码\033[0m"
    echo -e "\033[0;31m 3. 删除wireguard\033[0m"
    echo -e "\033[0;33m 4. 增加用户\033[0m"
    echo -e "0. 退出脚本"
    echo
    route -n -4
    echo -e "\033[43;42m ====================================\033[0m"
    route -n -6
    read -p "请输入数字:" num
    case "$num" in
    1)
        wireguard_install
        start_menu
        ;;
    2)
        read -p "请输入客户端用户名：" name
        content=$(cat /etc/wireguard/$name.conf)
        echo "${content}" | qrencode -o - -t UTF8
        echo "按任意键继续..."
        read -n 1
        start_menu
        ;;
    3)
        wireguard_remove
        start_menu
        ;;
    4)
        add_user
        start_menu
        ;;
    0)
        exit 1
        ;;
    *)
        clear
        echo -e "请输入正确数字"
        sleep 2s
        start_menu
        ;;
    esac
}

start_menu





