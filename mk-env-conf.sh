#!/bin/bash

FILES=$(find /var/env -name "*.env")
DEST=/tmp/env.conf
[ -f $DEST ] && rm $DEST
[ -f $DEST ] || touch $DEST

if [ -n "$FILES" ]
then
  for FILE in $FILES
  do
    cat $FILE >> $DEST
  done
fi

# renove 'export'
sed -i 's/export //g' $DEST
# del commit
sed -i '/^#/d' $DEST
# del blank
sed -i '/^$/d' $DEST

mv $DEST /var/env
