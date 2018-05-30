#!/bin/bash
if [ ! -f ./master.csv ]; then
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [ERROR] - no master config file -- master.csv found!"
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [ERROR] - put master info into ./master.csv in term of CSV."
  sleep 3
  exit 1
fi
echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - master configured."
if [ ! -f ./node.csv ]; then
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [WARN] - no node config file -- node.csv found!"
else
  echo "$(date -d today +'%Y-%m-%d %H:%M:%S') - [INFO] - node configured."
fi
exit 0
