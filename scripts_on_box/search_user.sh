#!/bin/bash
#echo "icmail.ru/vmail.ru"
#read domain
domain=$1
#получаем файл в виде  2 строк для каждого ящика
#1.email
#2.дата и время последнего входа
cd /home/mid/SCRIPT/migrate
find /spool1/CommuniGate/Domains/$domain/ -name 'account.info'| while read j
	do
		llogin=$(head -15 $j | grep -i "#LastLogin")
		#echo $j >> stat #для проверки вывода
		echo $j  > stat1 #Список директорий
		kpp=$(rev stat1 | cut -c 5- | rev | sed s/$/settings/g)
		#echo $kpp > 1
		accsize=$(head -15 $kpp | grep -i "MaxAccountSize")
		#echo $accsize > 1
			if [ "$domain" = "icmail.ru" ]; then
				sed -e "s/^.\{,38\}//;s/.\{,19\}$//" stat1 | sed s/$/@$domain/g >> stat2 #для icmail
			elif [ "$domain" = "vmail.ru" ]; then
				sed -e "s/^.\{,37\}//;s/.\{,19\}$//" stat1 | sed s/$/@$domain/g >> stat2 #для vmail
			fi
		echo $llogin >> stat2 #Получаем список с датой последнего логина пользователя
		echo $accsize >> stat2 #Добавляем квоту
		echo "_______________" >> stat2
	done
cat stat2 | grep '2022\|2023' -B 1 -A 1 > last_login_$domain #фильтруем по году, забираем в список всех от 2021
rm stat1 stat2
cat last_login_$domain | grep $domain > act_user_$domain
cat last_login_$domain  | grep "$domain\|MaxAccountSize" | sed 'N;s/\n/ /' | sed 's/MaxAccountSize = //' | rev | cut -c3- | rev > quota_$domain.txt
sed "s/.*/processAccount ('&');/" act_user_$domain > 2
rm act_user_$domain
sed '31r 2' listPasswords.pl > listPasswords_$domain.pl
rm 2
chmod +x listPasswords_$domain.pl
./listPasswords_$domain.pl > listpassword_$domain.csv
rm listPasswords_$domain.pl last_login_$domain
chown mid:mid listpassword_$domain.csv
chown mid:mid quota_$domain.txt
mv listpassword_* quota_* /home/mid/SCRIPT/migrate/files
