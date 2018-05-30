#!/bin/bash

# 1 download and install CFSSL
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - download CFSSL ... "
if [[ ! -x "$(command -v cfssl)" && ! -x "$(command -v cfssljson)" && ! -x "$(command -v cfssl-certinfo)" ]]; then
  while true; do
    wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
    chmod +x cfssl_linux-amd64
    mv cfssl_linux-amd64 /usr/local/bin/cfssl
    wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
    chmod +x cfssljson_linux-amd64
    mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
    wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
    chmod +x cfssl-certinfo_linux-amd64
    mv cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
    if [[ -x "$(command -v cfssl)" && -x "$(command -v cfssljson)" && -x "$(command -v cfssl-certinfo)" ]]; then
      echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - CFSSL installed."
      break
    fi
  done
else
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - CFSSL already existed. "
fi

echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - generate CA pem ... "
# 2 generate template
mkdir -p ./ssl/ca
cd ./ssl/ca && \
  cfssl print-defaults config > config.json && \
  cfssl print-defaults csr > csr.json && \
  cd -

# 3 generate ca
FILE=./ssl/ca/ca-config.json
cat > $FILE << EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "87600h"
      }
    }
  }
}
EOF
FILE=./ssl/ca/ca-csr.json
cat > $FILE << EOF
{
  "CN": "kubernetes",
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
