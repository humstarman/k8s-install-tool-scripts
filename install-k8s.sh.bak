#!/bin/bash

set -e

# 1 download and install CFSSL
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - download kubernetes ... "
# kubernetes-v3.3.2-linux-amd64.tar.gz
KUBE_VER=v1.10.2
if [ ! -f ./kubernetes-server-linux-amd64.tar.gz ]; then
  while true; do
    wget https://dl.k8s.io/$KUBE_VER/kubernetes-server-linux-amd64.tar.gz && break
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
      cp kube-apiserver $BIN && \
      cp kube-controller-manager $BIN && \
      cp kube-scheduler $BIN && \
      cp kubelet $BIN && \
      cp kube-proxy $BIN && \
      cp kubectl $BIN && \
      cd -
    ansible master -m copy -a "src=./kubernetes/server/bin/$BIN/ dest=/usr/local/bin mode='a+x'"
    # node
    NODE_EXISTENCE=true
    if [ ! -f ./node.csv ]; then
      NODE_EXISTENCE=false
    else
      if [ -z "$(cat ./node.csv)" ]; then
        NODE_EXISTENCE=false
      fi
    fi
    if $NODE_EXISTENCE; then
      BIN=kube-node-bin
      mkdir -p kubernetes/server/bin/$BIN
      cd kubernetes/server/bin && \
        cp kubelet $BIN && \
        cp kube-proxy $BIN && \
        cp kubectl $BIN && \
        cd -
      ansible node -m copy -a "src=./kubernetes/server/bin/$BIN/ dest=/usr/local/bin mode='a+x'"
    fi
    #
    if [[ -x "$(command -v kubectl)" ]]; then
      echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - kubernetes installed."
      break
    fi
  done
else
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - kubernetes already existed. "
fi
