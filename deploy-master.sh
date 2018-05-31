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

# 2 generate kubernetes pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - generate kubernetes pem ... "
mkdir -p ./ssl/kubernetes
FILE=./ssl/kubernetes/kubernetes-csr.json
cat > $FILE << EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
EOF
MASTER=$(sed s/","/" "/g ./master.csv)
#echo $MASTER
for ip in $MASTER; do
  cat >> $FILE << EOF
    "$ip",
EOF
done
cat >> $FILE << EOF
    "${CLUSTER_KUBERNETES_SVC_IP}",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
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

cd ./ssl/kubernetes && \
  cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes
  cd -

# 3 distribute kubernetes pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute kubernetes pem ... "
ansible master -m copy -a "src=./ssl/kubernetes/ dest=/etc/kubernetes/ssl"

# 4 pepaare ennviorment variable about the number of masters
N2SET=3
MASTER=$(sed s/","/" "/g ./master.csv)
N_MASTER=$(echo $MASTER | wc | awk -F ' ' '{print $2}')
[[ "$N_MASTER" > "$N2SET" ]] && N2SET=$N_MASTER
  
# 5 deploy kube-apiserver
mkdir -p ./systemd-unit
FILE=./systemd-unit/kube-apiserver.service
cat > $FILE << EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
EnvironmentFile=-/var/env/env.conf
ExecStart=/usr/local/bin/kube-apiserver \\
  --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --advertise-address=\${NODE_IP} \\
  --bind-address=0.0.0.0 \\
  --insecure-bind-address=0.0.0.0 \\
  --authorization-mode=Node,RBAC \\
  --runtime-config=api/all=rbac.authorization.kubernetes.io/v1 \\
  --kubelet-https=true \\
  --enable-bootstrap-token-auth \\
  --token-auth-file=/etc/kubernetes/token.csv \\
  --service-cluster-ip-range=\${SERVICE_CIDR} \\
  --service-node-port-range=\${NODE_PORT_RANGE} \\
  --tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem \\
  --tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --client-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  --etcd-certfile=/etc/kubernetes/ssl/kubernetes.pem \\
  --etcd-keyfile=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --etcd-servers=\${ETCD_ENDPOINTS} \\
  --enable-swagger-ui=true \\
  --allow-privileged=true \\
  --apiserver-count=$N2SET \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/lib/audit.log \\
  --event-ttl=1h \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5
Type=notify
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
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - $FILE deployed."

# 6 deploy kube-controller-manager
mkdir -p ./systemd-unit
FILE=./systemd-unit/kube-controller-manager.service
cat > $FILE << EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
EnvironmentFile=-/var/env/env.conf
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=127.0.0.1 \\
  --master=http://\${MASTER_IP}:8080 \\
  --allocate-node-cidrs=true \\
  --service-cluster-ip-range=\${SERVICE_CIDR} \\
  --cluster-cidr=\${CLUSTER_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --root-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

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
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - $FILE deployed."

# 7 deploy kube-scheduler-
mkdir -p ./systemd-unit
FILE=./systemd-unit/kube-scheduler.service
cat > $FILE << EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
EnvironmentFile=-/var/env/env.conf
ExecStart=/usr/local/bin/kube-scheduler \\
  --address=127.0.0.1 \\
  --master=http://\${MASTER_IP}:8080 \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

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
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - $FILE deployed."
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - master deployed."
