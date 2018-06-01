#!/bin/bash

set -e
:(){
  FILES=$(find /var/env -name "*.env")

  if [ -n "$FILES" ]; then
    for FILE in $FILES
    do
      [ -f $FILE ] && source $FILE
    done
  fi
};:

# 1 download and install flannel 
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - download flannel ... "
# flannel-v3.3.2-linux-amd64.tar.gz
FLANNEL_VER=v0.10.0
URL=https://github.com/coreos/flannel/releases/download/$FLANNEL_VER
if [ ! -f flannel-$FLANNEL_VER-linux-amd64.tar.gz ]; then
  while true; do
    wget $URL/flannel-${FLANNEL_VER}-linux-amd64.tar.gz && break
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

# 2 generate flannel pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - generate flannel pem ... "
mkdir -p ./ssl/flanneld
FILE=./ssl/flanneld/flanneld-csr.json
cat > $FILE << EOF
{
  "CN": "flanneld",
  "hosts": [],
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

cd ./ssl/flanneld && \
  cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes flanneld-csr.json | cfssljson -bare flanneld && \
  cd -

# 3 distribute flannel pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute flannel pem ... "
ansible all -m copy -a "src=./ssl/flanneld/ dest=/etc/flanneld/ssl"

# 4 put pod network info into etcd cluster
/usr/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'

# 5 generate flannel systemd unit
mkdir -p ./systemd-unit
FILE=./systemd-unit/flanneld.service
cat > $FILE << EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
EnvironmentFile=-/var/env/env.conf
ExecStart=/usr/local/bin/flanneld \\
  -etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  -etcd-certfile=/etc/flanneld/ssl/flanneld.pem \\
  -etcd-keyfile=/etc/flanneld/ssl/flanneld-key.pem \\
  -etcd-endpoints=\${ETCD_ENDPOINTS} \\
  -etcd-prefix=\${FLANNEL_ETCD_PREFIX}
ExecStartPost=/usr/local/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF
FILE=${FILE##*/}
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute $FILE ... "
ansible all -m copy -a "src=./systemd-unit/$FILE dest=/etc/systemd/system"
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - start $FILE ... "
ansible all -m shell -a "systemctl daemon-reload"
ansible all -m shell -a "systemctl enable $FILE"
ansible all -m shell -a "systemctl restart $FILE"
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - flannel $FLANNEL_VER deployed."
