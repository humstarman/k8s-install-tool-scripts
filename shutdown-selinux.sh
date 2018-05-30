#!/bin/bash

# temporary
if [ -x "$(command -v setenforce)" ]; then
  setenforce 0
fi
# for ever
if [ -f "/etc/selinux/config" ]; then
  sed -i s/"SELINUX=enforcing"/"SELINUX=disabled"/g /etc/selinux/config
fi
