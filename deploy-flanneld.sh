#!/bin/bash

set -e

# 1 download and install flannel 
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - download flannel ... "
# flannel-v3.3.2-linux-amd64.tar.gz
FLANNEL_VER=v0.10.0
if [ ! -f flannel-$FLANNEL_VER-linux-amd64.tar.gz ]; then
  while true; do
    wget https://github.com/coreos/flannel/releases/download/$FLANNEL_VER/flannel-${FLANNEL_VER}-linux-amd64.tar.gz && break
  done
fi
if [[ ! -x "$(command -v flanneld)" || ! -x "$(command -v mk-docker-opts.sh)" ]]; then
  while true; do
    #wget https://github.com/coreos/flannel/releases/download/$FLANNEL_VER/flannel-$FLANNEL_VER-linux-amd64.tar.gz
    mkdir -p flannel
    tar -zxvf flannel-$FLANNEL_VER-linux-amd64.tar.gz -C flannel
    mkdir -p ./flannel/bin
    mv ./flannel/flanneld ./flannel/bin
    mv ./flannel/mk-docker-opts.sh ./flannel/bin
    echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute flannel ... "
    ansible all -m copy -a "src=./flannel/bin/ dest=/usr/local/bin mode='a+x'"
    if [[ -x "$(command -v flanneld)" && -x "$(command -v mk-docker-opts.sh)" ]]; then
      echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - flannel installed."
      break
    fi
  done
else
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - flannel already existed. "
fi

# 2 generate TLS pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - generate flannel TLS pem ... "
mkdir -p ./ssl/flannel
FILE=./ssl/flannel/flannel-csr.json
cat > $FILE << EOF
{
  "CN": "flannel",
  "hosts": [
    "127.0.0.1",
EOF
MASTER=$(sed s/","/" "/g ./master.csv)
#echo $MASTER
i=0
N_MASTER=$(echo $MASTER | wc | awk -F ' ' '{print $2}')
#echo $N_MASTER
for ip in $MASTER; do
  i=$[i+1]
  #echo $i
  ip=\"$ip\"
  if [[ $i < $N_MASTER ]]; then
    ip+=,
  fi
  cat >> $FILE << EOF
    $ip
EOF
done
cat >> $FILE << EOF
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cd ./ssl/flannel && \
  cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes flannel-csr.json | cfssljson -bare flannel && \
  cd -

# 3 distribute flannel pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute flannel pem ... "
ansible master -m copy -a "src=ssl/flannel/ dest=/etc/flannel/ssl"

# 4 generate flannel systemd unit
mkdir -p ./systemd-unit
FILE=./systemd-unit/flannel.service
cat > $FILE << EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
EnvironmentFile=-/var/env/env.conf
WorkingDirectory=/var/lib/flannel/
ExecStart=/usr/local/bin/flannel \\
  --name=\${NODE_NAME} \\
  --cert-file=/etc/flannel/ssl/flannel.pem \\
  --key-file=/etc/flannel/ssl/flannel-key.pem \\
  --peer-cert-file=/etc/flannel/ssl/flannel.pem \\
  --peer-key-file=/etc/flannel/ssl/flannel-key.pem \\
  --trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --initial-advertise-peer-urls=https://\${NODE_IP}:2380 \\
  --listen-peer-urls=https://\${NODE_IP}:2380 \\
  --listen-client-urls=https://\${NODE_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://\${NODE_IP}:2379 \\
  --initial-cluster-token=flannel-cluster-1 \\
  --initial-cluster=\${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --data-dir=/var/lib/flannel
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
FILE=flannel.service
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute $FILE ... "
ansible master -m copy -a "src=./systemd-unit/$FILE dest=/etc/systemd/system"
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - start $FILE ... "
ansible master -m shell -a "systemctl daemon-reload"
ansible master -m shell -a "systemctl enable $FILE"
ansible master -m shell -a "systemctl restart $FILE"
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - flannel $FLANNEL_VER deployed."
