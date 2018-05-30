#!/bin/bash
PASSWD=$1
if [ -z "$PASSWD" ]; then
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [ERROR] - need the password." 
fi
if [ ! -x "$(command -v expect)" ]; then
  if [ -x "$(command -v apt-get)" ]; then
    apt-get update
    apt-get install -y tcl tk expect
  fi
  if [ -x "$(command -v yum)" ]; then
    yum makecache
    yum install -y tcl tk expect
  fi
fi
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
fi
MASTER=$(sed s/","/" "/g ./master.csv)
for ip in $MASTER; do
  ./auto-cp-ssh-id.sh root $PASSWD $ip 
done
NODE=$(sed s/","/" "/g ./node.csv)
for ip in $NODE; do
  ./auto-cp-ssh-id.sh root $PASSWD $ip 
done
