#!/bin/bash

if [ -x "$(command -v yum)" ]; then
  FIREWALL="firewalld"
elif [ -x "$(command -v apt-get)" ]; then
  FIREWALL="ufw"
else
  echo "$(date) - $0 - [ERROR] - unknown Distributor ID."
  exit 1
fi
systemctl stop $FIREWALL
systemctl disable $FIREWALL
