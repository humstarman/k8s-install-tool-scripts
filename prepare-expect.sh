#!/bin/bash
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
