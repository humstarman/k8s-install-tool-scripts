#!/bin/bash

# 1 download and install CFSSL
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - download etcd ... "
# etcd-v3.3.2-linux-amd64.tar.gz
ETCD_VER=v3.3.2
if [ ! -f "etcd-$ETCD_VER-linux-amd64.tar.gz" ]; then
  while true; do
    wget https://github.com/coreos/etcd/releases/download/$ETCD_VER/etcd-$ETCD_VER-linux-amd64.tar.gz 
    if [ -f "etcd-$ETCD_VER-linux-amd64.tar.gz" ]; then
      echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - CFSSL installed."
      break
    fi
  done
else
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - CFSSL already existed. "
fi
tar -zxvf etcd-$ETCD_VER-linux-amd64.tar.gz
mkdir -p ./etcd-$ETCD_VER-linux-amd64/bin
mv ./etcd-$ETCD_VER-linux-amd64/etcd ./etcd-$ETCD_VER-linux-amd64/bin
mv ./etcd-$ETCD_VER-linux-amd64/etcdctl ./etcd-$ETCD_VER-linux-amd64/bin
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute etcd ... "
ansible master -m copy -a "src=./etcd-$ETCD_VER-linux-amd64/bin/ dest=/usr/local/bin mode='a+x'"

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

cd ./ssl/ca && \
  cfssl gencert -initca ca-csr.json | cfssljson -bare ca && \
  cd -

# 4 distribute ca pem
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute CA pem ... "
ansible all -m copy -a "src=ssl/ca/ dest=/etc/kubernetes/ssl"
