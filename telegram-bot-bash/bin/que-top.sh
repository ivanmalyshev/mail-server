#!/bin/bash
TG_BOT_ID=5338397560:AAEEtsAUGfzExh7Syv0H8BJUkpARHeqmuDE #токен бота
TG_CHAT_ID=541882077 #id чата в боте
./que-smtpi.sh | sort | uniq -c | sort -n > sort
sort2=$(tail -n 5 sort)
rm sort
echo "=====топ 5 SMTP-адресов=====" > top
echo "$sort2" | awk -F'[\t,]' '{print $1 $2 $4 $5 $6}' >> top
#пример отчета:
#=====топ 5 SMTP-адресов=====
#49Received:nalissam.tk([87.251.85.36]verified)
#54Received:[195.98.93.46](accountit_infomail@frakht.vrn.ru
#83Received:relay.vrn.ru([195.98.90.71]verified)
#133Received:[212.12.20.167](accountit_infomail@frakht.vrn.ru
#142Received:[78.110.255.211](accountit_infomail@frakht.vrn.ru
echo "$sort2" #| awk '{print $1 $4}' >> sort
curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_CHAT_ID -d \
      text="$(cat top)" >> /dev/null
rm top
#exec 6<&0
#exec < sort
#read a1
#read a2
#read a3
#read a4
#read a5
#echo $a1
#echo $a2
#echo $a3
#echo $a4
#echo $a5
