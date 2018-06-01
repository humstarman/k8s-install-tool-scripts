#!/bin/bash

set -e

# 1 download and install CFSSL
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - download etcd ... "
# etcd-v3.3.2-linux-amd64.tar.gz
ETCD_VER=v3.3.2
URL=https://github.com/coreos/etcd/releases/download/$ETCD_VER
if [ ! -f etcd-$ETCD_VER-linux-amd64.tar.gz ]; then
  while true; do
    wget $URL/etcd-$ETCD_VER-linux-amd64.tar.gz && break
  done
fi
if [[ ! -x "$(command -v etcd)" || ! -x "$(command -v etcdctl)" ]]; then
  while true; do
    #wget https://github.com/coreos/etcd/releases/download/$ETCD_VER/etcd-$ETCD_VER-linux-amd64.tar.gz
    tar -zxvf etcd-$ETCD_VER-linux-amd64.tar.gz
    mkdir -p ./etcd-$ETCD_VER-linux-amd64/bin
    mv ./etcd-$ETCD_VER-linux-amd64/etcd ./etcd-$ETCD_VER-linux-amd64/bin
    mv ./etcd-$ETCD_VER-linux-amd64/etcdctl ./etcd-$ETCD_VER-linux-amd64/bin
    echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute etcd ... "
    ansible master -m copy -a "src=./etcd-$ETCD_VER-linux-amd64/bin/ dest=/usr/local/bin mode='a+x'"
    if [[ -x "$(command -v etcd)" && -x "$(command -v etcdctl)" ]]; then
      echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - etcd installed."
      break
    fi
  done
else
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - etcd already existed. "
fi

# 2 generate TLS pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - generate etcd TLS pem ... "
mkdir -p ./ssl/etcd
FILE=./ssl/etcd/etcd-csr.json
cat > $FILE << EOF
{
  "CN": "etcd",
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

cd ./ssl/etcd && \
  cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes etcd-csr.json | cfssljson -bare etcd && \
  cd -

# 3 distribute etcd pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute etcd pem ... "
ansible master -m copy -a "src=ssl/etcd/ dest=/etc/etcd/ssl"

# 4 generate etcd systemd unit
mkdir -p ./systemd-unit
FILE=./systemd-unit/etcd.service
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
WorkingDirectory=/var/lib/etcd/
ExecStart=/usr/local/bin/etcd \\
  --name=\${NODE_NAME} \\
  --cert-file=/etc/etcd/ssl/etcd.pem \\
  --key-file=/etc/etcd/ssl/etcd-key.pem \\
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \\
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \\
  --trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --initial-advertise-peer-urls=https://\${NODE_IP}:2380 \\
  --listen-peer-urls=https://\${NODE_IP}:2380 \\
  --listen-client-urls=https://\${NODE_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://\${NODE_IP}:2379 \\
  --initial-cluster-token=etcd-cluster-1 \\
  --initial-cluster=\${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
FILE=${FILE##*/}
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute $FILE ... "
ansible master -m copy -a "src=./systemd-unit/$FILE dest=/etc/systemd/system"
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - start $FILE ... "
ansible master -m shell -a "systemctl daemon-reload"
ansible master -m shell -a "systemctl enable $FILE"
ansible master -m shell -a "systemctl restart $FILE"
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - etcd $ETCD_VER deployed."
