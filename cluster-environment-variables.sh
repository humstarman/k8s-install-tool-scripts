#!/bin/bash

MASTER=$(sed s/","/" "/g ./master.csv)
NET_ID=$(cat ./master.csv)
NET_ID=${NET_ID%%,*}
NET_ID=${NET_ID%.*}
NODE_EXISTENCE=true
if [ ! -f ./node.csv ]; then
  NODE_EXISTENCE=false
else
  if [ -z "$(cat ./node.csv)" ]; then
    NODE_EXISTENCE=false
  fi
fi
if false; then
for ip in $MASTER; do
  echo $ip
done
echo '---'
echo $NET_ID
echo $NODE_EXISTENCE
fi

mkdir -p ./tmp
BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
cat > ./tmp/k8s.env << EOF
# TLS Bootstrapping 使用的Token，可以使用命令 head -c 16 /dev/urandom | od -An -t x | tr -d ' ' 生成
BOOTSTRAP_TOKEN="$BOOTSTRAP_TOKEN"

# 建议使用未用的网段来定义服务网段和Pod 网段
# 服务网段(Service CIDR)，部署前路由不可达，部署后集群内部使用IP:Port可达
SERVICE_CIDR="10.254.0.0/16"
# Pod 网段(Cluster CIDR)，部署前路由不可达，部署后路由可达(flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围(NodePort Range)
NODE_PORT_RANGE="10000-32766"

# flanneld 网络配置前缀
FLANNEL_ETCD_PREFIX="/kubernetes/network"

# kubernetes 服务IP(预先分配，一般为SERVICE_CIDR中的第一个IP)
CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务IP(从SERVICE_CIDR 中预先分配)
CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名
CLUSTER_DNS_DOMAIN="cluster.local."
EOF
#cp ./k8s.env ./tmp
#sed -i "/^BOOTSTRAP_TOKEN=\"/ c BOOTSTRAP_TOKEN=\"${BOOTSTRAP_TOKEN}\"" ./tmp/k8s.env

ansible all -m shell -a "mkdir -p /var/env"
ansible all -m copy -a "src=./tmp/k8s.env dest=/var/env"

# token
ansible all -m shell -a "mkdir -p /etc/kubernetes"
cat > ./tmp/token.csv << EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF
#echo -n -e "${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,\"system:kubelet-bootstrap\"" > ./tmp/token.csv
ansible all -m copy -a "src=./tmp/token.csv dest=/etc/kubernetes"


ansible master -m script -a "./put-this-ip.sh $NET_ID"
if $NODE_EXISTENCE; then
  ansible node -m script -a "./put-node-ip.sh $NET_ID"
fi

NAME=etcd

IPS=$MASTER

N=$(echo $MASTER | wc | awk -F ' ' '{print $2}')

NODE_IPS=""
ETCD_NODES=""
ETCD_ENDPOINTS=""

for i in $(seq -s ' ' 1 $N); do
  NODE_NAME="${NAME}-${i}"
  IP=$(echo $IPS | awk -v j=$i -F ' ' '{print $j}')
  NODE_IPS+=" $IP"
  ETCD_NODES+=",${NODE_NAME}=https://$IP:2380"
  ETCD_ENDPOINTS+=",https://$IP:2379"
done

#echo $NODE_IPS
#echo $ETCD_NODES
NODE_IPS=${NODE_IPS#* }
ETCD_NODES=${ETCD_NODES#*,}
ETCD_ENDPOINTS=${ETCD_ENDPOINTS#*,}
#echo $NODE_IPS
#echo $ETCD_NODES

for i in $(seq -s ' ' 1 $N); do
  FILE="./tmp/etcd.env.${i}"
  [ -e $FILE ] && rm -f $FILE
  [ -e $FILE ] || touch $FILE
  NODE_NAME="${NAME}-${i}"
  IP=$(echo $IPS | awk -v j=$i -F ' ' '{print $j}')
  cat > $FILE << EOF
export NODE_NAME=$NODE_NAME
export NODE_IPS="$NODE_IPS"
export ETCD_NODES=$ETCD_NODES
export ETCD_ENDPOINTS=$ETCD_ENDPOINTS
EOF
  ansible $IP -m copy -a "src=$FILE dest=/var/env/etcd.env"
done
if $NODE_EXISTENCE; then
  FILE="./tmp/etcd.env"
  [ -e $FILE ] && rm -f $FILE
  [ -e $FILE ] || touch $FILE
  cat > $FILE << EOF
export ETCD_NODES=$ETCD_NODES
export ETCD_ENDPOINTS=$ETCD_ENDPOINTS
EOF
  ansible node -m copy -a "src=$FILE dest=/var/env/etcd.env"
fi
rm -rf ./tmp

ansible all -m script -a ./mk-env-conf.sh

cat > ./write-to-etc_profile << EOF
FILES=\$(find /var/env -name "*.env")

if [ -n "\$FILES" ]
then
  for FILE in \$FILES
  do
    [ -f \$FILE ] && source \$FILE
  done
fi
EOF
ansible all -m copy -a "src=./write-to-etc_profile dest=/tmp"
#IF=$(cat /etc/profile | grep 'FILES=$(find \/var\/env -name "\*.env"')
ansible all -m script -a ./deal-env.sh
#fi
#ansible all -m shell -a "rm -f /tmp/write-to-etc_profile"
