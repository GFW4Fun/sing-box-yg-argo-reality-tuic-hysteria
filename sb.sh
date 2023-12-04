#!/bin/bash
export LANG=en_US.UTF-8
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit
#[[ -e /etc/hosts ]] && grep -qE '^ *172.65.251.78 gitlab.com' /etc/hosts || echo -e '\n172.65.251.78 gitlab.com' >> /etc/hosts
if [[ -f /etc/redhat-release ]]; then
release="Centos"
elif cat /etc/issue | grep -q -E -i "debian"; then
release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
else 
red "脚本不支持你当前系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
if [[ $(echo "$op" | grep -i -E "arch|alpine") ]]; then
red "脚本不支持你当前 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
version=$(uname -r | cut -d "-" -f1)
vi=$(systemd-detect-virt)
bit=$(uname -m)
if [[ $bit = "aarch64" ]]; then
cpu="arm64"
elif [[ $bit = "x86_64" ]]; then
amdv=$(cat /proc/cpuinfo | grep flags | head -n 1 | cut -d: -f2)
case "$amdv" in
*avx2*) cpu="amd64v3";;
*) cpu="amd64";;
esac
else
red "目前脚本不支持 $bit 架构" && exit
fi
if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
bbr=`sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}'`
elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
bbr="Openvz版bbr-plus"
else
bbr="Openvz/Lxc"
fi
if [ ! -f sbyg_update ]; then
green "首次安装Sing-box-yg脚本必要的依赖……"
update(){
if [ -x "$(command -v apt-get)" ]; then
apt update -y
elif [ -x "$(command -v yum)" ]; then
yum update -y && yum install epel-release -y
elif [ -x "$(command -v dnf)" ]; then
dnf update -y
fi
}
if [[ $release = Centos && ${vsid} =~ 8 ]]; then
cd /etc/yum.repos.d/ && mkdir backup && mv *repo backup/ 
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
yum clean all && yum makecache
cd
fi
update
packages=("curl" "openssl" "jq" "iptables" "iptables-persistent" "tar" "qrencode" "wget" "cron")
inspackages=("curl" "openssl" "jq" "iptables" "iptables-persistent" "tar" "qrencode" "wget" "cron")
for i in "${!packages[@]}"; do
package="${packages[$i]}"
inspackage="${inspackages[$i]}"
if ! command -v "$package" &> /dev/null; then
if [ -x "$(command -v apt-get)" ]; then
apt-get install -y "$inspackage"
elif [ -x "$(command -v yum)" ]; then
yum install -y "$inspackage"
elif [ -x "$(command -v dnf)" ]; then
dnf install -y "$inspackage"
fi
fi
done
if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
if [ -x "$(command -v yum)" ]; then
yum install -y cronie iptables-services
elif [ -x "$(command -v dnf)" ]; then
dnf install -y cronie iptables-services
fi
systemctl enable iptables >/dev/null 2>&1
systemctl start iptables >/dev/null 2>&1
fi
update
touch sbyg_update
fi
if [[ $vi = openvz ]]; then
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
red "检测到未开启TUN，现尝试添加TUN支持" && sleep 4
cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
green "添加TUN支持失败，建议与VPS厂商沟通或后台设置开启" && exit
else
echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
green "TUN守护功能已启动"
fi
fi
fi
v4v6(){
v4=$(curl -s4m5 icanhazip.com -k)
v6=$(curl -s6m5 icanhazip.com -k)
}
warpcheck(){
wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}
v6(){
v4orv6(){
if [ -z $(curl -s4m5 icanhazip.com -k) ]; then
echo
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
yellow "检测到 纯IPV6 VPS，添加DNS64"
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
endip=2606:4700:d0::a29f:c101
ipv=prefer_ipv6
else
endip=162.159.193.10
ipv=prefer_ipv4
echo '4' > /etc/s-box/i
fi
}
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
v4orv6
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
v4orv6
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}
close(){
systemctl stop firewalld.service >/dev/null 2>&1
systemctl disable firewalld.service >/dev/null 2>&1
setenforce 0 >/dev/null 2>&1
ufw disable >/dev/null 2>&1
iptables -P INPUT ACCEPT >/dev/null 2>&1
iptables -P FORWARD ACCEPT >/dev/null 2>&1
iptables -P OUTPUT ACCEPT >/dev/null 2>&1
iptables -t mangle -F >/dev/null 2>&1
iptables -F >/dev/null 2>&1
iptables -X >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
if [[ -n $(apachectl -v 2>/dev/null) ]]; then
systemctl stop httpd.service >/dev/null 2>&1
systemctl disable httpd.service >/dev/null 2>&1
service apache2 stop >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
fi
sleep 1
green "执行开放端口，关闭防火墙完毕"
}
openyn(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
readp "是否开放端口，关闭防火墙？\n1、是，执行 (回车默认)\n2、否，我自已手动\n请选择：" action
if [[ -z $action ]] || [[ "$action" = "1" ]]; then
close
elif [[ "$action" = "2" ]]; then
echo
else
red "输入错误,请重新选择" && openyn
fi
}
inssb(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "一、开始下载并安装Sing-box正式版内核……请稍等"
echo
sbcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
sbname="sing-box-$sbcore-linux-$cpu"
wget -q -O /etc/s-box/sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz
if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
mv /etc/s-box/$sbname/sing-box /etc/s-box
rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
if [[ -f '/etc/s-box/sing-box' ]]; then
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
blue "成功安装 Sing-box 内核版本：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')"
else
red "下载 Sing-box 内核不完整，安装失败，请再运行安装一次" && exit
fi
else
red "下载 Sing-box 内核失败，请再运行安装一次，并检测VPS的网络是否可以访问Github" && exit
fi
}
inscertificate(){
ymzs(){
ym_vl_re=www.yahoo.com
blue "Vless-reality的SNI域名默认为 www.yahoo.com"
blue "Vmess-ws将开启TLS，Hysteria-2、Tuic-v5将使用 $(cat /root/ygkkkca/ca.log 2>/dev/null) 证书，并开启SNI证书验证"
tlsyn=true
ym_vm_ws=$(cat /root/ygkkkca/ca.log 2>/dev/null)
certificatec_vmess_ws='/root/ygkkkca/cert.crt'
certificatep_vmess_ws='/root/ygkkkca/private.key'
certificatec_hy2='/root/ygkkkca/cert.crt'
certificatep_hy2='/root/ygkkkca/private.key'
certificatec_tuic='/root/ygkkkca/cert.crt'
certificatep_tuic='/root/ygkkkca/private.key'
}
zqzs(){
ym_vl_re=www.yahoo.com
blue "Vless-reality的SNI域名默认为 www.yahoo.com"
blue "Vmess-ws将关闭TLS，Hysteria-2、Tuic-v5将使用bing自签证书，并关闭SNI证书验证"
tlsyn=false
ym_vm_ws=www.bing.com
certificatec_vmess_ws='/etc/s-box/cert.pem'
certificatep_vmess_ws='/etc/s-box/private.key'
certificatec_hy2='/etc/s-box/cert.pem'
certificatep_hy2='/etc/s-box/private.key'
certificatec_tuic='/etc/s-box/cert.pem'
certificatep_tuic='/etc/s-box/private.key'
}
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "二、生成并设置相关证书"
echo
blue "自动生成bing自签证书中……" && sleep 2
openssl ecparam -genkey -name prime256v1 -out /etc/s-box/private.key
openssl req -new -x509 -days 36500 -key /etc/s-box/private.key -out /etc/s-box/cert.pem -subj "/CN=www.bing.com"
echo
if [[ -f /etc/s-box/cert.pem ]]; then
blue "生成bing自签证书成功"
else
red "生成bing自签证书失败" && exit
fi
echo
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
yellow "经检测，之前已使用Acme-yg脚本申请过Acme域名证书：$(cat /root/ygkkkca/ca.log) "
green "是否使用 $(cat /root/ygkkkca/ca.log) 域名证书？"
yellow "1：否！使用自签的证书 (回车默认)"
yellow "2：是！使用 $(cat /root/ygkkkca/ca.log) 域名证书"
readp "请选择：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
ymzs
fi
else
green "如有解析完成的域名，是否申请一个Acme域名证书？（组成双证书模式，与自签证书可共存、各协议可独立切换）"
yellow "1：否！使用自签的证书 (回车默认)"
yellow "2：是！使用Acme-yg脚本申请Acme证书 (支持常规80端口模式与Dns API模式)"
readp "请选择：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key && ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
red "Acme证书申请失败，继续使用自签证书" 
zqzs
else
ymzs
fi
fi
fi
}
chooseport(){
if [[ -z $port ]]; then
port=$(shuf -i 2000-65535 -n 1)
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
done
fi
blue "确认的端口：$port" && sleep 2
}
vlport(){
readp "\n设置Vless-reality端口[1-65535] (回车跳过为2000-65535之间的随机端口)：" port
chooseport
port_vl_re=$port
}
vmport(){
readp "\n设置Vmess-ws端口[1-65535] (回车跳过为2000-65535之间的随机端口)：" port
chooseport
port_vm_ws=$port
}
hy2port(){
readp "\n设置Hysteria2主端口[1-65535] (回车跳过为2000-65535之间的随机端口)：" port
chooseport
port_hy2=$port
}
tu5port(){
readp "\n设置Tuic5主端口[1-65535] (回车跳过为2000-65535之间的随机端口)：" port
chooseport
port_tu=$port
}
insport(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "三、设置各个协议端口"
yellow "1：自动生成每个协议的随机端口 (2000-65535范围内)，回车默认"
yellow "2：自定义每个协议端口"
readp "请输入：" port
if [ -z "$port" ] || [ "$port" = "1" ] ; then
ports=()
for i in {1..4}; do
while true; do
port=$(shuf -i 2000-65535 -n 1)
if ! [[ " ${ports[@]} " =~ " $port " ]] && \
[[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && \
[[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
ports+=($port)
break
fi
done
done
port_vm_ws=${ports[0]}
port_vl_re=${ports[1]}
port_hy2=${ports[2]}
port_tu=${ports[3]}
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
echo
blue "根据Vmess-ws协议是否启用TLS，随机指定支持CDN优选IP的端口：$port_vm_ws"
else
vlport && vmport && hy2port && tu5port
fi
echo
blue "各协议端口确认如下"
blue "Vless-reality端口：$port_vl_re"
blue "Vmess-ws端口：$port_vm_ws"
blue "Hysteria-2端口：$port_hy2"
blue "Tuic-v5端口：$port_tu"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "四、自动生成各个协议统一的uuid (密码)"
uuid=$(/etc/s-box/sing-box generate uuid)
blue "已确认uuid (密码)：${uuid}"
blue "已确认Vmess的path路径：${uuid}-vm"
}
inssbjsonser(){
cat > /etc/s-box/sb.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm"
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "min_version": "1.2",
                "max_version": "1.3",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "min_version":"1.2",
            "max_version":"1.3",
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",
            "sniff": true,
            "sniff_override_destination": true,
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        }
],
"outbounds": [
{
"type":"direct",
"tag":"direct",
"domain_strategy": "$ipv"
},
{
"type":"direct",
"tag": "vps-outbound-v4", 
"domain_strategy":"ipv4_only"
},
{
"type":"direct",
"tag": "vps-outbound-v6",
"domain_strategy":"ipv6_only"
},
{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
},
{
"type":"direct",
"tag":"socks-IPv4-out",
"detour":"socks-out",
"domain_strategy":"ipv4_only"
},
{
"type":"direct",
"tag":"socks-IPv6-out",
"detour":"socks-out",
"domain_strategy":"ipv6_only"
},
{
"type":"direct",
"tag":"warp-IPv4-out",
"detour":"wireguard-out",
"domain_strategy":"ipv4_only"
},
{
"type":"direct",
"tag":"warp-IPv6-out",
"detour":"wireguard-out",
"domain_strategy":"ipv6_only"
},
{
"type":"wireguard",
"tag":"wireguard-out",
"server":"$endip",
"server_port":1701,
"local_address":[
"172.16.0.2/32",
"2606:4700:110:891c:6ee2:7df4:5e99:b7cf/128"
],
"private_key":"aJkrp4MMgL/Oi2bO4Fww9J8aqAW1ojeOZ22RK0nXYWY=",
"peer_public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"reserved":[230,25,169]
},
{
"type": "block",
"tag": "block"
}
],
"route":{
"geoip":{
"download_url":"https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db",
"download_detour":"direct"
},
"geosite":{
"download_url":"https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db",
"download_detour":"direct"
},
"rules":[
{
"protocol": ["quic"],
"port": [ 443 ],
"outbound": "block"
},
{
"outbound":"warp-IPv4-out",
"domain": [
"yg_kkk"
],
"geosite": [
"yg_kkk"
]
},
{
"outbound":"warp-IPv6-out",
"domain": [
"yg_kkk"
],
"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv4-out",
"domain": [
"yg_kkk"
],
"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv6-out",
"domain": [
"yg_kkk"
],
"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v4",
"domain": [
"yg_kkk"
],
"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v6",
"domain": [
"yg_kkk"
],
"geosite": [
"yg_kkk"
]
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF
}
sbservice(){
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl start sing-box
systemctl restart sing-box
}
ipuuid(){
uuid=$(jq -r '.inbounds[0].users[0].uuid' /etc/s-box/sb.json)
serip=$(curl -s4m5 icanhazip.com -k || curl -s6m5 icanhazip.com -k)
if [[ "$serip" =~ : ]]; then
sbdnsip='https://[2001:4860:4860::8888]/dns-query'
server_ip="[$serip]"
server_ipcl="$serip"
else
sbdnsip='https://8.8.8.8/dns-query'
server_ip="$serip"
server_ipcl="$serip"
fi
}
wgcfgo(){
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
ipuuid
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
ipuuid
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}
result_vl_vm_hy_tu(){
rm -rf /etc/s-box/vm_ws_argo.txt /etc/s-box/vm_ws.txt /etc/s-box/vm_ws_tls.txt
wgcfgo
vl_port=$(jq -r '.inbounds[0].listen_port' /etc/s-box/sb.json)
vl_name=$(jq -r '.inbounds[0].tls.server_name' /etc/s-box/sb.json)
public_key=$(cat /etc/s-box/public.key)
short_id=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /etc/s-box/sb.json)
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
ws_path=$(jq -r '.inbounds[1].transport.path' /etc/s-box/sb.json)
vm_name=$(jq -r '.inbounds[1].tls.server_name' /etc/s-box/sb.json)
vm_port=$(jq -r '.inbounds[1].listen_port' /etc/s-box/sb.json)
tls=$(jq -r '.inbounds[1].tls.enabled' /etc/s-box/sb.json)
if [[ "$tls" = "false" ]]; then
sb_vm_ip=$server_ip
cl_vm_ip=$server_ipcl
else
sb_vm_ip=$vm_name
cl_vm_ip=$vm_name
fi
hy2_port=$(jq -r '.inbounds[2].listen_port' /etc/s-box/sb.json)
hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
if [[ -n $hy2_ports ]]; then
hy2ports=$(echo $hy2_ports | sed 's/:/-/g')
hyps=$hy2_port,$hy2ports
else
hyps=$hy2_port
fi
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
hy2_sniname=$(jq -r '.inbounds[2].tls.key_path' /etc/s-box/sb.json)
if [[ "$hy2_sniname" = '/etc/s-box/private.key' ]]; then
hy2_name=www.bing.com
sb_hy2_ip=$server_ip
cl_hy2_ip=$server_ipcl
ins_hy2=1
hy2_ins=true
else
hy2_name=$ym
sb_hy2_ip=$ym
cl_hy2_ip=$ym
ins_hy2=0
hy2_ins=false
fi
tu5_port=$(jq -r '.inbounds[3].listen_port' /etc/s-box/sb.json)
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
tu5_sniname=$(jq -r '.inbounds[3].tls.key_path' /etc/s-box/sb.json)
if [[ "$tu5_sniname" = '/etc/s-box/private.key' ]]; then
tu5_name=www.bing.com
sb_tu5_ip=$server_ip
cl_tu5_ip=$server_ipcl
ins=1
tu5_ins=true
else
tu5_name=$ym
sb_tu5_ip=$ym
cl_tu5_ip=$ym
ins=0
tu5_ins=false
fi
}
resvless(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
vl_link="vless://$uuid@$server_ip:$vl_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#ygkkk-vl-reality"
echo "$vl_link" > /etc/s-box/vl_reality.txt
red "🚀【 vless-reality-vision 】节点信息如下：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$vl_link${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vl_reality.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}
resvmess(){
if [[ "$tls" = "false" ]]; then
if [[ -n $(ps -ef | grep cloudflared) && -s '/etc/s-box/argo.log' ]]; then
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】节点信息如下：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"www.visa.com","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"ygkkk-vm-argo","tls":"tls","sni":"'$argo'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"www.visa.com","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"ygkkk-vm-argo","tls":"tls","sni":"'$argo'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_argo.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_argo.txt)"
fi
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws 】节点信息如下 (建议设置为CDN优先节点)：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$server_ip'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"ygkkk-vm-ws","tls":"","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$server_ip'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"ygkkk-vm-ws","tls":"","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws.txt)"
else
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws-tls 】节点信息如下：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}vmess://$(echo '{"add":"'$vm_name'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"ygkkk-vm-ws-tls","tls":"tls","sni":"'$vm_name'","type":"none","v":"2"}' | base64 -w 0)${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo 'vmess://'$(echo '{"add":"'$vm_name'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"ygkkk-vm-ws-tls","tls":"tls","sni":"'$vm_name'","type":"none","v":"2"}' | base64 -w 0) > /etc/s-box/vm_ws_tls.txt
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/vm_ws_tls.txt)"
fi
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}
reshy2(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?insecure=$ins_hy2&mport=$hyps&sni=$hy2_name#ygkkk-hy2"
echo "$hy2_link" > /etc/s-box/hy2.txt
red "🚀【 Hysteria-2 】节点信息如下：" && sleep 2
echo
echo "分享链接【nekobox、小火箭shadowrocket】"
echo -e "${yellow}$hy2_link${plain}"
echo
echo "二维码【nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/hy2.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}
restu5(){
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
tuic5_link="tuic://$uuid:$uuid@$sb_tu5_ip:$tu5_port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&allow_insecure=$ins#ygkkk-tu5"
echo "$tuic5_link" > /etc/s-box/tuic5.txt
red "🚀【 Tuic-v5 】节点信息如下：" && sleep 2
echo
echo "分享链接【nekobox、小火箭shadowrocket】"
echo -e "${yellow}$tuic5_link${plain}"
echo
echo "二维码【nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/tuic5.txt)"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}
sb_client(){
cat > /etc/s-box/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
    "dns": {
        "servers": [
            {
                "tag": "remote",
                "address": "$sbdnsip",             
                "detour": "select"
            },
            {
                "tag": "local",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "address": "rcode://success",
                "tag": "block"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "local",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "remote"
            },
            {
                "clash_mode": "Direct",
                "server": "local"
            },
            {
                "geosite": "cn",
                "server": "local"
            },
            {
                "geosite": "geolocation-!cn",
                "server": "remote"
            },
             {
                "geosite": "geolocation-!cn",             
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "remote"
        },
      "inbounds": [
    {
      "type": "tun",
      "inet4_address": "172.19.0.1/30",
      "inet6_address": "fdfe:dcba:9876::1/126",
      "auto_route": true,
      "strict_route": true,
      "stack": "mixed",
      "sniff": true
    }
  ],
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule",
      "store_mode": true,
      "store_selected": true,
      "store_fakeip": true
    }
  },
  "outbounds": [
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",
        "vless-sb",
        "vmess-sb",
        "hy2-sb",
        "tuic5-sb"
      ]
    },
    {
      "type": "vless",
      "tag": "vless-sb",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
{
            "server": "$cl_vm_ip",
            "server_port": $vm_port,
            "tag": "vmess-sb",
            "tls": {
                "enabled": $tls,
                "server_name": "$vm_name",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
            "transport": {
                "headers": {
                    "Host": [
                        "$vm_name"
                    ]
                },
                "path": "$uuid-vm",
                "type": "ws"
            },
            "type": "vmess",
            "security": "auto",
            "uuid": "$uuid"
        },
    {
        "type": "hysteria2",
        "tag": "hy2-sb",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$uuid",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-sb",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$uuid",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
                "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "block",
      "type": "block"
    },
    {
      "tag": "dns-out",
      "type": "dns"
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "vless-sb",
        "vmess-sb",
        "hy2-sb",
        "tuic5-sb"
      ],
      "url": "https://cp.cloudflare.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "geoip": {
      "download_url": "https://mirror.ghproxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db",
      "download_detour": "select"
    },
    "geosite": {
      "download_url": "https://mirror.ghproxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db",
      "download_detour": "select"
    },
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
        "outbound": "dns-out",
        "protocol": "dns"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "geosite": "cn",
        "geoip": [
          "cn",
          "private"
        ],
        "outbound": "direct"
      },
      {
        "geosite": "geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF
cat > /etc/s-box/clash_meta_client.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
dns:
  enable: true
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4
proxies:
- name: vless-reality-vision节点               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                      
  client-fingerprint: chrome                  
- name: vmess-ws节点                         
  type: vmess
  server: $cl_vm_ip                        
  port: $vm_port                                     
  uuid: $uuid       
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls
  network: ws
  servername: $vm_name                    
  ws-opts:
    path: "$uuid-vm"                             
    headers:
      Host: $vm_name                     
- name: hysteria2节点                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  port: $hy2_port                                
  password: $uuid                              
  alpn:
    - h3
  sni: $hy2_name                               
  skip-cert-verify: $hy2_ins
  fast-open: true
- name: tuic5节点                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $uuid   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins  
proxy-groups:
- name: 负载均衡
  type: load-balance
  url: https://cp.cloudflare.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
    - vless-reality-vision节点                              
    - vmess-ws节点
    - hysteria2节点
    - tuic5节点
- name: 自动选择
  type: url-test
  url: https://cp.cloudflare.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
    - vless-reality-vision节点                              
    - vmess-ws节点
    - hysteria2节点
    - tuic5节点
    
- name: 🌍选择代理节点
  type: select
  proxies:
    - 负载均衡                                         
    - 自动选择
    - DIRECT
    - vless-reality-vision节点                              
    - vmess-ws节点
    - hysteria2节点
    - tuic5节点
rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍选择代理节点
EOF
cat > /etc/s-box/v2rayn_hy2.yaml <<EOF
server: $sb_hy2_ip:$hy2_port
auth: $uuid
tls:
  sni: $hy2_name
  insecure: $hy2_ins
fastOpen: true
socks5:
  listen: 127.0.0.1:50000
lazy: true
transport:
  udp:
    hopInterval: 30s
EOF
cat > /etc/s-box/v2rayn_tu5.json <<EOF
{
    "relay": {
        "server": "$sb_tu5_ip:$tu5_port",
        "uuid": "$uuid",
        "password": "$uuid",
        "congestion_control": "bbr",
        "alpn": ["h3", "spdy/3.1"]
    },
    "local": {
        "server": "127.0.0.1:55555"
    },
    "log_level": "info"
}
EOF
if [[ -n $hy2_ports ]]; then
hy2_ports=",$hy2_ports"
hy2_ports=$(echo $hy2_ports | sed 's/:/-/g')
a=$hy2_ports
sed -i "/server:/ s/$/$a/" /etc/s-box/v2rayn_hy2.yaml
fi
sed -i 's/server: \(.*\)/server: "\1"/' /etc/s-box/v2rayn_hy2.yaml
if [[ -f /etc/s-box/i ]]; then
sed -i 's/"inet6_address":/\/\/&/' /etc/s-box/sing_box_client.json
fi
}
cfargo(){
tls=$(jq -r '.inbounds[1].tls.enabled' /etc/s-box/sb.json)
if [[ "$tls" = "false" ]]; then
i=0
while [ $i -le 4 ]; do let i++
yellow "第$i次刷新验证Cloudflared Argo隧道域名有效性，请稍等……"
if [[ -n $(ps -ef | grep cloudflared) ]]; then
kill -15 $(cat /etc/s-box/sbargopid.log) >/dev/null 2>&1
fi
/etc/s-box/cloudflared tunnel --url http://localhost:$(jq -r '.inbounds[1].listen_port' /etc/s-box/sb.json) --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 &
echo "$!" > /etc/s-box/sbargopid.log
sleep 5
if [[ -n $(curl -sL https://$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')/ -I | awk 'NR==1 && /404|400/') ]]; then
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
blue "Argo隧道申请成功，域名验证有效：$argo" && sleep 2
break
fi
if [ $i -eq 5 ]; then
yellow "Argo域名验证暂不可用，稍后可能会自动恢复，或者直接申请重置" && sleep 2
fi
done
else
yellow "因vmess开启了tls，Argo隧道功能不可用" && sleep 2
fi
}
instsllsingbox(){
if [[ -f '/etc/systemd/system/sing-box.service' ]]; then
red "已安装Sing-box服务，无法再次安装" && exit
fi
mkdir -p /etc/s-box
v6 ; openyn ; inssb ; inscertificate ; insport
echo
blue "Vless-reality相关key与id将自动生成……"
key_pair=$(/etc/s-box/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
echo "$public_key" > /etc/s-box/public.key
short_id=$(/etc/s-box/sing-box generate rand --hex 4)
wget -q -O /root/geosite.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db
wget -q -O /root/geoip.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db
inssbjsonser && sbservice && sbactive
if [[ ! $vi =~ lxc|openvz ]]; then
sysctl -w net.core.rmem_max=2500000 > /dev/null
sysctl -p > /dev/null
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "五、针对vmess-ws协议，加入Cloudflared-Argo临时隧道功能"
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
esac
curl -sL -o /etc/s-box/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu
chmod +x /etc/s-box/cloudflared
/etc/s-box/cloudflared tunnel --url http://localhost:$(jq -r '.inbounds[1].listen_port' /etc/s-box/sb.json) --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 &
echo "$!" > /etc/s-box/sbargopid.log
sleep 5
if [[ -n $(curl -sL https://$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')/ -I | awk 'NR==1 && /404|400/') ]]; then
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
blue "Argo隧道申请成功且验证有效，域名：$argo" && sleep 2
else
cfargo
fi
curl -sL https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
clear
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
lnsb && blue "Sing-box安装成功，脚本快捷方式为 sb" && cronsb
sbshare
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
blue "Hysteria2与Tuic5的v2rayn配置文件、Clash-Meta、SFA/SFI/SFW客户端配置文件，请选择9进行查看"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}
changeym(){
[ -f /root/ygkkkca/ca.log ] && ymzs="$yellow切换为域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)$plain" || ymzs="$yellow未申请域名证书，无法切换$plain"
vl_na="正在使用的域名证书：$(jq -r '.inbounds[0].tls.server_name' /etc/s-box/sb.json)。$yellow更换符合reality要求的域名证书，不建议使用自有解析的域名$plain"
tls=$(jq -r '.inbounds[1].tls.enabled' /etc/s-box/sb.json)
[[ "$tls" = "false" ]] && vm_na="当前已关闭TLS。$ymzs ${yellow}切换为开启TLS，Argo隧道将关闭，可进入主菜单选项4，将端口更改为https 443系的端口，主协议可实现CDN优选IP${plain}" || vm_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为关闭TLS，Argo隧道将可用，可进入主菜单选项4，将端口更改为http 80系端口，主协议可实现CDN优选IP$plain"
hy2_sniname=$(jq -r '.inbounds[2].tls.key_path' /etc/s-box/sb.json)
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_na="正在使用自签bing证书。$ymzs" || hy2_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
tu5_sniname=$(jq -r '.inbounds[3].tls.key_path' /etc/s-box/sb.json)
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_na="正在使用自签bing证书。$ymzs" || tu5_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
green "请选择要切换证书模式的协议"
green "1：vless-reality协议，$vl_na"
if [[ -f /root/ygkkkca/ca.log ]]; then
green "2：vmess-ws协议，$vm_na"
green "3：Hysteria2协议，$hy2_na"
green "4：Tuic5协议，$tu5_na"
else
red "仅支持选项1 (vless-reality)。因未申请域名证书，vmess-ws、Hysteria-2、Tuic-v5的证书切换选项暂不予显示"
fi
green "0：返回上层"
readp "请选择：" menu
if [ "$menu" = "1" ]; then
readp "请输入vless-reality域名 (回车使用www.yahoo.com)：" menu
ym_vl_re=${menu:-www.yahoo.com}
a=$(jq -r '.inbounds[0].tls.server_name' /etc/s-box/sb.json)
b=$(jq -r '.inbounds[0].tls.reality.handshake.server' /etc/s-box/sb.json)
c=$(cat /etc/s-box/vl_reality.txt | cut -d'=' -f5 | cut -d'&' -f1)
sed -i "23s/$a/$ym_vl_re/" /etc/s-box/sb.json
sed -i "27s/$b/$ym_vl_re/" /etc/s-box/sb.json
systemctl restart sing-box
blue "vless-reality域名已更换为$ym_vl_re"
result_vl_vm_hy_tu && resvless && sb_client
elif [ "$menu" = "2" ]; then
if [ -f /root/ygkkkca/ca.log ]; then
a=$(jq -r '.inbounds[1].tls.enabled' /etc/s-box/sb.json)
[ "$a" = "true" ] && a_a=false || a_a=true
b=$(jq -r '.inbounds[1].tls.server_name' /etc/s-box/sb.json)
[ "$b" = "www.bing.com" ] && b_b=$(cat /root/ygkkkca/ca.log) || b_b=$(cat /root/ygkkkca/ca.log)
c=$(jq -r '.inbounds[1].tls.certificate_path' /etc/s-box/sb.json)
d=$(jq -r '.inbounds[1].tls.key_path' /etc/s-box/sb.json)
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
sed -i "53s#$a#$a_a#" /etc/s-box/sb.json
sed -i "54s#$b#$b_b#" /etc/s-box/sb.json
sed -i "57s#$c#$c_c#" /etc/s-box/sb.json
sed -i "58s#$d#$d_d#" /etc/s-box/sb.json
systemctl restart sing-box
result_vl_vm_hy_tu && resvmess && sb_client
else
red "当前未申请域名证书，不可切换。主菜单选择12，执行Acme证书申请" && sleep 2 && sb
fi
elif [ "$menu" = "3" ]; then
if [ -f /root/ygkkkca/ca.log ]; then
c=$(jq -r '.inbounds[2].tls.certificate_path' /etc/s-box/sb.json)
d=$(jq -r '.inbounds[2].tls.key_path' /etc/s-box/sb.json)
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
sed -i "81s#$c#$c_c#" /etc/s-box/sb.json
sed -i "82s#$d#$d_d#" /etc/s-box/sb.json
systemctl restart sing-box
result_vl_vm_hy_tu && reshy2 && sb_client
else
red "当前未申请域名证书，不可切换。主菜单选择12，执行Acme证书申请" && sleep 2 && sb
fi
elif [ "$menu" = "4" ]; then
if [ -f /root/ygkkkca/ca.log ]; then
c=$(jq -r '.inbounds[3].tls.certificate_path' /etc/s-box/sb.json)
d=$(jq -r '.inbounds[3].tls.key_path' /etc/s-box/sb.json)
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
sed -i "104s#$c#$c_c#" /etc/s-box/sb.json
sed -i "105s#$d#$d_d#" /etc/s-box/sb.json
systemctl restart sing-box
result_vl_vm_hy_tu && restu5 && sb_client
else
red "当前未申请域名证书，不可切换。主菜单选择12，执行Acme证书申请" && sleep 2 && sb
fi
else
sb
fi
}
allports(){
vl_port=$(jq -r '.inbounds[0].listen_port' /etc/s-box/sb.json)
vm_port=$(jq -r '.inbounds[1].listen_port' /etc/s-box/sb.json)
hy2_port=$(jq -r '.inbounds[2].listen_port' /etc/s-box/sb.json)
tu5_port=$(jq -r '.inbounds[3].listen_port' /etc/s-box/sb.json)
hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
tu5_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$tu5_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
[[ -n $hy2_ports ]] && hy2zfport="$hy2_ports" || hy2zfport="未添加"
[[ -n $tu5_ports ]] && tu5zfport="$tu5_ports" || tu5zfport="未添加"
}
changeport(){
sbactive
allports
fports(){
readp "\n请输入转发的端口范围 (1000-65535范围内，格式为 小数字:大数字)：" rangeport
if [[ $rangeport =~ ^([1-9][0-9]{3,4}:[1-9][0-9]{3,4})$ ]]; then
b=${rangeport%%:*}
c=${rangeport##*:}
if [[ $b -ge 1000 && $b -le 65535 && $c -ge 1000 && $c -le 65535 && $b -lt $c ]]; then
iptables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
ip6tables -t nat -A PREROUTING -p udp --dport $rangeport -j DNAT --to-destination :$port
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
blue "已确认转发的端口范围：$rangeport"
else
red "输入的端口范围不在有效范围内" && fports
fi
else
red "输入格式不正确。格式为 小数字:大数字" && fports
fi
echo
}
fport(){
readp "\n请输入一个转发的端口 (1000-65535范围内)：" onlyport
if [[ $onlyport -ge 1000 && $onlyport -le 65535 ]]; then
iptables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
ip6tables -t nat -A PREROUTING -p udp --dport $onlyport -j DNAT --to-destination :$port
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
blue "已确认转发的端口：$onlyport"
else
blue "输入的端口不在有效范围内" && fport
fi
echo
}
hy2deports(){
allports
hy2_ports=$(echo "$hy2_ports" | sed 's/,/,/g')
IFS=',' read -ra ports <<< "$hy2_ports"
for port in "${ports[@]}"; do
iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$hy2_port
ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$hy2_port
done
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
}
tu5deports(){
allports
tu5_ports=$(echo "$tu5_ports" | sed 's/,/,/g')
IFS=',' read -ra ports <<< "$tu5_ports"
for port in "${ports[@]}"; do
iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$tu5_port
ip6tables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination :$tu5_port
done
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
}
allports
green "vless-reality与vmess-ws仅能更改唯一的端口"
green "Hysteria2与Tuic5支持更改主端口，也支持增删多个转发端口"
green "Hysteria2支持端口跳跃，且与Tuic5都支持多端口复用"
green "1：vless-reality协议 ${yellow}端口:$vl_port${plain}"
green "2：vmess-ws协议 ${yellow}端口:$vm_port${plain}"
green "3：Hysteria2协议 ${yellow}端口:$hy2_port  转发多端口: $hy2zfport${plain}"
green "4：Tuic5协议 ${yellow}端口:$tu5_port  转发多端口: $tu5zfport${plain}"
green "0：返回上层"
readp "请选择要变更端口的协议【0-4】：" menu
if [ "$menu" = "1" ]; then
vlport
sed -i "14s/$vl_port/$port_vl_re/" /etc/s-box/sb.json
systemctl restart sing-box
result_vl_vm_hy_tu && resvless && sb_client
elif [ "$menu" = "2" ]; then
vmport
sed -i "41s/$vm_port/$port_vm_ws/" /etc/s-box/sb.json
systemctl restart sing-box
cfargo
result_vl_vm_hy_tu && resvmess && sb_client
elif [ "$menu" = "3" ]; then
green "1：更换Hysteria2主端口 (原多端口自动重置删除)"
green "2：添加Hysteria2多端口"
green "3：重置删除Hysteria2多端口"
green "0：返回上层"
readp "请选择【0-3】：" menu
if [ "$menu" = "1" ]; then
if [ -n $hy2_ports ]; then
hy2deports
hy2port
sed -i "67s/$hy2_port/$port_hy2/" /etc/s-box/sb.json
systemctl restart sing-box
result_vl_vm_hy_tu && reshy2 && sb_client
else
hy2port
sed -i "67s/$hy2_port/$port_hy2/" /etc/s-box/sb.json
systemctl restart sing-box
result_vl_vm_hy_tu && reshy2 && sb_client
fi
elif [ "$menu" = "2" ]; then
green "1：添加Hysteria2范围端口"
green "2：添加Hysteria2单端口"
green "0：返回上层"
readp "请选择【0-2】：" menu
if [ "$menu" = "1" ]; then
port=$(jq -r '.inbounds[2].listen_port' /etc/s-box/sb.json)
fports && result_vl_vm_hy_tu && sb_client && changeport
elif [ "$menu" = "2" ]; then
port=$(jq -r '.inbounds[2].listen_port' /etc/s-box/sb.json)
fport && result_vl_vm_hy_tu && sb_client && changeport
else
changeport
fi
elif [ "$menu" = "3" ]; then
if [ -n $hy2_ports ]; then
hy2deports && result_vl_vm_hy_tu && sb_client && changeport
else
yellow "Hysteria2未设置多端口" && changeport
fi
else
changeport
fi
elif [ "$menu" = "4" ]; then
green "1：更换Tuic5主端口 (原多端口自动重置删除)"
green "2：添加Tuic5多端口"
green "3：重置删除Tuic5多端口"
green "0：返回上层"
readp "请选择【0-3】：" menu
if [ "$menu" = "1" ]; then
if [ -n $tu5_ports ]; then
tu5deports
tu5port
sed -i "91s/$tu5_port/$port_tu/" /etc/s-box/sb.json
systemctl restart sing-box
result_vl_vm_hy_tu && restu5 && sb_client
else
tu5port
sed -i "91s/$tu5_port/$port_tu/" /etc/s-box/sb.json
systemctl restart sing-box
result_vl_vm_hy_tu && restu5 && sb_client
fi
elif [ "$menu" = "2" ]; then
green "1：添加Tuic5范围端口"
green "2：添加Tuic5单端口"
green "0：返回上层"
readp "请选择【0-2】：" menu
if [ "$menu" = "1" ]; then
port=$(jq -r '.inbounds[3].listen_port' /etc/s-box/sb.json)
fports && result_vl_vm_hy_tu && sb_client && changeport
elif [ "$menu" = "2" ]; then
port=$(jq -r '.inbounds[3].listen_port' /etc/s-box/sb.json)
fport && result_vl_vm_hy_tu && sb_client && changeport
else
changeport
fi
elif [ "$menu" = "3" ]; then
if [ -n $tu5_ports ]; then
tu5deports && result_vl_vm_hy_tu && sb_client && changeport
else
yellow "Tuic5未设置多端口" && changeport
fi
else
changeport
fi
else
sb
fi
}
changeuuid(){
olduuid=$(jq -r '.inbounds[0].users[0].uuid' /etc/s-box/sb.json)
green "当前uuid (密码)：$olduuid"
echo
readp "输入自定义uuid，必须是uuid格式，不懂就回车(重置并随机生成uuid)：" menu
if [ -z "$menu" ]; then
uuid=$(/etc/s-box/sing-box generate uuid)
else
uuid=$menu
fi
blue "已确认uuid (密码)：${uuid}" 
blue "已确认Vmess的path路径：${uuid}-vm" && sleep 2
sed -i "s/$olduuid/$uuid/g" /etc/s-box/sb.json
systemctl restart sing-box
sbshare
}
changeip(){
v4v6
chip(){
rpip=$(jq -r '.outbounds[0].domain_strategy' /etc/s-box/sb.json)
sed -i "113s/$rpip/$rrpip/g" /etc/s-box/sb.json
systemctl restart sing-box
}
readp "1. IPV4优先\n2. IPV6优先\n3. 仅IPV4\n4. 仅IPV6\n请选择：" choose
if [[ $choose == "1" && -n $v4 ]]; then
rrpip="prefer_ipv4" && chip && v4_6="IPV4优先($v4)"
elif [[ $choose == "2" && -n $v6 ]]; then
rrpip="prefer_ipv6" && chip && v4_6="IPV6优先($v6)"
elif [[ $choose == "3" && -n $v4 ]]; then
rrpip="ipv4_only" && chip && v4_6="仅IPV4($v4)"
elif [[ $choose == "4" && -n $v6 ]]; then
rrpip="ipv6_only" && chip && v4_6="仅IPV6($v6)"
else 
red "当前不存在你选择的IPV4/IPV6地址，或者输入错误" && changeip
fi
blue "当前已更换的IP优先级：${v4_6}" && sb
}
tgsbshow(){
echo
yellow "1：重置/设置Telegram机器人的Token、用户ID"
yellow "0：返回上层"
readp "请选择【0-1】：" menu
if [ "$menu" = "1" ]; then
rm -rf /etc/s-box/sbtg.sh
readp "输入Telegram机器人Token: " token
telegram_token=$token
readp "输入Telegram机器人用户ID: " userid
telegram_id=$userid
echo '#!/bin/bash
export LANG=en_US.UTF-8
m1=$(cat /etc/s-box/vl_reality.txt 2>/dev/null)
m2=$(cat /etc/s-box/vm_ws.txt 2>/dev/null)
m3=$(cat /etc/s-box/vm_ws_argo.txt 2>/dev/null)
m4=$(cat /etc/s-box/vm_ws_tls.txt 2>/dev/null)
m5=$(cat /etc/s-box/hy2.txt 2>/dev/null)
m6=$(cat /etc/s-box/tuic5.txt 2>/dev/null)
m7=$(cat /etc/s-box/sing_box_client.json 2>/dev/null)
m8=$(cat /etc/s-box/clash_meta_client.yaml 2>/dev/null)
message_text_m1=$(echo "$m1")
message_text_m2=$(echo "$m2")
message_text_m3=$(echo "$m3")
message_text_m4=$(echo "$m4")
message_text_m5=$(echo "$m5")
message_text_m6=$(echo "$m6")
message_text_m7=$(echo "$m7" | jq -c .)
message_text_m8=$(echo "$m8")
MODE=HTML
URL="https://api.telegram.org/bottelegram_token/sendMessage"
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vless-reality-vision 分享链接 】：支持v2rayng、nekobox、小火箭shadowrocket "$'"'"'\n\n'"'"'"${message_text_m1}")
if [[ -f /etc/s-box/vm_ws.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws 分享链接 】：支持v2rayng、nekobox、小火箭shadowrocket "$'"'"'\n\n'"'"'"${message_text_m2}")
fi
if [[ -n $(ps -ef | grep cloudflared) && -s '/etc/s-box/argo.log' ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws(tls)+Argo 分享链接 】：支持v2rayng、nekobox、小火箭shadowrocket "$'"'"'\n\n'"'"'"${message_text_m3}")
fi
if [[ -f /etc/s-box/vm_ws_tls.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws-tls 分享链接 】：支持v2rayng、nekobox、小火箭shadowrocket "$'"'"'\n\n'"'"'"${message_text_m4}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Hysteria-2 分享链接 】：支持nekobox、小火箭shadowrocket "$'"'"'\n\n'"'"'"${message_text_m5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Tuic-v5 分享链接 】：支持nekobox、小火箭shadowrocket "$'"'"'\n\n'"'"'"${message_text_m6}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Sing-box 配置文件 】：支持SFA、SFI、SFW "$'"'"'\n\n'"'"'"${message_text_m7}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Clash-meta 配置文件 】：支持CMFA、CMFW-V、CMFOC "$'"'"'\n\n'"'"'"${message_text_m8}")
if [ $? == 124 ];then
echo TG_api请求超时,请检查网络是否重启完成并是否能够访问TG
fi
resSuccess=$(echo "$res" | jq -r ".ok")
if [[ $resSuccess = "true" ]]; then
echo "TG推送成功";
else
echo "TG推送失败，请检查TG机器人Token和ID";
fi
' > /etc/s-box/sbtg.sh
sed -i "s/telegram_token/$telegram_token/g" /etc/s-box/sbtg.sh
sed -i "s/telegram_id/$telegram_id/g" /etc/s-box/sbtg.sh
green "设置完成！请确保TG机器人已处于激活状态！"
tgnotice && sleep 3 && sb
else
changeserv
fi
}
tgnotice(){
if [[ -f /etc/s-box/sbtg.sh ]]; then
green "请稍等5秒，TG机器人准备推送……"
sbshare > /dev/null 2>&1
bash /etc/s-box/sbtg.sh
else
red "未设置TG通知功能，请前往主菜单选项3进行设置" && sleep 2 && sb
fi
}
changeserv(){
sbactive
echo
green "Sing-box配置变更选择如下:"
readp "1：reality证书更换+其他协议自签证书与域名证书切换 (开启或关闭sni证书验证、TLS)\n2：变更全协议uuid (密码)\n3：重置申请Argo隧道临时域名\n4：切换本地IPV4、IPV6出站优先级\n5：设置Telegram机器人通知功能\n0：返回上层\n请选择【0-5】：" menu
if [ "$menu" = "1" ];then
changeym
elif [ "$menu" = "2" ];then
changeuuid
elif [ "$menu" = "3" ];then
cfargo
elif [ "$menu" = "4" ];then
changeip
elif [ "$menu" = "5" ];then
tgsbshow
else 
sb
fi
}
sbymfl(){
[[ $(systemctl is-active warp-svc) = active ]] && warp_s4_ip="当前IP：$(curl -4sx socks5h://localhost:40000 icanhazip.com -k)" || warp_s4_ip='无warp-s5的IPV4，黑名单模式'
[[ $(systemctl is-active warp-svc) = active ]] && warp_s6_ip="当前IP：$(curl -6sx socks5h://localhost:40000 icanhazip.com -k)" || warp_s6_ip='无warp-s5的IPV6，黑名单模式'
v4v6
if [[ -z $v4 ]]; then
vps_ipv4='无本地IPV4，黑名单模式'      
vps_ipv6="当前IP：$v6"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="当前IP：$v4"    
vps_ipv6="当前IP：$v6"
else
vps_ipv4="当前IP：$v4"    
vps_ipv6='无本地IPV6，黑名单模式'
fi
unset swg4 swd4 swd6 swg6 ssd4 ssg4 ssd6 ssg6 sad4 sag4 sad6 sag6
wd4=$(jq -r '.route.rules[1].domain | join(" ")' /etc/s-box/sb.json)
wg4=$(jq -r '.route.rules[1].geosite | join(" ")' /etc/s-box/sb.json)
if [[ "$wd4" == "yg_kkk" && "$wg4" == "yg_kkk" ]]; then
wfl4="${yellow}【warp出站IPV4可用】未分流${plain}"
else
if [[ "$wd4" != "yg_kkk" ]]; then
swd4="$wd4 "
fi
if [[ "$wg4" != "yg_kkk" ]]; then
swg4=$wg4
fi
wfl4="${yellow}【warp出站IPV4可用】已分流：$swd4$swg4${plain} "
fi
wd6=$(jq -r '.route.rules[2].domain | join(" ")' /etc/s-box/sb.json)
wg6=$(jq -r '.route.rules[2].geosite | join(" ")' /etc/s-box/sb.json)
if [[ "$wd6" == "yg_kkk" && "$wg6" == "yg_kkk" ]]; then
wfl6="${yellow}【warp出站IPV6可用】未分流${plain}"
else
if [[ "$wd6" != "yg_kkk" ]]; then
swd6="$wd6 "
fi
if [[ "$wg6" != "yg_kkk" ]]; then
swg6=$wg6
fi
wfl6="${yellow}【warp出站IPV6可用】已分流：$swd6$swg6${plain} "
fi
sd4=$(jq -r '.route.rules[3].domain | join(" ")' /etc/s-box/sb.json)
sg4=$(jq -r '.route.rules[3].geosite | join(" ")' /etc/s-box/sb.json)
if [[ "$sd4" == "yg_kkk" && "$sg4" == "yg_kkk" ]]; then
sfl4="${yellow}【$warp_s4_ip】未分流${plain}"
else
if [[ "$sd4" != "yg_kkk" ]]; then
ssd4="$sd4 "
fi
if [[ "$sg4" != "yg_kkk" ]]; then
ssg4=$sg4
fi
sfl4="${yellow}【$warp_s4_ip】已分流：$ssd4$ssg4${plain} "
fi
sd6=$(jq -r '.route.rules[4].domain | join(" ")' /etc/s-box/sb.json)
sg6=$(jq -r '.route.rules[4].geosite | join(" ")' /etc/s-box/sb.json)
if [[ "$sd6" == "yg_kkk" && "$sg6" == "yg_kkk" ]]; then
sfl6="${yellow}【$warp_s6_ip】未分流${plain}"
else
if [[ "$sd6" != "yg_kkk" ]]; then
ssd6="$sd6 "
fi
if [[ "$sg6" != "yg_kkk" ]]; then
ssg6=$sg6
fi
sfl6="${yellow}【$warp_s6_ip】已分流：$ssd6$ssg6${plain} "
fi
ad4=$(jq -r '.route.rules[5].domain | join(" ")' /etc/s-box/sb.json)
ag4=$(jq -r '.route.rules[5].geosite | join(" ")' /etc/s-box/sb.json)
if [[ "$ad4" == "yg_kkk" && "$ag4" == "yg_kkk" ]]; then
adfl4="${yellow}【$vps_ipv4】未分流${plain}" 
else
if [[ "$ad4" != "yg_kkk" ]]; then
sad4="$ad4 "
fi
if [[ "$ag4" != "yg_kkk" ]]; then
sag4=$ag4
fi
adfl4="${yellow}【$vps_ipv4】已分流：$sad4$sag4${plain} "
fi
ad6=$(jq -r '.route.rules[6].domain | join(" ")' /etc/s-box/sb.json)
ag6=$(jq -r '.route.rules[6].geosite | join(" ")' /etc/s-box/sb.json)
if [[ "$ad6" == "yg_kkk" && "$ag6" == "yg_kkk" ]]; then
adfl6="${yellow}【$vps_ipv6】未分流${plain}" 
else
if [[ "$ad6" != "yg_kkk" ]]; then
sad6="$ad6 "
fi
if [[ "$ag6" != "yg_kkk" ]]; then
sag6=$ag6
fi
adfl6="${yellow}【$vps_ipv6】已分流：$sad6$sag6${plain} "
fi
}
changefl(){
sbactive
green "对所有协议进行统一的域名分流"
green "warp-wireguard默认开启，IPV4与IPV6可用 (选项1与2)"
green "warp-socks5需要安装warp官方客户端 (选项3与4)"
green "VPS本地出站分流，如安装warp方案一，本地IP会被warp接管 (选项5与6)"
yellow "支持完整域名方式(例：www.google.com)与geosite方式(例：netflix、disney、openai)"
yellow "注意："
yellow "1：完整域名方式只能填完整域名，geosite方式只能填geosite"
yellow "2：同一个完整域名或者geosite切勿重复分流"
yellow "3：如该分流通道无网络，所填分流为黑名单模式 (屏蔽该网站)"
changef
}
changef(){
sbymfl
echo
green "1：重置warp-wireguard-ipv4分流域名 $wfl4"
green "2：重置warp-wireguard-ipv6分流域名 $wfl6"
green "3：重置warp-socks5-ipv4分流域名 $sfl4"
green "4：重置warp-socks5-ipv6分流域名 $sfl6"
green "5：重置VPS本地ipv4分流域名 $adfl4"
green "6：重置VPS本地ipv6分流域名 $adfl6"
green "0：返回上层"
echo
readp "请选择【0-6】：" menu
if [ "$menu" = "1" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv4的完整域名方式的分流通道)：" w4flym
if [ -z "$w4flym" ]; then
w4flym='"yg_kkk"'
else
w4flym="$(echo "$w4flym" | sed 's/ /","/g')"
w4flym="\"$w4flym\""
fi
sed -i "192s/.*/$w4flym/" /etc/s-box/sb.json
systemctl restart sing-box
changef
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv4的geosite方式的分流通道)：" w4flym
if [ -z "$w4flym" ]; then
w4flym='"yg_kkk"'
else
w4flym="$(echo "$w4flym" | sed 's/ /","/g')"
w4flym="\"$w4flym\""
fi
sed -i "195s/.*/$w4flym/" /etc/s-box/sb.json
systemctl restart sing-box
changef
else
changef
fi
elif [ "$menu" = "2" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的完整域名方式的分流通道：" w6flym
if [ -z "$w6flym" ]; then
w6flym='"yg_kkk"'
else
w6flym="$(echo "$w6flym" | sed 's/ /","/g')"
w6flym="\"$w6flym\""
fi
sed -i "201s/.*/$w6flym/" /etc/s-box/sb.json
systemctl restart sing-box
changefl
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的geosite方式的分流通道：" w6flym
if [ -z "$w6flym" ]; then
w6flym='"yg_kkk"'
else
w6flym="$(echo "$w6flym" | sed 's/ /","/g')"
w6flym="\"$w6flym\""
fi
sed -i "204s/.*/$w6flym/" /etc/s-box/sb.json
systemctl restart sing-box
changefl
else
changefl
fi
elif [ "$menu" = "3" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv4的完整域名方式的分流通道：" s4flym
if [ -z "$s4flym" ]; then
s4flym='"yg_kkk"'
else
s4flym="$(echo "$s4flym" | sed 's/ /","/g')"
s4flym="\"$s4flym\""
fi
sed -i "210s/.*/$s4flym/" /etc/s-box/sb.json
systemctl restart sing-box
changefl
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv4的geosite方式的分流通道：" s4flym
if [ -z "$s4flym" ]; then
s4flym='"yg_kkk"'
else
s4flym="$(echo "$s4flym" | sed 's/ /","/g')"
s4flym="\"$s4flym\""
fi
sed -i "213s/.*/$s4flym/" /etc/s-box/sb.json
systemctl restart sing-box
changefl
else
changefl
fi
elif [ "$menu" = "4" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv6的完整域名方式的分流通道：" s6flym
if [ -z "$s6flym" ]; then
s6flym='"yg_kkk"'
else
s6flym="$(echo "$s6flym" | sed 's/ /","/g')"
s6flym="\"$s6flym\""
fi
sed -i "219s/.*/$s6flym/" /etc/s-box/sb.json
systemctl restart sing-box
changefl
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv6的geosite方式的分流通道：" s6flym
if [ -z "$s6flym" ]; then
s6flym='"yg_kkk"'
else
s6flym="$(echo "$s6flym" | sed 's/ /","/g')"
s6flym="\"$s6flym\""
fi
sed -i "222s/.*/$s6flym/" /etc/s-box/sb.json
systemctl restart sing-box
changefl
else
changefl
fi
elif [ "$menu" = "5" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv4的完整域名方式的分流通道：" ad4flym
if [ -z "$ad4flym" ]; then
ad4flym='"yg_kkk"'
else
ad4flym="$(echo "$ad4flym" | sed 's/ /","/g')"
ad4flym="\"$ad4flym\""
fi
sed -i "228s/.*/$ad4flym/" /etc/s-box/sb.json
systemctl restart sing-box
changefl
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv4的geosite方式的分流通道：" ad4flym
if [ -z "$ad4flym" ]; then
ad4flym='"yg_kkk"'
else
ad4flym="$(echo "$ad4flym" | sed 's/ /","/g')"
ad4flym="\"$ad4flym\""
fi
sed -i "231s/.*/$ad4flym/" /etc/s-box/sb.json
systemctl restart sing-box
changefl
else
changefl
fi
elif [ "$menu" = "6" ]; then
readp "1：使用完整域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv6的完整域名方式的分流通道：" ad6flym
if [ -z "$ad6flym" ]; then
ad6flym='"yg_kkk"'
else
ad6flym="$(echo "$ad6flym" | sed 's/ /","/g')"
ad6flym="\"$ad6flym\""
fi
sed -i "237s/.*/$ad6flym/" /etc/s-box/sb.json
systemctl restart sing-box
changefl
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv6的geosite方式的分流通道：" ad6flym
if [ -z "$ad6flym" ]; then
ad6flym='"yg_kkk"'
else
ad6flym="$(echo "$ad6flym" | sed 's/ /","/g')"
ad6flym="\"$ad6flym\""
fi
sed -i "240s/.*/$ad6flym/" /etc/s-box/sb.json
systemctl restart sing-box
changefl
else
changefl
fi
else
sb
fi
}
stclre(){
if [[ ! -f '/etc/s-box/sb.json' ]]; then
red "未正常安装Sing-box" && exit
fi
readp "1：重启\n2：关闭\n请选择：" menu
if [ "$menu" = "1" ]; then
systemctl enable sing-box
systemctl start sing-box
systemctl restart sing-box
sbactive
green "Sing-box服务已重启\n" && sleep 3 && sb
elif [ "$menu" = "2" ]; then
systemctl stop sing-box
systemctl disable sing-box
green "Sing-box服务已关闭\n" && sleep 3 && sb
else
stclre
fi
}
cronsb(){
uncronsb
crontab -l > /tmp/crontab.tmp
echo "0 1 * * * systemctl restart sing-box" >> /tmp/crontab.tmp
echo '@reboot /bin/bash -c "/etc/s-box/cloudflared tunnel --url http://localhost:$(jq -r '.inbounds[1].listen_port' /etc/s-box/sb.json) --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 & pid=\$! && echo \$pid > /etc/s-box/sbargopid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}
uncronsb(){
crontab -l > /tmp/crontab.tmp
sed -i '/sing-box/d' /tmp/crontab.tmp
sed -i '/sb.json/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}
lnsb(){
curl -sL -o /usr/bin/sb https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/sb.sh
chmod +x /usr/bin/sb
}
upsbyg(){
if [[ ! -f '/usr/bin/sb' ]]; then
red "未正常安装Sing-box-yg" && exit
fi
lnsb
curl -sL https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
green "Sing-box-yg安装脚本升级成功" && sleep 5 && sb
}
lapre(){
latcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
precore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | sed -n 4p | tr -d ',"' | awk '{print $1}')
inscore=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}')
}
upsbcroe(){
sbactive
lapre
[[ $inscore =~ ^[0-9.]+$ ]] && lat="【已安装v$inscore】" || pre="【已安装v$inscore】"
green "1：升级/切换Sing-box最新正式版 v$latcore  ${bblue}${lat}${plain}"
green "2：升级/切换Sing-box最新测试版 v$precore  ${bblue}${pre}${plain}"
readp "请选择：" menu
if [ "$menu" = "1" ]; then
upcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+",' | sed -n 1p | tr -d '",')
elif [ "$menu" = "2" ]; then
upcore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | sed -n 4p | tr -d ',"' | awk '{print $1}')
else
sb
fi
green "开始下载并更新Sing-box内核……请稍等"
sbname="sing-box-$upcore-linux-$cpu"
wget -q -O /etc/s-box/sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/v$upcore/$sbname.tar.gz
if [[ -f '/etc/s-box/sing-box.tar.gz' ]]; then
tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box
mv /etc/s-box/$sbname/sing-box /etc/s-box
rm -rf /etc/s-box/{sing-box.tar.gz,$sbname}
if [[ -f '/etc/s-box/sing-box' ]]; then
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
systemctl restart sing-box
blue "成功升级/切换 Sing-box 内核版本：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')" && sleep 3 && sb
else
red "下载 Sing-box 内核不完整，安装失败，请再运行安装一次" && upsbcroe
fi
else
red "下载 Sing-box 内核失败，请再运行安装一次，并检测VPS的网络是否可以访问Github" && exit
fi
}
unins(){
systemctl stop sing-box >/dev/null 2>&1
systemctl disable sing-box >/dev/null 2>&1
kill -15 $(cat /etc/s-box/sbargopid.log) >/dev/null 2>&1
rm -f /etc/systemd/system/sing-box.service
rm -rf /etc/s-box sbyg_update /usr/bin/sb /root/geosite.db /root/geoip.db
uncronsb
iptables -t nat -F PREROUTING >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
green "Sing-box卸载完成！"
}
sblog(){
red "退出日志 Ctrl+c"
systemctl status sing-box
journalctl -u sing-box.service -o cat -f
}
sbactive(){
if [[ ! -f /etc/s-box/sb.json ]]; then
red "未正常启动Sing-box，请卸载重装或者选择10查看运行日志反馈" && exit
fi
}
sbshare(){
result_vl_vm_hy_tu && resvless && resvmess && reshy2 && restu5 && sb_client
}
clash_sb_share(){
echo
yellow "1：查看最新各协议分享链接、二维码"
yellow "2：查看最新Clash-Meta、Sing-box客户端SFA/SFI/SFW统一配置文件"
yellow "3：查看最新Hysteria2、Tuic5的V2rayN客户端配置文件"
yellow "4：推送最新节点配置信息(1+2)到Telegram"
yellow "0：返回上层"
readp "请选择【0-4】：" menu
if [ "$menu" = "1" ]; then
sbshare
elif  [ "$menu" = "2" ]; then
green "请稍等……"
sbshare > /dev/null 2>&1
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vless-reality、vmess-ws、Hysteria2、Tuic5 】Clash-Meta配置文件显示如下："
red "支持Clash-Meta安卓客户端、Clash-Verge电脑客户端、软路由Openclash，支持Gitlab私有订阅链接在线配置更新"
red "文件目录 /etc/s-box/clash_meta_client.yaml ，复制自建以yaml文件格式为准" && sleep 2
echo
cat /etc/s-box/clash_meta_client.yaml
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vless-reality、vmess-ws、Hysteria2、Tuic5 】SFA/SFI/SFW配置文件显示如下："
red "安卓SFA、苹果SFI（支持Gitlab私有订阅链接在线配置更新），win电脑官方文件包SFW请到甬哥Github项目自行下载，"
red "文件目录 /etc/s-box/sing_box_client.json ，复制自建以json文件格式为准" && sleep 2
echo
cat /etc/s-box/sing_box_client.json
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
elif  [ "$menu" = "3" ]; then
green "请稍等……"
sbshare > /dev/null 2>&1
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 Hysteria-2 】v2rayn配置文件显示如下："
red "请下载Hysteria2官方客户端核心，支持多端口跳跃、多端口复用"
red "文件目录 /etc/s-box/v2rayn_hy2.yaml ，复制自建以yaml文件格式为准" && sleep 2
echo
cat /etc/s-box/v2rayn_hy2.yaml
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
tu5_sniname=$(jq -r '.inbounds[3].tls.key_path' /etc/s-box/sb.json)
if [[ "$tu5_sniname" = '/etc/s-box/private.key' ]]; then
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
red "注意：V2rayN客户端使用Tuic5官方客户端核心时，不支持Tuic5自签证书，仅支持域名证书" && sleep 2
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
else
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 Tuic-v5 】v2rayn配置文件显示如下："
red "请下载Tuic5官方客户端核心，如已设置多端口，请自行修改，不支持多端口跳跃，支持多端口复用"
red "文件目录 /etc/s-box/v2rayn_tu5.json ，复制自建以json文件格式为准" && sleep 2
echo
cat /etc/s-box/v2rayn_tu5.json
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
fi
elif [ "$menu" = "4" ]; then
tgnotice
else
sb
fi
}
acme(){
bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
}
cfwarp(){
bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
}
bbr(){
if [[ $vi =~ lxc|openvz ]]; then
yellow "当前VPS的架构为 $vi，不支持开启原版BBR加速" && sleep 2 && exit 
else
green "点击任意键，即可开启BBR加速，ctrl+c退出"
bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
fi
}
showprotocol(){
allports
sbymfl
tls=$(jq -r '.inbounds[1].tls.enabled' /etc/s-box/sb.json)
if [[ "$tls" = "false" ]]; then
if [[ -n $(ps -ef | grep cloudflared) && -s '/etc/s-box/argo.log' && -n $(curl -sL https://$(cat /etc/s-box/argo.log | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')/ -I | awk 'NR==1 && /404|400/') ]]; then
vm_zs="TLS关闭"
argoym="已开启"
else
vm_zs="TLS关闭"
argoym="未开启，可重置开启"
fi
else
vm_zs="TLS开启"
argoym="不支持开启"
fi
hy2_sniname=$(jq -r '.inbounds[2].tls.key_path' /etc/s-box/sb.json)
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_zs="自签证书" || hy2_zs="域名证书"
tu5_sniname=$(jq -r '.inbounds[3].tls.key_path' /etc/s-box/sb.json)
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_zs="自签证书" || tu5_zs="域名证书"
echo -e "Sing-box节点关键信息、已分流域名情况如下："
echo -e "🚀【 Vless-reality 】${yellow}端口:$vl_port  SNI域名证书:$(jq -r '.inbounds[0].tls.server_name' /etc/s-box/sb.json)${plain}"
if [[ "$tls" = "false" ]]; then
echo -e "🚀【   Vmess-ws    】${yellow}端口:$vm_port   证书形式:$vm_zs   Argo状态:$argoym${plain}"
else
echo -e "🚀【 Vmess-ws-tls  】${yellow}端口:$vm_port   证书形式:$vm_zs   Argo状态:$argoym${plain}"
fi
echo -e "🚀【  Hysteria-2   】${yellow}端口:$hy2_port  证书形式:$hy2_zs  转发多端口: $hy2zfport${plain}"
echo -e "🚀【    Tuic-v5    】${yellow}端口:$tu5_port  证书形式:$tu5_zs  转发多端口: $tu5zfport${plain}"
if [ "$argoym" = "已开启" ]; then
echo -e "UUID(密码)：${yellow}$(jq -r '.inbounds[0].users[0].uuid' /etc/s-box/sb.json)${plain}"
echo -e "Argo临时域名：${yellow}$(cat /etc/s-box/argo.log | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')${plain}"
fi
echo
ww4="warp-wireguard-ipv4分流域名：$wfl4"
ww6="warp-wireguard-ipv6分流域名：$wfl6"
ws4="warp-socks5-ipv4分流域名：$sfl4"
ws6="warp-socks5-ipv6分流域名：$sfl6"
l4="VPS本地ipv4分流域名：$adfl4"
l6="VPS本地ipv6分流域名：$adfl6"
ymflzu=("ww4" "ww6" "ws4" "ws6" "l4" "l6")
for ymfl in "${ymflzu[@]}"; do
if [[ ${!ymfl} != *"未"* ]]; then
echo -e "${!ymfl}"
fi
done
if [[ $ww4 = *"未"* && $ww6 = *"未"* && $ws4 = *"未"* && $ws6 = *"未"* && $l4 = *"未"* && $l6 = *"未"* ]] ; then
echo -e "未设置域名分流"
fi
}
clear
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
echo -e "${bblue} ░██     ░██      ░██ ██ ██         ░█${plain}█   ░██     ░██   ░██     ░█${red}█   ░██${plain}  "
echo -e "${bblue}  ░██   ░██      ░██    ░░██${plain}        ░██  ░██      ░██  ░██${red}      ░██  ░██${plain}   "
echo -e "${bblue}   ░██ ░██      ░██ ${plain}                ░██ ██        ░██ █${red}█        ░██ ██  ${plain}   "
echo -e "${bblue}     ░██        ░${plain}██    ░██ ██       ░██ ██        ░█${red}█ ██        ░██ ██  ${plain}  "
echo -e "${bblue}     ░██ ${plain}        ░██    ░░██        ░██ ░██       ░${red}██ ░██       ░██ ░██ ${plain}  "
echo -e "${bblue}     ░█${plain}█          ░██ ██ ██         ░██  ░░${red}██     ░██  ░░██     ░██  ░░██ ${plain}  "
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
white "甬哥Github项目  ：github.com/yonggekkk"
white "甬哥Blogger博客 ：ygkkk.blogspot.com"
white "甬哥YouTube频道 ：www.youtube.com/@ygkkk"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
white "Vless-reality-vision、Vmess-ws(tls)+Argo、Hysteria-2、Tuic-v5 一键四协议共存"
white "Sing-box-yg脚本快捷方式：sb"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 1. 安装 Sing-box" 
green " 2. 卸载 Sing-box"
white "----------------------------------------------------------------------------------"
green " 3. 变更配置 (双证书、UUID、Argo域名、IP优先级、TG通知)" 
green " 4. 更改端口、添加多端口跳跃复用" 
green " 5. 三大通道自定义域名分流" 
green " 6. 关闭、重启 Sing-box"   
green " 7. 更新 Sing-box-yg 脚本"
green " 8. 更新、切换 Sing-box 双内核"
white "----------------------------------------------------------------------------------"
green " 9. 实时查询/TG通知：分享链接、二维码、Clash-Meta、官方SFA/SFI/SFW客户端配置"
green "10. 查看 Sing-box 运行日志"
green "11. 一键原版BBR+FQ加速"
green "12. 管理 Acme 申请域名证书"
green "13. 管理 Warp 查看Netflix、ChatGPT解锁情况"
green " 0. 退出脚本"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
insV=$(cat /etc/s-box/v 2>/dev/null)
latestV=$(curl -sL https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1)
if [ -f /etc/s-box/v ]; then
if [ "$insV" = "$latestV" ]; then
echo -e "当前 Sing-box-yg 脚本最新版：${bblue}${insV}${plain} (已安装)"
else
echo -e "当前 Sing-box-yg 脚本版本号：${bblue}${insV}${plain}"
echo -e "检测到最新 Sing-box-yg 脚本版本号：${yellow}${latestV}${plain} (可选择7进行更新)"
echo -e "${yellow}$(curl -sL https://gitlab.com/rwkgyg/sing-box-yg/-/raw/main/version/version)${plain}"
fi
else
echo -e "当前 Sing-box-yg 脚本版本号：${bblue}${latestV}${plain}"
echo -e "请先选择 1 ，安装 Sing-box-yg 脚本"
fi
lapre
if [ -f '/etc/s-box/sb.json' ]; then
if [[ $inscore =~ ^[0-9.]+$ ]]; then
if [ "${inscore}" = "${latcore}" ]; then
echo
echo -e "当前 Sing-box 最新正式版内核：${bblue}${inscore}${plain} (已安装)"
echo
echo -e "当前 Sing-box 最新测试版内核：${bblue}${precore}${plain} (可切换)"
else
echo
echo -e "当前 Sing-box 已安装正式版内核：${bblue}${inscore}${plain}"
echo -e "检测到最新 Sing-box 正式版内核：${yellow}${latcore}${plain} (可选择8进行更新)"
echo
echo -e "当前 Sing-box 最新测试版内核：${bblue}${precore}${plain} (可切换)"
fi
else
if [ "${inscore}" = "${precore}" ]; then
echo
echo -e "当前 Sing-box 最新测试版内核：${bblue}${inscore}${plain} (已安装)"
echo
echo -e "当前 Sing-box 最新正式版内核：${bblue}${latcore}${plain} (可切换)"
else
echo
echo -e "当前 Sing-box 已安装测试版内核：${bblue}${inscore}${plain}"
echo -e "检测到最新 Sing-box 测试版内核：${yellow}${precore}${plain} (可选择8进行更新)"
echo
echo -e "当前 Sing-box 最新正式版内核：${bblue}${latcore}${plain} (可切换)"
fi
fi
else
echo
echo -e "当前 Sing-box 最新正式版内核：${bblue}${latcore}${plain}"
echo -e "当前 Sing-box 最新测试版内核：${bblue}${precore}${plain}"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "VPS状态如下："
echo -e "系统:$blue$op$plain  \c";echo -e "内核:$blue$version$plain  \c";echo -e "处理器:$blue$cpu$plain  \c";echo -e "虚拟化:$blue$vi$plain  \c";echo -e "BBR算法:$blue$bbr$plain"
v4v6
if [[ "$v6" == "2a09"* ]]; then
w6="【WARP】"
fi
if [[ "$v4" == "104.28"* ]]; then
w4="【WARP】"
fi
rpip=$(jq -r '.outbounds[0].domain_strategy' /etc/s-box/sb.json 2>/dev/null)
[[ -z $v4 ]] && showv4='IPV4地址丢失，请切换至IPV6或者重装Sing-box' || showv4=$v4$w4
[[ -z $v6 ]] && showv6='IPV6地址丢失，请切换至IPV4或者重装Sing-box' || showv6=$v6$w6
if [[ $rpip = 'prefer_ipv6' ]]; then
v4_6="IPV6优先出站($showv6)"
elif [[ $rpip = 'prefer_ipv4' ]]; then
v4_6="IPV4优先出站($showv4)"
elif [[ $rpip = 'ipv4_only' ]]; then
v4_6="仅IPV4出站($showv4)"
elif [[ $rpip = 'ipv6_only' ]]; then
v4_6="仅IPV6出站($showv6)"
fi
if [[ -z $v4 ]]; then
vps_ipv4='无IPV4'      
vps_ipv6="$v6"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="$v4"    
vps_ipv6="$v6"
else
vps_ipv4="$v4"    
vps_ipv6='无IPV6'
fi
echo -e "本地IPV4地址：$blue$vps_ipv4$w4$plain   本地IPV6地址：$blue$vps_ipv6$w6$plain"
if [[ -n $rpip ]]; then
echo -e "本地IP优先级：$blue$v4_6$plain"
fi
if [[ -n $(systemctl status sing-box 2>/dev/null | grep -w active) && -f '/etc/s-box/sb.json' ]]; then
echo -e "Sing-box状态：$green运行中$plain"
elif [[ -z $(systemctl status sing-box 2>/dev/null | grep -w active) && -f '/etc/s-box/sb.json' ]]; then
echo -e "Sing-box状态：$yellow未启动，可选择6重启，依旧如此选择10查看日志并反馈，建议卸载重装Sing-box$plain"
else
echo -e "Sing-box状态：$red未安装$plain"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
if [ -f '/etc/s-box/sb.json' ]; then
showprotocol
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
readp "请输入数字【0-13】:" Input
case "$Input" in  
 1 ) instsllsingbox;;
 2 ) unins;;
 3 ) changeserv;;
 4 ) changeport;;
 5 ) changefl;;
 6 ) stclre;;
 7 ) upsbyg;; 
 8 ) upsbcroe;;
 9 ) clash_sb_share;;
10 ) sblog;;
11 ) bbr;;
12 ) acme;;
13 ) cfwarp;;
 * ) exit 
esac
