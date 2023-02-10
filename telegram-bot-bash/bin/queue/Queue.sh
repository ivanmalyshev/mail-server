#!/bin/bash
Queue=/spool2/CommuniGate/Queue/
#Queue=/spool2/CommuniGate/Old/Old2/
bold=$(tput bold)
normal=$(tput sgr0)
Old=/spool2/CommuniGate/Old/
Scripts=/spool2/CommuniGate/
TG_BOT_ID=5338397560:AAEEtsAUGfzExh7Syv0H8BJUkpARHeqmuDE #токен бота
TG_CHAT_ID=541882077 #id чата в боте
TG_WORK_ID=-1001435958867 #id work support
#msh=/spool2/CommuniGate/m.sh
cd $Queue #переходим в папку с очередью
queue=$(find . -type f | wc -l) #количество в очереди
cd $Scripts 
#если папка Queue содержит более N писем - то запускаем скрипты
if [[ $queue -ge 7000 ]]
  then
 /home/mid/SCRIPT/queue/que-smtpi.sh | sort | uniq -c | sort -n > sort
        sort2=$(tail -n 5 sort)
        rm sort
echo "=====топ 5 SMTP-адресов=====" > top
echo "$sort2" | awk -F'[\t,]' '{print $1 $2 $4 $5 $6}' >> top 
        curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_CHAT_ID -d \
        text="$(cat top)" >> /dev/null
rm top
	echo "Queue $queue. Run scripts"
	#######отправляем отчет в бота тг##########
	curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_CHAT_ID -d \
        text="box.vrn.ru Количество писем $queue. Запускаю скрипты"
	curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_WORK_ID -d \
        text="box.vrn.ru Количество писем queue. Запускаю скрипты" 
	###################################
	./m.sh > dmm
	./s.sh > dss
	./RejectMessages dmm
	./RejectMessages dss
	cd $Old
	old=$(find *.msg -type f | wc -l)
	cd $Queue
	queue1=$(find . -type f | wc -l)
	#########отчет о сбросе очереди, количество писем################
	echo "Queue reset $queue1. Number of letters $old" | mail -s "Error: Queue_box" tp@ic.vrn.ru,vetrov@vmail.ru,postmaster@icmail.ru
	curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_CHAT_ID -d \
	text="box.vrn.ru. WARNING!!!! Очередь сбросил $queue1. Количество писем $old"
	curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_WORK_ID -d \
        text="box.vrn.ru. WARNING!!!! Большое количество писем. Количество сброшенных писем $old. Очередь после сброса $queue1"
	######################################################################
	
 else
	#####если порог меньше N писем - то отправляем отчет что все хорошо в почту и тг
  echo "Queue $queue. No queue reset required" | mail -s "Queue_box" mid@icmail.ru
	curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_CHAT_ID -d \
        text="box.vrn.ru Количество писем $queue." >> /dev/null
	/home/mid/SCRIPT/queue/que-smtpi.sh | sort | uniq -c | sort -n > sort
	sort2=$(tail -n 5 sort)
	rm sort
echo -e "=====ТОП 5 SMTP-АДРЕСОВ=====" > top
echo "$sort2" | awk -F'[\t,]' '{print $1 $2 $4 $5 $6}' >> top
	curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_CHAT_ID -d \
      	text="$(cat top)" >> /dev/null
rm top
	#curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_WORK_ID -d \
        #text="box.vrn.ru Количество писем $queue."
	######################################################################
  fi
