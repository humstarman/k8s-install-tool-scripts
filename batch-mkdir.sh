#!/bin/bash

ansible all -m shell -a "mkdir -p /var/env && mkdir -p /etc/kubernetes/ssl && mkdir -p /etc/flanneld/ssl && mkdir -p /var/lib/kubelet && mkdir -p /var/lib/kube-proxy && mkdir -p /etc/kubernetes/manifests && mkdir -p /etc/calico && mkdir -p /etc/harbor/ssl && mkdir -p /etc/etcd/ssl"

ansible master -m shell -a "mkdir -p /var/lib/etcd"
