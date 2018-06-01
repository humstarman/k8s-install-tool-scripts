#!/bin/bash

set -e

# 1 download and install CFSSL
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - download kubernetes ... "
# kubernetes-v3.3.2-linux-amd64.tar.gz
KUBE_VER=v1.10.2
URL=https://dl.k8s.io/$KUBE_VER
if [ ! -f ./kubernetes-server-linux-amd64.tar.gz ]; then
  while true; do
    wget $URL/kubernetes-server-linux-amd64.tar.gz && break
  done
fi
if [[ ! -x "$(command -v kubectl)" ]]; then
  while true; do
    # master
    #wget https://github.com/coreos/kubernetes/releases/download/$KUBE_VER/kubernetes-$KUBE_VER-linux-amd64.tar.gz
    tar -zxvf kubernetes-server-linux-amd64.tar.gz 
    BIN=kube-master-bin
    mkdir -p kubernetes/server/bin/$BIN
    cd kubernetes/server/bin && \
      mv kube-apiserver $BIN && \
      mv kube-controller-manager $BIN && \
      mv kube-scheduler $BIN && \
      cd -
    echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute Kubernetes master components ... "
    ansible master -m copy -a "src=./kubernetes/server/bin/$BIN/ dest=/usr/local/bin mode='a+x'"
    # node
    BIN=kube-node-bin
    mkdir -p kubernetes/server/bin/$BIN
    cd kubernetes/server/bin && \
      mv kubelet $BIN && \
      mv kube-proxy $BIN && \
      mv kubectl $BIN && \
      cd -
    echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - distribute Kubernetes node components ... "
    ansible all -m copy -a "src=./kubernetes/server/bin/$BIN/ dest=/usr/local/bin mode='a+x'"
    if [[ -x "$(command -v kubectl)" ]]; then
      echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - kubernetes installed."
      break
    fi
  done
else
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - kubernetes already existed. "
fi
