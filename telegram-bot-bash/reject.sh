#!/bin/bash
TG_BOT_ID=5338397560:AAEEtsAUGfzExh7Syv0H8BJUkpARHeqmuDE
TG_CHAT_ID=541882077
file=/home/mid/telegram_bot/telegram-bot-bash/file2
log=/home/mid/telegram_bot/telegram-bot-bash/log
./RejectMessages $file >> $log  && curl -X POST https://api.telegram.org/bot$TG_BOT_ID/sendMessage -d chat_id=$TG_CHAT_ID -d \
      text="cat $log" >> /dev/null && rm $file
