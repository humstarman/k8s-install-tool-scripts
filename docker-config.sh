#!/bin/bash
DOCKER=/opt/docker
[ -d "$DOCKER" ] || mkdir -p $DOCKER
if [ -x "$(command -v yum)" ]; then
  yum makecache
  yum install -y yum-utils \
    device-mapper-persistent-data \
    lvm2
  yum install -y conntrack
  FIREWALL="firewalld"
elif [ -x "$(command -v apt-get)" ]; then
  # for Ubuntu
  if cat /etc/issue | grep Ubuntu; then
    apt-get update
    apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      software-properties-common
  fi
  # for Debian
  if cat /etc/issue | grep Debian; then
    apt-get update
    apt-get install \
     apt-transport-https \
     ca-certificates \
     curl \
     gnupg2 \
     software-properties-common
  fi
  apt-get update
  apt-get install -y conntrack
  FIREWALL="ufw"
else
  echo "$(date) - $0 - [ERROR] - unknown Distributor ID."
  exit 1
fi

systemctl stop $FIREWALL
systemctl disable $FIREWALL

iptables -P FORWARD ACCEPT
iptables -F && iptables -X && iptables -F -t nat && iptables -X -t nat
# mk docker-iptables.service
# cp docker-iptables.service /etc/systemd/system
cat > /etc/systemd/system/docker-iptables.service << EOF
[Unit]
Description=Make Iptables Rules for Docker

[Service]
Type=oneshot
ExecStart=/bin/sh \\
          -c \\
          "sleep 60 && /sbin/iptables -P FORWARD ACCEPT"

[Install]
WantedBy=multi-user.target
EOF
[ -d /etc/docker ] || mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "data-root": "$DOCKER",
  "registry-mirrors" : [
    "https://nmp34hlf.mirror.aliyuncs.com",
    "https://mirror.ccs.tencentyun.com"
  ],
  "insecure-registries" : [
    "192.168.0.0/16",
    "172.0.0.0/8",
    "10.0.0.0/8"
  ],
  "debug" : true,
  "experimental" : true,
  "max-concurrent-downloads" : 10
}
EOF
systemctl daemon-reload
systemctl enable docker-iptables.service
# optimize bridge-nf-call-iptables && bridge-nf-call-ip6tables
## script:
FILE=/usr/local/bin/opt-bridge-nf-call-iptables.sh
cat > $FILE << EOF
#!/bin/bash
:(){
  TARGET="\$1"
  echo \$TARGET
  FILE=/etc/sysctl.conf
  if [ ! -f \$FILE ]; then
    echo "\$TARGET" > \$FILE
    return
  fi
  if cat \$FILE | grep "\$TARGET"; then return; fi
  echo "\$TARGET" >> \$FILE
}
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables
: "net.bridge.bridge-nf-call-ip6tables = 1"
: "net.bridge.bridge-nf-call-iptables = 1"
: "net.bridge.bridge-nf-call-arptables = 1"
EOF
chmod +x $FILE
## systemd unit:
FILE=/etc/systemd/system/opt-bridge-nf-call-iptables.service
cat > $FILE << EOF
[Unit]
Description=Optimization of bridge nf call iptables

[Service]
Type=oneshot
ExecStart=/usr/local/bin/opt-bridge-nf-call-iptables.sh

[Install]
WantedBy=multi-user.target
EOF
FILE=${FILE##*/}
systemctl daemon-reload
systemctl enable $FILE 

exit 0
