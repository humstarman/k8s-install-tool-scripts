#!/bin/bash

IF0=$(cat /etc/profile | grep 'FILES=$(find \/var\/env -name "\*.env"')
if [ -z "$IF0" ]; then 
  cat /tmp/write-to-etc_profile >> /etc/profile
fi
rm -f /tmp/write-to-etc_profile
