#!/bin/bash
#Задаем список ip адресов
ipaddr1= 1.1.1.1
ipaddr2= 2.2.2.2
ipaddr3= 3.3.3.3
ipaddr4= 4.4.4.4
ipaddr5= 5.5.5.5 
#проверяем с какого ip идет отправка
#addr=$1
addr=$(sed -n 368p /etc/postfix/main.cf |  sed -e "s/^.\{,20\}//")
echo "текущий адрес $addr"
#Проверяем ip адрес в блэклисте
	#получаем реверс ip
	rev_ip=$(echo $addr | awk -F. '{print $4"."$3"." $2"."$1}')
	rev_ip1=$(echo $ipaddr1 | awk -F. '{print $4"."$3"." $2"."$1}')
	rev_ip2=$(echo $ipaddr2 | awk -F. '{print $4"."$3"." $2"."$1}')
	rev_ip3=$(echo $ipaddr3 | awk -F. '{print $4"."$3"." $2"."$1}')
	rev_ip4=$(echo $ipaddr4 | awk -F. '{print $4"."$3"." $2"."$1}')
	rev_ip5=$(echo $ipaddr5 | awk -F. '{print $4"."$3"." $2"."$1}')
#проверяем активный ip в основных спам-базах - барракуда и спамхаус
	result=$(host -t TXT $rev_ip.zen.spamhaus.org)
	result2=$(host -t TXT $rev_ip.b.barracudacentral.org)
	echo $result 
	echo $result2
#проверяем все ip на локальном интерфейсе
	result_addr1=$(host -t TXT $rev_ip1.zen.spamhaus.org)
	result2_addr1=$(host -t TXT $rev_ip1.b.barracudacentral.org)
	result_addr2=$(host -t TXT $rev_ip2.zen.spamhaus.org)
	result2_addr2=$(host -t TXT $rev_ip2.b.barracudacentral.org)
	result_addr3=$(host -t TXT $rev_ip3.zen.spamhaus.org)
	result2_addr3=$(host -t TXT $rev_ip3.b.barracudacentral.org)
	result_addr4=$(host -t TXT $rev_ip4.zen.spamhaus.org)
	result2_addr4=$(host -t TXT $rev_ip4.b.barracudacentral.org)
	result_addr5=$(host -t TXT $rev_ip5.zen.spamhaus.org)
	result2_addr5=$(host -t TXT $rev_ip5.b.barracudacentral.org)
#если ip находится в спаме, то меняем на один из адресов
#если в host отдает not found: 3(NXDOMAIN)
	if [[ $result == *"not found"* ]] && [[ $result2 == *"not found"* ]]; then
		echo "ip-адрес не заблокирован"
#если нет not found, то меняем ip в конфиге, проверяя на блокировку каждый из адресов. Тот адрес который не числится в списках устанавливается в качестве активного
	elif [[ $result != *"not found"* ]] || [[ $result2 != *"not found"* ]]; then
	#если использовался 1 адрес
		 if [[ $addr = $ipaddr1 ]] && [[ $result_addr2  == *"not found"* ]] && [[ $result2_addr2  == *"not found"* ]]; then
				postconf -e smtp_bind_address=$ipaddr2
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr2"
			elif [[ $addr = $ipaddr1 ]] && [[ $result_addr3  == *"not found"* ]] && [[ $result2_addr3  == *"not found"* ]]; then
				postconf -e smtp_bind_address=$ipaddr3
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr3"
			elif [[ $addr = $ipaddr1 ]] && [[ $result_addr4  == *"not found"* ]] && [[ $result2_addr4  == *"not found"* ]]; then
                        	postconf -e smtp_bind_address=$ipaddr4
                        	service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr4"
			elif [[ $addr = $ipaddr1 ]] && [[ $result_addr5  == *"not found"* ]] && [[ $result2_addr5  == *"not found"* ]]; then
				postconf -e smtp_bind_address=$ipaddr5
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr5"
	#если использовался 2 адрес
			elif [[ $addr = $ipaddr2 ]] && [[ $result_addr1  == *"not found"* ]] && [[ $result2_addr1  == *"not found"* ]]; then
                                postconf -e smtp_bind_address=$ipaddr4
                                service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr1"
			elif [[ $addr = $ipaddr2 ]] && [[ $result_addr3  == *"not found"* ]] && [[ $result2_addr3  == *"not found"* ]]; then
                                postconf -e smtp_bind_address=$ipaddr3
                                service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr3"
			elif [[ $addr = $ipaddr2 ]] && [[ $result_addr4  == *"not found"* ]] && [[ $result2_addr4  == *"not found"* ]]; then
                                postconf -e smtp_bind_address=$ipaddr4
                                service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr4"
			elif [[ $addr = $ipaddr2 ]] && [[ $result_addr5  == *"not found"* ]] && [[ $result2_addr5  == *"not found"* ]]; then
				postconf -e smtp_bind_address=$ipaddr5
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr5"
	#если использовался 3 адрес
			elif [[ $addr = $ipaddr3 ]] && [[ $result_addr1  == *"not found"* ]] && [[ $result2_addr1  == *"not found"* ]]; then
                                postconf -e smtp_bind_address=$ipaddr1
                                service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr1"
                        elif [[ $addr = $ipaddr3 ]] && [[ $result_addr2  == *"not found"* ]] && [[ $result2_addr2 == *"not found"* ]]; then
                                postconf -e smtp_bind_address=$ipaddr2
                                service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr2"
                        elif [[ $addr = $ipaddr3 ]] && [[ $result_addr4  == *"not found"* ]] && [[ $result2_addr4  == *"not found"* ]]; then
                                postconf -e smtp_bind_address=$ipaddr4
                                service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr4"
			elif [[ $addr = $ipaddr3 ]] && [[ $result_addr5  == *"not found"* ]] && [[ $result2_addr5  == *"not found"* ]]; then
				postconf -e smtp_bind_address=$ipaddr5
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr5"
	#если использовался 4 адрес
			elif [[ $addr = $ipaddr4 ]] && [[ $result_addr1  == *"not found"* ]] && [[ $result2_addr1  == *"not found"* ]]; then
                                postconf -e smtp_bind_address=$ipaddr1
                                service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr1"
                        elif [[ $addr = $ipaddr4 ]] && [[ $result_addr2  == *"not found"* ]] && [[ $result2_addr2 == *"not found"* ]]; then
                                postconf -e smtp_bind_address=$ipaddr2
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr2"
                        elif [[ $addr = $ipaddr4 ]] && [[ $result_addr3  == *"not found"* ]] && [[ $result2_addr3  == *"not found"* ]]; then
                                postconf -e smtp_bind_address=$ipaddr3
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr3" 
			elif [[ $addr = $ipaddr4 ]] && [[ $result_addr5  == *"not found"* ]] && [[ $result2_addr5  == *"not found"* ]]; then
				postconf -e smtp_bind_address=$ipaddr5
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr5"
	#если использовался 5 адрес
			elif [[ $addr = $ipaddr5 ]] && [[ $result_addr1  == *"not found"* ]] && [[ $result2_addr1  == *"not found"* ]]; then
				postconf -e smtp_bind_address=$ipaddr1
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr1"
			elif [[ $addr = $ipaddr5 ]] && [[ $result_addr2  == *"not found"* ]] && [[ $result2_addr2  == *"not found"* ]]; then
				postconf -e smtp_bind_address=$ipaddr2
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr2"
			elif [[ $addr = $ipaddr5 ]] && [[ $result_addr3  == *"not found"* ]] && [[ $result2_addr3  == *"not found"* ]]; then
				postconf -e smtp_bind_address=$ipaddr3
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr3"
			elif [[ $addr = $ipaddr5 ]] && [[ $result_addr4  == *"not found"* ]] && [[ $result2_addr4  == *"not found"* ]]; then
				postconf -e smtp_bind_address=$ipaddr4
				service postfix restart
				echo " Адрес $addr в спам-листах. Меняю на $ipaddr4"
		fi
	fi

