#!/bin/sh
TG_BOT_ID=5116019965:AAEfqJeYZYlJzVlfYMUYYEUyGjXJcjXBbTQ
TG_CHAT_ID=541882077
#поиск письма по заданному адресу с выводом файлов и их последующем открытием и отправкой в WWPager
addr=$1
#file=/home/mid/telegram_bot/telegram-bot-bash/bin/queue/file
#post_filter=/home/mid/telegram_bot/telegram-bot-bash/bin/queue/post_filter
#echo $1 > ip
mail_tg=mid@wwpager.ru
find /spool2/CommuniGate/Queue -name \*.msg | while read j
do
	head -500 $j | grep -E $addr > /dev/null && echo $j >> file
done 
	exec 6<&0
	exec < file
		read a1
		read a2
		read a3
		read a4
		read a5
	exec 3<&-
#....
#cat $file
echo "=========1 письмо=======" > post_filter
echo $a1 >> post_filter
	head -n 10 $a1  >> post_filter
echo "                            " >> post_filter
echo "=========2 письмо=======" >> post_filter
echo $a2 >> post_filter
	head -n 10 $a2 >> post_filter
echo "                            " >> post_filter
echo "=========3 письмо=======" >> post_filter
echo $a3 >> post_filter
	head -n 10 $a3 >> post_filter
echo "                            " >> post_filter
echo "=========4 письмо=======" >> post_filter
echo $a4 >> post_filter
	head -n 10 $a4 >> post_filter
echo "                            " >> post_filter
echo "=========5 письмо=======" >> post_filter
echo $a5 >> post_filter
	head -n 10 $a5 >> post_filter
curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_CHAT_ID -d \
      text="$(cat post_filter)" >> /dev/null
rm post_filter 
mv file file2
to=$(head -n 10 $a1 | grep "R W" | sed 's|.*<||' | sed 's/>//'| cut -d ' ' -f1)
to2=$(head -n 10 $a2 | grep "R W" | sed 's|.*<||' | sed 's/>//'| cut -d ' ' -f1)
#echo $to
#echo $to2
cat $a1 | sed -e 's/'$to'/'$mail_tg'/g'| sed '1,/R W/ d'| sed -e '1d' > /spool1/CommuniGate/Submitted/a1.sub
cat $a2 | sed -e 's/'$to2'/'$mail_tg'/g'| sed '1,/R W/ d'| sed -e '1d' > /spool1/CommuniGate/Submitted/a2.sub
