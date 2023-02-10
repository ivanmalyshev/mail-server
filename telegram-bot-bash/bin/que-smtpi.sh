#!/bin/sh
find /spool2/CommuniGate/Queue -name \*.msg | while read j
do
#head -4 $j | grep -E  "^S SMTP"
head -10 $j | grep -E "Received: from"
done
