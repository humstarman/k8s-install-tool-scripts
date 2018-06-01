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
DOCKER_VER=18.03.1
URL=https://download.docker.com/linux/static/stable/x86_64
if [ ! -f docker-${DOCKER_VER}-ce.tgz ]; then
  while true; do
    wget $URL/docker-${DOCKER_VER}-ce.tgz && break
  done
fi
if [[ ! -x "$(command -v docker)" ]]; then
  while true; do
    tar -zxvf docker-${DOCKER_VER}-ce.tgz 
    echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute docker ... "
    ansible all -m copy -a "src=./docker/ dest=/usr/local/bin mode='a+x'"
    if [[ -x "$(command -v docker)" ]]; then
      echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - docker $DOCKER_VER installed."
      break
    fi
  done
else
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - docker already existed. "
fi

# 2 config docker
ansible all -m script -a ./docker-config.sh

# 3 deploy docker
mkdir -p ./systemd-unit
FILE=./systemd-unit/docker.service
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
    sleep 1
    ansible all -m shell -a "systemctl daemon-reload"
    ansible all -m shell -a "systemctl restart $FILE"
  fi
done
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - docker $DOCKER_VER deployed."

# 4 deploy kubelet
## generate system:node-bootstrapper
if ! kubectl get clusterrolebindings | grep kubelet-bootstrap; then
  kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap
fi
## generate kubelet bootstrapping kubeconfig
FILE=mk-kubelet-kubeconfig.sh
cat > $FILE << EOF
#!/bin/bash
:(){
  FILES=\$(find /var/env -name "*.env")

  if [ -n "\$FILES" ]; then
    for FILE in \$FILES
    do
      [ -f \$FILE ] && source \$FILE
    done
  fi
};:
# 设置集群参数
kubectl config set-cluster kubernetes \\
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \\
  --embed-certs=true \\
  --server=\${KUBE_APISERVER} \\
  --kubeconfig=bootstrap.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kubelet-bootstrap \\
  --token=\${BOOTSTRAP_TOKEN} \\
  --kubeconfig=bootstrap.kubeconfig
# 设置上下文参数
kubectl config set-context default \\
  --cluster=kubernetes \\
  --user=kubelet-bootstrap \\
  --kubeconfig=bootstrap.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=bootstrap.kubeconfig
mv bootstrap.kubeconfig /etc/kubernetes/
EOF
ansible all -m script -a ./$FILE
##  generate kubelet systemd unit
mkdir -p ./systemd-unit
FILE=./systemd-unit/kubelet.service
cat > $FILE << EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
EnvironmentFile=-/var/env/env.conf
WorkingDirectory=/var/lib/kubelet
ExecStart=/usr/local/bin/kubelet \\
  --fail-swap-on=false \\
  --pod-infra-container-image=registry.access.redhat.com/rhel7/pod-infrastructure:latest \\
  --cgroup-driver=cgroupfs \\
  --address=\${NODE_IP} \\
  --hostname-override=\${NODE_IP} \\
  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --cert-dir=/etc/kubernetes/ssl \\
  --cluster-dns=\${CLUSTER_DNS_SVC_IP} \\
  --cluster-domain=\${CLUSTER_DNS_DOMAIN} \\
  --hairpin-mode promiscuous-bridge \\
  --allow-privileged=true \\
  --serialize-image-pulls=false \\
  --logtostderr=true \\
  --pod-manifest-path=/etc/kubernetes/manifests \\
  --v=2
ExecStartPost=/sbin/iptables -A INPUT -s 10.0.0.0/8 -p tcp --dport 4194 -j ACCEPT
ExecStartPost=/sbin/iptables -A INPUT -s 172.17.0.0/12 -p tcp --dport 4194 -j ACCEPT
ExecStartPost=/sbin/iptables -A INPUT -s 192.168.1.0/16 -p tcp --dport 4194 -j ACCEPT
ExecStartPost=/sbin/iptables -A INPUT -p tcp --dport 4194 -j DROP
Restart=on-failure
RestartSec=5

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
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - $FILE deployed."

# 5 deploy kube-proxy 
## generate kube-proxy pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - generate kube-proxy pem ... "
SSL_DIR=./ssl/kube-proxy
mkdir -p $SSL_DIR 
FILE=$SSL_DIR/kube-proxy-csr.json
cat > $FILE << EOF
{
  "CN": "system:kube-proxy",
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
cd $SSL_DIR && \
  cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy && \
  cd -
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute kube-proxy pem ... "
ansible all -m copy -a "src=${SSL_DIR}/ dest=/etc/kubernetes/ssl"
## generate kube-proxy bootstrapping kubeconfig
FILE=mk-kube-proxy-kubeconfig.sh
cat > $FILE << EOF
#!/bin/bash
:(){
  FILES=\$(find /var/env -name "*.env")

  if [ -n "\$FILES" ]; then
    for FILE in \$FILES
    do
      [ -f \$FILE ] && source \$FILE
    done
  fi
};:
# 设置集群参数
kubectl config set-cluster kubernetes \\
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \\
  --embed-certs=true \\
  --server=\${KUBE_APISERVER} \\
  --kubeconfig=kube-proxy.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kube-proxy \\
  --client-certificate=/etc/kubernetes/ssl/kube-proxy.pem \\
  --client-key=/etc/kubernetes/ssl/kube-proxy-key.pem \\
  --embed-certs=true \\
  --kubeconfig=kube-proxy.kubeconfig
# 设置上下文参数
kubectl config set-context default \\
  --cluster=kubernetes \\
  --user=kube-proxy \\
  --kubeconfig=kube-proxy.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
mv kube-proxy.kubeconfig /etc/kubernetes/
EOF
ansible all -m script -a ./$FILE
##  generate kube-proxy systemd unit
mkdir -p ./systemd-unit
FILE=./systemd-unit/kube-proxy.service
cat > $FILE << EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
EnvironmentFile=-/var/env/env.conf
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/usr/local/bin/kube-proxy \\
  --bind-address=\${NODE_IP} \\
  --hostname-override=\${NODE_IP} \\
  --cluster-cidr=\${SERVICE_CIDR} \\
  --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \\
  --logtostderr=true \\
  --masquerade-all \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

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
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - $FILE deployed."

# 6 deply HA based on nginx
NODE_EXISTENCE=true
if [ ! -f ./node.csv ]; then
  NODE_EXISTENCE=false
else
  if [ -z "$(cat ./node.csv)" ]; then
    NODE_EXISTENCE=false
  fi
fi
if $NODE_EXISTENCE; then
  ## generate nginx.conf
  MASTER=$(sed s/","/" "/g ./master.csv)
  DOCKER=$(which docker)
  NGINX_CONF_DIR=/etc/nginx
  FILE=nginx.conf
  cat > $FILE << EOF
error_log stderr notice;

worker_processes auto;
events {
  multi_accept on;
  use epoll;
  worker_connections 1024;
}

stream {
    upstream kube_apiserver {
        least_conn;
EOF
  for ip in $MASTER; do
    cat >> $FILE << EOF
        server $ip:6443;
EOF
  done
  cat >> $FILE << EOF
    }

    server {
        listen        0.0.0.0:6443;
        proxy_pass    kube_apiserver;
        proxy_timeout 10m;
        proxy_connect_timeout 1s;
    }
}
EOF
  ansible node -m shell -a "[ -d "$NGINX_CONF_DIR" ] || mkdir -p "$NGINX_CONF_DIR""
  ansible node -m copy -a "src=$FILE dest=$NGINX_CONF_DIR"
  ## generate nginx-proxy.service
  mkdir -p ./systemd-unit
  FILE=./systemd-unit/nginx-proxy.service
  cat > $FILE << EOF
[Unit]
Description=kubernetes apiserver docker wrapper
Wants=docker.socket
After=docker.service

[Service]
User=root
PermissionsStartOnly=true
ExecStart=$DOCKER run -p 6443:6443 \\
          -v $NGINX_CONF_DIR:/etc/nginx \\
          --name nginx-proxy \\
          --network host \\
          --restart on-failure:5 \\
          --memory 512M \\
          nginx:stable
ExecStartPre=-$DOCKER rm -f nginx-proxy
ExecStop=$DOCKER stop nginx-proxy
Restart=always
RestartSec=15s
TimeoutStartSec=30s

[Install]
WantedBy=multi-user.target
EOF
  FILE=${FILE##*/}
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute $FILE ... "
  ansible node -m copy -a "src=./systemd-unit/$FILE dest=/etc/systemd/system"
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - start $FILE ... "
  ansible node -m shell -a "systemctl daemon-reload"
  ansible node -m shell -a "systemctl enable $FILE"
  ansible node -m shell -a "systemctl restart $FILE"
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - HA nodes deployed."  
fi
