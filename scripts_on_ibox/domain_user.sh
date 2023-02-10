#!/bin/bash
create=/home
for line in `cat /home/mid/box/files/listpassword_icmail.ru.csv | grep -v ^#`; do
M_USER=`echo ${line} | cut -d '|' -f1` 
M_PASS=`echo ${line} | cut -d '|' -f2` 
bash /home/mid/box/create_mail_user_SQL.sh ${M_USER} ${M_PASS} >> /home/mid/box/files/user_icmail.sql
done

for line in `cat /home/mid/box/files/listpassword_vmail.ru.csv | grep -v ^#`; do
M_USER=`echo ${line} | cut -d '|' -f1`
M_PASS=`echo ${line} | cut -d '|' -f2`
bash /home/mid/box/create_mail_user_SQL.sh ${M_USER} ${M_PASS} >> /home/mid/box/files/user_vmail.sql
done
echo "SQL for ibox created"



