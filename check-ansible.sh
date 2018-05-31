#!/bin/bash
WAIT=3
if [ ! -x "$(command -v ansible)" ]; then
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [WARN] - no ansible found, start installing."
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - wait $WAIT sec to start ... ."
  sleep $WAIT
  if [ -x "$(command -v apt-get)" ]; then
    apt-get update
    apt-get install -y software-properties-common
    apt-add-repository -y ppa:ansible/ansible
    apt-get update
    apt-get install -y ansible
  fi
  if [ -x "$(command -v yum)" ]; then
    yum makecache
    yum install -y ansible
  fi
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - ansible installed."
else
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - ansible already existed."
fi 
