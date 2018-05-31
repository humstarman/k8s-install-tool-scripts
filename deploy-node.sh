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

# 1 download and install docker 
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - download docker ... "
# kubernetes-v3.3.2-linux-amd64.tar.gz
DOCKER_VER=18.03.1
if [ ! -f docker-${DOCKER_VER}-ce.tgz ]; then
  while true; do
    wget https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VER}-ce.tgz && break
  done
fi
if [[ ! -x "$(command -v docker)" ]]; then
  while true; do
    #wget https://github.com/coreos/kubernetes/releases/download/$DOCKER_VER/kubernetes-$DOCKER_VER-linux-amd64.tar.gz
    tar -zxvf docker-${DOCKER_VER}-ce.tgz 
    echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute docker ... "
    ansible all -m copy -a "src=./docker/ dest=/usr/local/bin mode='a+x'"
    if [[ -x "$(command -v docker)" ]]; then
      echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - docker $DOCKER_VER installed."
      break
    fi
  done
else
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - kubernetes already existed. "
fi

# 2 config docker
ansible all -m script -a ./docker-config.sh

# 3 deploy docker
mkdir -p ./systemd-unit
FILE=./systemd-unit/kubernetes.service
cat > $FILE << EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
EnvironmentFile=-/run/flannel/docker
ExecStart=/usr/local/bin/dockerd --log-level=error \$DOCKER_NETWORK_OPTIONS
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
FILE=${FILE##*/}
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute $FILE ... "
ansible all -m copy -a "src=./systemd-unit/$FILE dest=/etc/systemd/system"
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - start $FILE ... "
ansible all -m shell -a "systemctl daemon-reload"
ansible all -m shell -a "systemctl enable $FILE"
ansible all -m shell -a "systemctl restart $FILE"
# check config
TARGET='10.0.0.0/8'
while true; do
  if docker info | grep $TARGET; then
    break
  else
    ansible all -m shell -a "systemctl daemon-reload"
    ansible all -m shell -a "systemctl restart $FILE"
  fi
done
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - docker $DOCKER_VER deployed."

# 2 generate kubernetes pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - generate kubernetes pem ... "
mkdir -p ./ssl/kubernetes
FILE=./ssl/kubernetes/kubernetes-csr.json
cat > $FILE << EOF
{
  "CN": "kubernetes",
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

cd ./ssl/kubernetes && \
  cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes && \
  cd -

# 3 distribute kubernetes pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute kubernetes pem ... "
ansible all -m copy -a "src=./ssl/kubernetes/ dest=/etc/kubernetes/ssl"

# 4 put pod network info into etcd cluster
/usr/local/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/kubernetes/ssl/kubernetes.pem \
  --key-file=/etc/kubernetes/ssl/kubernetes-key.pem \
  set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'

# 5 generate kubernetes systemd unit
mkdir -p ./systemd-unit
FILE=./systemd-unit/kubernetes.service
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
ExecStart=/usr/local/bin/kubernetes \\
  -etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  -etcd-certfile=/etc/kubernetes/ssl/kubernetes.pem \\
  -etcd-keyfile=/etc/kubernetes/ssl/kubernetes-key.pem \\
  -etcd-endpoints=\${ETCD_ENDPOINTS} \\
  -etcd-prefix=\${FLANNEL_ETCD_PREFIX}
ExecStartPost=/usr/local/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/kubernetes/docker
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
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - kubernetes $DOCKER_VER deployed."
