#!/bin/bash
##################################################################
#
# File: bashbot.sh 
# Note: DO NOT EDIT! this file will be overwritten on update
# shellcheck disable=SC2140,SC2031,SC2120,SC1091,SC1117,SC2059
#
# Description: bashbot, the Telegram bot written in bash.
#
#     Written by Drew (@topkecleon) KayM (@gnadelwartz).
#     Also contributed: Daniil Gentili (@danog), JuanPotato, BigNerd95,
#                       TiagoDanin, iicc1, dcoomber
#     https://github.com/topkecleon/telegram-bot-bash
#
#     This file is public domain in the USA and all free countries.
#     Elsewhere, consider it to be WTFPLv2. (wtfpl.net/txt/copying)
#
# Usage: bashbot.sh BOTCOMMAND
BOTCOMMANDS="-h  help  init  start  stop  status  suspendback  resumeback  killback"
#
# Exit Codes:
#     0 - success (hopefully)
#     1 - can't change to dir
#     2 - can't write to tmp, count or token
#     3 - user / command / file not found
#     4 - unknown command
#     5 - cannot start, stop or get status
#     6 - mandatory module not found
#     7 - can't get bottoken
#     8 - curl/wget missing
#     10 - not bash!
#
#### $$VERSION$$ v1.51-dev-23-g69b1871
##################################################################

# are we running in a terminal?
NN="\n"
if [ -t 1 ] && [ -n "${TERM}" ];  then
    INTERACTIVE='yes'
    RED='\e[31m'
    GREEN='\e[32m'
    ORANGE='\e[35m'
    GREY='\e[1;30m'
    NC='\e[0m'
    NN="${NC}\n"
fi
declare -r INTERACTIVE RED GREEN ORANGE GREY NC NN

# telegram uses utf-8 characters, check if we have an utf-8 charset
if [ "${LANG}" = "${LANG%[Uu][Tt][Ff]*}" ]; then
	printf "${ORANGE}Warning: Telegram uses utf-8, but looks like you are using non utf-8 locale:${NC} ${LANG}\n"
fi

# we need some bash 4+ features, check for old bash by feature
if [ "$({ LC_ALL=C.utf-8 printf "%b" "\u1111"; } 2>/dev/null)" = "\u1111" ]; then
	printf "${ORANGE}Warning: Missing unicode '\uxxxx' support, missing C.utf-8 locale or to old bash version.${NN}"
fi


# in UTF-8 äöü etc. are part of [:alnum:] and ranges (e.g. a-z), but we want ASCII a-z ranges!
# for more information see  doc/4_expert.md#Character_classes
azazaz='abcdefghijklmnopqrstuvwxyz'	# a-z   :lower:
AZAZAZ='ABCDEFGHIJKLMNOPQRSTUVWXYZ'	# A-Z   :upper:
o9o9o9='0123456789'			# 0-9   :digit:
azAZaz="${azazaz}${AZAZAZ}"	# a-zA-Z	:alpha:
azAZo9="${azAZaz}${o9o9o9}"	# a-zA-z0-9	:alnum:

# some important helper functions
# returns true if command exist
_exists() {
	[ "$(type -t "$1")" = "file" ]
}
# execute function if exists
_exec_if_function() {
	[ "$(type -t "$1")" != "function" ] && return 1
	"$@"
}
# returns true if function exist
_is_function() {
	[ "$(type -t "$1")" = "function" ]
}
# round $1 in international notation! , returns float with $2 decimal digits
# if $2 is not given or is not a positive number zero is assumed
_round_float() {
	local digit="$2"; [[ "$2" =~ ^[${o9o9o9}]+$ ]] || digit="0"
	: "$(LC_ALL=C printf "%.${digit}f" "$1" 2>/dev/null)"
	printf "%s" "${_//,/.}"	# make more LANG independent
}
# date is external, printf is much faster
_date(){
	printf "%(%c)T\n" -1
}
setConfigKey() {
	[[ "$1" =~ ^[-${azAZo9},._]+$ ]] || return 3
	[ -z "${BOTCONFIG}" ] && return 1
	printf '["%s"]\t"%s"\n' "${1//,/\",\"}" "${2//\"/\\\"}" >>"${BOTCONFIG}.jssh"
}
getConfigKey() {
	[[ "$1" =~ ^[-${azAZo9},._]+$ ]] || return 3
	[ -r "${BOTCONFIG}.jssh" ] && sed -n 's/\["'"$1"'"\]\t*"\(.*\)"/\1/p' "${BOTCONFIG}.jssh" | tail -n 1
}
# escape characters in json strings for telegram 
# $1 string, output escaped string
JsonEscape(){
	sed -E -e 's/\r//g' -e 's/([-"`´,§$%&/(){}#@!?*.\t])/\\\1/g' <<< "${1//$'\n'/\\n}"
}
# clean \ from escaped json string
# $1 string, output cleaned string
cleanEscape(){	# remove "	all \ but  \n\u		\n or \r
	sed -E -e 's/\\"/+/g' -e 's/\\([^nu])/\1/g' -e 's/(\r|\n)//g' <<<"$1"
}
# check if $1 seems a valid token
# return true if token seems to be valid
check_token(){
	[[ "$1" =~ ^[${o9o9o9}]{8,10}:[${azAZo9}_-]{35}$ ]] && return 0
	return 1
}
# log $1 with date
log_error(){ printf "%(%c)T: %s\n" -1 "$*" >>"${ERRORLOG}"; }
log_debug(){ printf "%(%c)T: %s\n" -1 "$*" >>"${DEBUGLOG}"; }
log_update(){ printf "%(%c)T: %s\n" -1 "$*" >>"${UPDATELOG}"; }
# log $1 with date, special first \n
log_message(){ printf "\n%(%c)T: %s\n" -1 "${1/\\n/$'\n'}" >>"${MESSAGELOG}"; }
# curl is preferred, try detect curl even not in PATH
# sets BASHBOT_CURL to point to curl
DETECTED_CURL="curl"
detect_curl() {
	local file warn="Warning: Curl not detected, try fallback to wget! pls install curl or adjust BASHBOT_CURL/BASHBOT_WGET environment variables."
	# custom curl command
	[ -n "${BASHBOT_CURL}" ] && return 0
	# use wget
	[ -n "${BASHBOT_WGET}" ] && DETECTED_CURL="wget" && return 1
	# default use curl in PATH
	BASHBOT_CURL="curl"
	_exists curl && return 0
	# search in usual locations
	for file in /usr/bin /bin /usr/local/bin; do
		[ -x "${file}/curl" ] && BASHBOT_CURL="${file}/curl" && return 0
	done
	# curl not in PATH and not in usual locations
	DETECTED_CURL="wget"
	log_update "${warn}"; [ -n "${BASHBOTDEBUG}" ] && log_debug "${warn}"
	return 1
}

# additional tests if we run in debug mode
export BASHBOTDEBUG
[[ "${BASH_ARGV[0]}" == *"debug"* ]] && BASHBOTDEBUG="yes"

# $1 where $2 command $3 may debug 
# shellcheck disable=SC2094
debug_checks(){ {
	[  -z "${BASHBOTDEBUG}" ] && return
	local token where="$1"; shift
	printf "%(%c)T: debug_checks: %s: bashbot.sh %s\n" -1 "${where}" "${1##*/}"
	# shellcheck disable=SC2094
	[ -z "${DEBUGLOG}" ] && printf "%(%c)T: %s\n" -1 "DEBUGLOG not set! =========="
	token="$(getConfigKey "bottoken")"
	[ -z "${token}" ] && printf "%(%c)T: %s\n" -1 "Bot token is missing! =========="
	check_token "${token}" || printf "%(%c)T: %s\n%s\n" -1 "Invalid bot token! ==========" "${token}"
	[ -z "$(getConfigKey "botadmin")" ] && printf "%(%c)T: %s\n" -1 "Bot admin is missing! =========="
	# call user defined debug_checks if exists
	_exec_if_function my_debug_checks "$(_date)" "${where}" "$*"
	} 2>/dev/null >>"${DEBUGLOG}"
}

# some Linux distributions (e.g. Manjaro) doesn't seem to have C locale activated by default
if _exists locale && [ "$(locale -a | grep -c -e "^C$" -e "^C.[uU][tT][fF]")" -lt 2 ]; then
	printf "${ORANGE}Warning: locale ${NC}${GREY}C${NC}${ORANGE} and/or ${NC}${GREY}C.utf8${NC}${ORANGE} seems missing, use \"${NC}${GREY}locale -a${NC}${ORANGE}\" to show what locales are installed on your system.${NN}"
fi

# get location and name of bashbot.sh
SCRIPT="$0"
REALME="${BASH_SOURCE[0]}"
SCRIPTDIR="$(dirname "${REALME}")"
RUNDIR="$(dirname "$0")"

MODULEDIR="${SCRIPTDIR}/modules"

# adjust stuff for source, use return from source without source
exit_source() { exit "$1"; }
if [[ "${SCRIPT}" != "${REALME}" || "$1" == "source" ]]; then
	SOURCE="yes"
	SCRIPT="${REALME}"
	[ -z "$1" ] && exit_source() { printf "Exit from source ...\n"; return "$1"; }
fi

# emmbeded system may claim bash but it is not
# check for bash like ARRAY handlung
if ! (unset a; set -A a a; eval "a=(a b)"; eval '[ -n "${a[1]}" ]'; ) > /dev/null 2>&1; then
	printf "Error: Current shell does not support ARRAY's, may be busybox ash shell. pls install a real bash!\n"
	exit_source 10
fi

# adjust path variables
if [ -n "${BASHBOT_HOME}" ]; then
	SCRIPTDIR="${BASHBOT_HOME}"
 else
	BASHBOT_HOME="${SCRIPTDIR}"
fi
[ -z "${BASHBOT_ETC}" ] && BASHBOT_ETC="${BASHBOT_HOME}"
[ -z "${BASHBOT_VAR}" ] && BASHBOT_VAR="${BASHBOT_HOME}"

ADDONDIR="${BASHBOT_ETC:-.}/addons"
RUNUSER="${USER}"	# save original USER

# provide help
case "$1" in
	"") [ -z "${SOURCE}" ] && printf "${ORANGE}Available commands: ${GREY}${BOTCOMMANDS}${NN}" && exit
		;;
	"-h"*)	LOGO="${BASHBOT_HOME:-.}/doc/bashbot.ascii"
		{ [ -r "${LOGO}" ] && cat "${LOGO}"
		sed -nE -e '/(NOT EDIT)|(shellcheck)/d' -e '3,/###/p' "$0"; } | more
		exit;;
	"help") HELP="${BASHBOT_HOME:-.}/README"
		if [ -n "${INTERACTIVE}" ];then
			_exists w3m && w3m "${HELP}.html" && exit
			_exists lynx && lynx "${HELP}.html" && exit
			_exists less && less "${HELP}.txt" && exit
		fi
		cat "${HELP}.txt"
		exit;;
esac

# OK, ENVIRONMENT is set up, let's do some additional tests
if [[ -z "${SOURCE}" && -z "${BASHBOT_HOME}" ]] && ! cd "${RUNDIR}" ; then
	printf "${RED}ERROR: Can't change to ${RUNDIR} ...${NN}"
	exit_source 1
fi
RUNDIR="."
[ ! -w "." ] && printf "${ORANGE}WARNING: ${RUNDIR} is not writeable!${NN}"

# check if JSON.sh is available
JSONSHFILE="${BASHBOT_JSONSH:-${SCRIPTDIR}/JSON.sh/JSON.sh}"
if [ ! -x "${JSONSHFILE}" ]; then
	printf "${RED}ERROR:${NC} ${JSONSHFILE} ${RED}does not exist, are we in dev environment?${NN}${GREY}%s${NN}\n"\
		"\$JSONSHFILE is set wrong or bashbot is not installed correctly, see doc/0_install.md"
	exit_source 3
fi

# file locations based on ENVIRONMENT
BOTCONFIG="${BASHBOT_ETC:-.}/botconfig"
BOTACL="${BASHBOT_ETC:-.}/botacl"
DATADIR="${BASHBOT_VAR:-.}/data-bot-bash"
BLOCKEDFILE="${BASHBOT_VAR:-.}/blocked"
COUNTFILE="${BASHBOT_VAR:-.}/count"

LOGDIR="${RUNDIR:-.}/logs"

# CREATE botconfig if not exist
# assume everything already set up correctly if TOKEN is set
if [ -z "${BOTTOKEN}" ]; then
  # BOTCONFIG does not exist, create
  [ ! -f "${BOTCONFIG}.jssh" ] && printf '["bot_config_key"]\t"config_key_value"\n' >>"${BOTCONFIG}.jssh"
  if [ -z "$(getConfigKey "bottoken")" ]; then
    # ask user for bot token
    if [ -z "${INTERACTIVE}" ] && [ "$1" != "init" ]; then
	printf "Running headless, set BOTTOKEN or run ${SCRIPT} init first!\n"
	exit 2 
    else
	printf "${RED}ENTER BOT TOKEN...${NN}${ORANGE}PLEASE WRITE YOUR TOKEN HERE OR PRESS CTRL+C TO ABORT${NN}"
	read -r token
	printf "\n"
    fi
    [ -n "${token}" ] && printf '["bottoken"]\t"%s"\n'  "${token}" >> "${BOTCONFIG}.jssh"
  fi
  # no botadmin, setup botadmin
  if [ -z "$(getConfigKey "botadmin")" ]; then
     # ask user for bot admin
     if [ -z "${INTERACTIVE}" ]; then
	printf "Running headless, set botadmin to AUTO MODE!\n"
     else
	printf "${RED}ENTER BOT ADMIN...${NN}${ORANGE}PLEASE WRITE YOUR TELEGRAM ID HERE OR PRESS ENTER\nTO MAKE FIRST USER TYPING '/start' BOT ADMIN${NN}?\b"
	read -r admin
     fi
     [ -z "${admin}" ] && admin='?'
     printf '["botadmin"]\t"%s"\n'  "${admin}" >> "${BOTCONFIG}.jssh"
  fi

  # setup botacl file
  if [ ! -f "${BOTACL}" ]; then
	printf "${GREY}Create initial ${BOTACL} file.${NN}"
	printf '\n' >"${BOTACL}"
  fi
  # check data dir file
  if [ ! -w "${DATADIR}" ]; then
	printf "${RED}ERROR: ${DATADIR} does not exist or is not writeable!.${NN}"
	[ "$1" != "init" ] && exit_source 2 # skip on init
  fi
  # setup count file 
  if [ ! -f "${COUNTFILE}.jssh" ]; then
	printf '["counted_user_chat_id"]\t"num_messages_seen"\n' >> "${COUNTFILE}.jssh"
  elif [ ! -w "${COUNTFILE}.jssh" ]; then
	printf "${RED}WARNING: Can't write to ${COUNTFILE}!.${NN}"
	ls -l "${COUNTFILE}.jssh"
  fi
  # setup blocked file 
  if [ ! -f "${BLOCKEDFILE}.jssh" ]; then
	printf '["blocked_user_or_chat_id"]\t"name and reason"\n' >>"${BLOCKEDFILE}.jssh"
  fi
fi

if [[ ! -d "${LOGDIR}" || ! -w "${LOGDIR}" ]]; then
	LOGDIR="${RUNDIR:-.}"
fi
DEBUGLOG="${LOGDIR}/DEBUG.log"
ERRORLOG="${LOGDIR}/ERROR.log"
UPDATELOG="${LOGDIR}/BASHBOT.log"
MESSAGELOG="${LOGDIR}/MESSAGE.log"

# read BOTTOKEN from bot database if not set
if [ -z "${BOTTOKEN}" ]; then
    BOTTOKEN="$(getConfigKey "bottoken")"
    if [ -z "${BOTTOKEN}" ]; then
		BOTERROR="Warning: can't get bot token, try to recover working config..."
		printf "${ORANGE}${BOTERROR}${NC} "
		if [ -r "${BOTCONFIG}.jssh.ok" ]; then
			log_error "${BOTERROR}"
			mv "${BOTCONFIG}.jssh" "${BOTCONFIG}.jssh.bad"
			cp "${BOTCONFIG}.jssh.ok" "${BOTCONFIG}.jssh"; printf "OK\n"
			BOTTOKEN="$(getConfigKey "bottoken")"
		else
			printf "\n${RED}Error: Can't recover from missing bot token! Remove ${BOTCONFIG}.jssh and run${NC} bashbot.sh init\n"
			exit_source 7
		fi
    fi
fi

# BOTTOKEN format checks
if ! check_token "${BOTTOKEN}"; then
	printf "\n${ORANGE}Warning: Your bot token is incorrect, it should have the following format:${NC}\n%b%b"\
		"<your_bot_id>${RED}:${NC}<35_alphanumeric_characters-hash> ${RED}e.g. =>${NC} 123456789${RED}:${NC}Aa-Zz_0Aa-Zz_1Aa-Zz_2Aa-Zz_3Aa-Zz_4\n\n"\
		"${GREY}Your bot token: '${NC}${BOTTOKEN//:/${RED}:${NC}}'\n"

	if [[ ! "${BOTTOKEN}" =~ ^[${o9o9o9}]{8,10}: ]]; then
		printf "${GREY}\tHint: Bot id not a number or wrong len: ${NC}$(($(wc -c <<<"${BOTTOKEN%:*}")-1)) ${GREY}but should be${NC} 8-10\n"
		[ -n "$(getConfigKey "botid")" ] && printf "\t${GREEN}Did you mean: \"${NC}$(getConfigKey "botid")${GREEN}\" ?${NN}"
	fi
	[[ ! "${BOTTOKEN}" =~ :[${azAZo9}_-]{35}$ ]] &&\
		printf "${GREY}\tHint: Hash contains invalid character or has not len${NC} 35 ${GREY}, hash len is ${NC}$(($(wc -c <<<"${BOTTOKEN#*:}")-1))\n"
	printf "\n"
fi


##################
# here we start with the real stuff
BASHBOT_RETRY=""	# retry by default

URL="${BASHBOT_URL:-https://api.telegram.org/bot}${BOTTOKEN}"
FILEURL="${URL%%/bot*}/file/bot${BOTTOKEN}"
ME_URL=${URL}'/getMe'

#################
# BASHBOT COMMON functions

declare -rx SCRIPT SCRIPTDIR MODULEDIR RUNDIR ADDONDIR BOTACL DATADIR COUNTFILE
declare -rx BOTTOKEN URL ME_URL

declare -ax CMD
declare -Ax UPD BOTSENT USER MESSAGE URLS CONTACT LOCATION CHAT FORWARD REPLYTO VENUE iQUERY iBUTTON
declare -Ax SERVICE NEWMEMBER LEFTMEMBER PINNED MIGRATE
export res CAPTION ME BOTADMIN



##############################
# bashbot modules starts here ...

# file: modules/aliases.sh
# do not edit, this file will be overwritten on update

# This file is public domain in the USA and all free countries.
# Elsewhere, consider it to be WTFPLv2. (wtfpl.net/txt/copying)
#
#
# will be automatically sourced from bashbot

# source once magic, function named like file
eval "$(basename "${BASH_SOURCE[0]}")(){ :; }"

# easy handling of users:
_is_botadmin() {
	user_is_botadmin "${USER[ID]}"
}
_is_admin() {
	user_is_admin "${CHAT[ID]}" "${USER[ID]}"
}
_is_creator() {
	user_is_creator "${CHAT[ID]}" "${USER[ID]}"
}
_is_allowed() {
	user_is_allowed "${USER[ID]}" "$1" "${CHAT[ID]}"
}
_leave() {
	leave_chat "${CHAT[ID]}"
}
_kick_user() {
	kick_chat_member "${CHAT[ID]}" "$1"
}
_unban_user() {
	unban_chat_member "${CHAT[ID]}" "$1"
}
# easy sending of messages of messages
_message() {
	send_normal_message "${CHAT[ID]}" "$1"
}
_normal_message() {
	send_normal_message "${CHAT[ID]}" "$1"
}
_html_message() {
	send_html_message "${CHAT[ID]}" "$1"
}
_markdown_message() {
	send_markdown_message "${CHAT[ID]}" "$1"
}
# easy handling of keyboards
_inline_button() {
	send_inline_button "${CHAT[ID]}" "" "$1" "$2" 
}
_inline_keyboard() {
	send_inline_keyboard "${CHAT[ID]}" "" "$1"
}
_keyboard_numpad() {
	send_keyboard "${CHAT[ID]}" "" '["1","2","3"],["4","5","6"],["7","8","9"],["-","0","."]' "yes"
}
_keyboard_yesno() {
	send_keyboard "${CHAT[ID]}" "" '["yes","no"]'
}
_del_keyboard() {
	remove_keyboard "${CHAT[ID]}" ""
}

# file: modules/inline.sh
# do not edit, this file will be overwritten on update

# This file is public domain in the USA and all free countries.
# Elsewhere, consider it to be WTFPLv2. (wtfpl.net/txt/copying)
#

# will be automatically sourced from bashbot

# source once magic, function named like file
eval "$(basename "${BASH_SOURCE[0]}")(){ :; }"


answer_inline_query() {
	answer_inline_multi "$1" "$(shift; inline_query_compose "${RANDOM}" "$@")"
}
answer_inline_multi() {
	sendJson "" '"inline_query_id": '"$1"', "results": ['"$2"']' "${URL}/answerInlineQuery"
}

# $1 unique ID for answer
# $2 type of answer
# remaining arguments are the "must have" arguments in the order as in telegram doc
# followed by the optional arguments: https://core.telegram.org/bots/api#inlinequeryresult
inline_query_compose(){
	local JSON="{}"
	local ID="$1"
	local fours last
								# title2Json title caption description markup inlinekeyboard
	case "$2" in
		# user provided media
		"article"|"message")	# article ID title message (markup description)
			JSON='{"type":"article","id":"'${ID}'","input_message_content": {"message_text":"'$4'"} '$(title2Json "$3" "" "$5" "$6" "$7")'}'
		;;
		"photo")	# photo ID photoURL (thumbURL title description caption)
			[ -z "$4" ] && tumb="$3"
			JSON='{"type":"photo","id":"'${ID}'","photo_url":"'$3'","thumb_url":"'$4${tumb}'"'$(title2Json "$5" "$7" "$6" "$7" "$8")'}'
		;;
		"gif")	# gif ID photoURL (thumbURL title caption)
			[ -z "$4" ] && tumb="$3"
			JSON='{"type":"gif","id":"'${ID}'","gif_url":"'$3'", "thumb_url":"'$4${tumb}'"'$(title2Json "$5" "$6" "$7" "$8" "$9")'}'
		;;
		"mpeg4_gif")	# mpeg4_gif ID mpegURL (thumbURL title caption)
			[ -n "$4" ] && tumb='","thumb_url":"'$4'"'
			JSON='{"type":"mpeg4_gif","id":"'${ID}'","mpeg4_url":"'$3'"'${tumb}$(title2Json "$5" "$6" "" "$7" "$8")'}'
		;;
		"video")	# video ID videoURL mime thumbURL title (caption)
			JSON='{"type":"video","id":"'${ID}'","video_url":"'$3'","mime_type":"'$4'","thumb_url":"'$5'"'$(title2Json "$6" "$7" "$8" "$9" "${10}")'}'
		;;
		"audio")	# audio ID audioURL title (caption)
			JSON='{"type":"audio","id":"'${ID}'","audio_url":"'$3'"'$(title2Json "$4" "$5" "" "" "$6")'}'
		;;
		"voice")	# voice ID voiceURL title (caption)
			JSON='{"type":"voice","id":"'${ID}'","voice_url":"'$3'"'$(title2Json "$4" "$5" "" "" "$6")'}'
		;;
		"document")	# document ID title documentURL mimetype (caption description)
			JSON='{"type":"document","id":"'${ID}'","document_url":"'$4'","mime_type":"'$5'"'$(title2Json "$3" "$6" "$7" "$8" "$9")'}'
		;;
		"location")	# location ID lat long title
			JSON='{"type":"location","id":"'${ID}'","latitude":"'$3'","longitude":"'$4'","title":"'$5'"}'
		;;
		"venue")	# venue ID lat long title (address forsquare)
			[ -z "$6" ] && addr="$5"
			[ -n "$7" ] && fours=',"foursquare_id":"'$7'"'
			JSON='{"type":"venue","id":"'${ID}'","latitude":"'$3'","longitude":"'$4'","title":"'$5'","address":"'$6${addr}'"'${fours}'}'
		;;
		"contact")	# contact ID phone first (last thumb)
			[ -n "$5" ] && last=',"last_name":"'$5'"'
			[ -n "$6" ] && tumb='","thumb_url":"'$6'"'
			JSON='{"type":"contact","id":"'${ID}'","phone_number":"'$3'","first_name":"'$4'"'${last}'"}'
		;;
								# title2Json title caption description markup inlinekeyboard
		# Cached media stored in Telegram server
		"cached_photo")	# photo ID file (title description caption)
			JSON='{"type":"photo","id":"'${ID}'","photo_file_id":"'$3'"'$(title2Json "$4" "$6" "$5"  "$7" "$8")'}'
		;;
		"cached_gif")	# gif ID file (title caption)
			JSON='{"type":"gif","id":"'${ID}'","gif_file_id":"'$3'"'$(title2Json "$4" "$5" "$6" "$7" "$8" )'}'
		;;
		"cached_mpeg4_gif")	# mpeg ID file (title caption)
			JSON='{"type":"mpeg4_gif","id":"'${ID}'","mpeg4_file_id":"'$3'"'$(title2Json "$4" "$5"  "" "$6" "$7")'}'
		;;
		"cached_sticker")	# sticker ID file 
			JSON='{"type":"sticker","id":"'${ID}'","sticker_file_id":"'$3'"}'
		;;
		"cached_document")	# document ID title file (description caption)
			JSON='{"type":"document","id":"'${ID}'","document_file_id":"'$4'"'$(title2Json "$3" "$6" "$5"  "$6" "$7")'}'
		;;
		"cached_video")	# video ID file title (description caption)
			JSON='{"type":"video","id":"'${ID}'","video_file_id":"'$3'"'$(title2Json "$4" "$6" "$5" "$7" "$8")'}'
		;;
		"cached_voice")	# voice ID file title (caption)
			JSON='{"type":"voice","id":"'${ID}'","voice_file_id":"'$3'"'$(title2Json "$4" "$5" "" "" "$6")'}'
		;;
		"cached_audio")	# audio ID file title (caption)
			JSON='{"type":"audio","id":"'${ID}'","audio_file_id":"'$3'"'$(title2Json "$4" "$5" "" "" "$6")'}'
		;;
	esac

	printf '%s\n' "${JSON}"
}


# file: modules/background.sh
# do not edit, this file will be overwritten on update

# This file is public domain in the USA and all free countries.
# Elsewhere, consider it to be WTFPLv2. (wtfpl.net/txt/copying)
#
# shellcheck disable=SC1117,SC2059

# will be automatically sourced from bashbot

# source once magic, function named like file
eval "$(basename "${BASH_SOURCE[0]}")(){ :; }"

######
# interactive and background functions

# old syntax as aliases
background() {
	start_back "${CHAT[ID]}" "$1" "$2"
}
startproc() {
	start_proc "${CHAT[ID]}" "$1" "$2"
}
checkback() {
	check_back "${CHAT[ID]}" "$1"
}
checkproc() {
	check_proc "${CHAT[ID]}" "$1"
}
killback() {
	kill_back  "${CHAT[ID]}" "$1"
}
killproc() {
	kill_proc "${CHAT[ID]}" "$1"
}

# inline and background functions
# $1 chatid
# $2 program
# $3 jobname
# $4 $5 parameters
start_back() {
	local cmdfile; cmdfile="${DATADIR:-.}/$(procname "$1")$3-back.cmd"
	printf '%s\n' "$1:$3:$2" >"${cmdfile}"
	restart_back "$@"
}
# $1 chatid
# $2 program
# $3 jobname
# $4 $5 parameters
restart_back() {
	local fifo; fifo="${DATADIR:-.}/$(procname "$1" "back-$3-")"
	log_update "Start background job CHAT=$1 JOB=${fifo##*/} CMD=${2##*/} $4 $5"
	check_back "$1" "$3" && kill_proc "$1" "back-$3-"
	nohup bash -c "{ $2 \"$4\" \"$5\" \"${fifo}\" | \"${SCRIPT}\" outproc \"$1\" \"${fifo}\"; }" &>>"${fifo}.log" &
	sleep 0.5	# give bg job some time to init
}


# $1 chatid
# $2 program
# $3 $4 parameters
start_proc() {
	[ -z "$2" ] && return
	[ -x "${2%% *}" ] || return 1
	local fifo; fifo="${DATADIR:-.}/$(procname "$1")"
	check_proc "$1" && kill_proc "$1"
	mkfifo "${fifo}"
	log_update "Start interactive script CHAT=$1 JOB=${fifo##*/} CMD=$2 $3 $4"
	nohup bash -c "{ $2 \"$4\" \"$5\" \"${fifo}\" | \"${SCRIPT}\" outproc \"$1\" \"${fifo}\"
		rm \"${fifo}\"; [ -s \"${fifo}.log\" ] || rm -f \"${fifo}.log\"; }" &>>"${fifo}.log" &
}


# $1 chatid
# $2 jobname
check_back() {
	check_proc "$1" "back-$2-"
}

# $1 chatid
# $2 prefix
check_proc() {
	[ -n "$(proclist "$(procname "$1" "$2")")" ]
	# shellcheck disable=SC2034
	res=$?; return $?
}

# $1 chatid
# $2 jobname
kill_back() {
	kill_proc "$1" "back-$2-"
	rm -f "${DATADIR:-.}/$(procname "$1")$2-back.cmd"
}


# $1 chatid
# $2 prefix
kill_proc() {
	local fifo prid
	fifo="$(procname "$1" "$2")"
	prid="$(proclist "${fifo}")"
	fifo="${DATADIR:-.}/${fifo}"
	# shellcheck disable=SC2086
	if [ -n "${prid}" ]; then
		log_update "Stop interactive / background CHAT=$1 JOB=${fifo##*/}"
		kill ${prid}
	fi
	[ -s "${fifo}.log" ] || rm -f "${fifo}.log"
	[ -p "${fifo}" ] && rm -f "${fifo}";
}

# $1 chatid
# $2 message
send_interactive() {
	local fifo; fifo="${DATADIR:-.}/$(procname "$1")"
	[ -p "${fifo}" ] && printf '%s\n' "$2" >"${fifo}" &	# not blocking!
}

# old style but may not work because of local checks
inproc() {
	send_interactive "${CHAT[ID]}" "${MESSAGE[0]}"
}

# start stop all jobs 
# $1 command #	kill suspend resume restart
job_control() {
	local BOT ADM content proc CHAT job fifo killall=""
	BOT="$(getConfigKey "botname")"
	ADM="${BOTADMIN}"
	debug_checks "Enter job_control" "$1"
	# cleanup on start
	[[ "$1" == "re"* ]] && bot_cleanup "startback"
	for FILE in "${DATADIR:-.}/"*-back.cmd; do
		[ "${FILE}" = "${DATADIR:-.}/*-back.cmd" ] && printf "${RED}No background processes.${NN}" && break
		content="$(< "${FILE}")"
		CHAT="${content%%:*}"
		job="${content#*:}"
		proc="${job#*:}"
		job="${job%:*}"
		fifo="$(procname "${CHAT}" "${job}")" 
		debug_checks "Execute job_control" "$1" "${FILE##*/}"
		case "$1" in
		"resume"*|"restart"*)
			printf "Restart Job: %s %s\n" "${proc}" " ${fifo##*/}"
			restart_back "${CHAT}" "${proc}" "${job}"
			# inform botadmin about stop
			[ -n "${ADM}" ] && send_normal_message "${ADM}" "Bot ${BOT} restart background jobs ..." &
			;;
		"suspend"*)
			printf "Suspend Job: %s %s\n" "${proc}" " ${fifo##*/}"
			kill_proc "${CHAT}" "${job}"
			# inform botadmin about stop
			[ -n "${ADM}" ] && send_normal_message "${ADM}" "Bot ${BOT} suspend background jobs ..." &
			killall="y"
			;;
		"kill"*)
			printf "Kill Job: %s %s\n" "${proc}" " ${fifo##*/}"
			kill_proc "${CHAT}" "${job}"
			rm -f "${FILE}"	# remove job
			# inform botadmin about stop
			[ -n "${ADM}" ] && send_normal_message "${ADM}" "Bot ${BOT} kill  background jobs ..." &
			killall="y"
			;;
		esac
		# send message only onnfirst job
		ADM=""
	done
	debug_checks "end job_control" "$1"
	# kill all requestet. kill ALL background jobs, even not listed in data-bot-bash
	[ "${killall}" = "y" ] && killallproc "back-"
}

# file: modules/chatMember.sh
# do not edit, this file will be overwritten on update

# This file is public domain in the USA and all free countries.
# Elsewhere, consider it to be WTFPLv2. (wtfpl.net/txt/copying)
#

# will be automatically sourced from bashbot

# source once magic, function named like file
eval "$(basename "${BASH_SOURCE[0]}")(){ :; }"


# manage chat functions -------
# $1 chat 
new_chat_invite() {
	sendJson "$1" "" "${URL}/exportChatInviteLink"
	[ "${BOTSENT[OK]}" = "true" ] && printf "%s\n" "${BOTSENT[RESULT]}"
}

# $1 chat, $2 user_id, $3 title 
set_chatadmin_title() {
	sendJson "$1" '"user_id":'"$2"',"custom_title": "'"$3"'"' "${URL}/setChatAdministratorCustomTitle"
}
# $1 chat, $2 title 
set_chat_title() {
	sendJson "$1" '"title": "'"$2"'"' "${URL}/setChatTitle"
}

# $1 chat, $2 title 
set_chat_description() {
	sendJson "$1" '"description": "'"$2"'"' "${URL}/setChatDescription"
}

# $1 chat  $2 file
set_chat_photo() {
	local file; file="$(checkUploadFile "$1" "$2" "set_chat_photo")"
	[ -z "${file}" ] && return 1
	sendUpload "$1" "photo" "${file}" "${URL}/setChatPhoto" 
}
# $1 chat 
delete_chat_photo() {
	sendJson "$1" "" "${URL}/deleteChatPhoto"
}

# $1 chat, $2 message_id 
pin_chat_message() {
	sendJson "$1" '"message_id": "'"$2"'"' "${URL}/pinChatMessage"
}

# $1 chat, $2 message_id 
unpin_chat_message() {
	sendJson "$1" '"message_id": "'"$2"'"' "${URL}/unpinChatMessage"
}

# $1 chat 
unpinall_chat_message() {
	sendJson "$1" "" "${URL}/unpinAllChatMessages"
}

# $1 chat 
delete_chat_stickers() {
	sendJson "$1" "" "${URL}/deleteChatStickerSet"
}

# manage chat member functions -------
# $1 chat 
chat_member_count() {
	sendJson "$1" "" "${URL}/getChatMembersCount"
	[ "${BOTSENT[OK]}" = "true" ] && printf "%s\n" "${BOTSENT[RESULT]}"
}

kick_chat_member() {
	sendJson "$1" 'user_id: '"$2"'' "${URL}/kickChatMember"
}

unban_chat_member() {
	sendJson "$1" 'user_id: '"$2"'' "${URL}/unbanChatMember"
}

leave_chat() {
	sendJson "$1" "" "${URL}/leaveChat"
}

# $1 chat, $2 userid, $3 ... "right[:true]" default false
# right:  is_anonymous change_info post_messages edit_messages delete_messages invite_users restrict_members pin_messages promote_member
promote_chat_member() {
	local arg bool json chat="$1" user="$2; shift 2"
	for arg in "$@"
	do
		# default false
		bool=false; [ "${arg##*:}" = "true" ] && bool="true"
		# expand args
		case "${arg}" in
			*"anon"*)	arg="is_anonymous";;
			*"change"*)	arg="can_change_info";;
			*"post"*)	arg="can_post_messages";;
			*"edit"*)	arg="can_edit_messages";;
			*"delete"*)	arg="can_delete_messages";;
			*"pin"*)	arg="can_pin_messages";;
			*"invite"*)	arg="can_invite_users";;
			*"restrict"*)	arg="can_restrict_members";;
			*"promote"*)	arg="can_promote_members";;
			*) 	[ -n "${BASHBOTDEBUG}" ] && log_debug "promote_chat_member: unknown promotion CHAT=${chat} USER=${user} PROM=${arg}"
				continue;; 
		esac
		# compose json
		[ -n "${json}" ] && json+=","
		json+='"'"${arg}"'": "'"${bool}"'"'
	done
	sendJson "${chat}" '"user_id":'"${user}"','"${json}"'' "${URL}/promoteChatMember"
}

# bashbot specific functions ---------

# usage: status="$(get_chat_member_status "chat" "user")"
# $1 chat # $2 user
get_chat_member_status() {
	sendJson "$1" '"user_id":'"$2"'' "${URL}/getChatMember"
	# shellcheck disable=SC2154
	printf "%s\n" "${UPD["result,status"]}"
}

user_is_creator() {
	# empty is false ...
	[[ "${1:--}" == "${2:-+}" || "$(get_chat_member_status "$1" "$2")" == "creator" ]] && return 0
	return 1 
}

# $1 chat
bot_is_admin() {
	user_is_admin "$1" "$(getConfigKey "botid")"
}

# $1 chat # $2 user
user_is_admin() {
	[[ -z "$1" || -z "$2" ]] && return 1
	[ "${1:--}" == "${2:-+}" ] && return 0
	user_is_botadmin "$2" && return 0
	local me; me="$(get_chat_member_status "$1" "$2")"
	[[ "${me}" =~ ^creator$|^administrator$ ]] && return 0
	return 1 
}

# $1 user
user_is_botadmin() {
	[ -z "$1" ] && return 1
	[ -z "${BOTADMIN}" ] && return 1
	[[ "${BOTADMIN}" == "$1" || "${BOTADMIN}" == "$2" ]] && return 0
	if [ "${BOTADMIN}" = "?" ]; then setConfigKey "botadmin" "${1:-?}"; BOTADMIN="${1:-?}"; return 0; fi
	return 1
}

# $1 user # $2 key # $3 chat
user_is_allowed() {
	[ -z "$1" ] && return 1
	user_is_admin "$1" && return 0
	# user can do everything
	grep -F -xq "$1:*:*" "${BOTACL}" && return 0
	[ -z "$2" ] && return 1
	# user is allowed todo one action in every chat
	grep -F -xq "$1:$2:*" "${BOTACL}" && return 0
	# all users are allowed to do one action in every chat
	grep -F -xq "ALL:$2:*" "${BOTACL}" && return 0
	[ -z "$3" ] && return 1
	# user is allowed to do one action in one chat
	grep -F -xq "$1:$2:$3" "${BOTACL}" && return 0
	# all users are allowed to do one action in one chat
	grep -F -xq "ALL:$2:$3" "${BOTACL}" && return 0
	return 1
}

# file: modules/jsshDB.sh
# do not edit, this file will be overwritten on update

# This file is public domain in the USA and all free countries.
# Elsewhere, consider it to be WTFPLv2. (wtfpl.net/txt/copying)
#
#
# source from commands.sh to use jsonDB functions
#
# jsonDB provides simple functions to read and store bash Arrays
# from to file in JSON.sh output format, its a simple key/value storage.

# will be automatically sourced from bashbot
# but can be used independent from bashbot also
# e.g. to create scrupts to manage jssh files

# source once magic, function named like file
eval "$(basename "${BASH_SOURCE[0]}")(){ :; }"

# new feature: serialize / atomic operations:
# updates will be done atomic with flock
# flock should flock should be available on all system as its part of busybox
# tinybox

# lockfile filename.flock is persistent and will be testet with flock for active lock (file open)
export JSSHDB_LOCKNAME=".flock"
# an array value containing this string will not saveed to DB (unset)
export JSSHDB_UNSET="99999999999999999999_JSSHDB_UNSET_99999999999999999999"

# in UTF-8 äöü etc. are part of [:alnum:] and ranges (e.g. a-z), but we want ASCII a-z ranges!
# for more information see  doc/4_expert.md#Character_classes
azazaz='abcdefghijklmnopqrstuvwxyz'	# a-z   :lower:
AZAZAZ='ABCDEFGHIJKLMNOPQRSTUVWXYZ'	# A-Z   :upper:
o9o9o9='0123456789'			# 0-9   :digit:
azAZaz="${azazaz}${AZAZAZ}"	# a-zA-Z	:alpha:
azAZo9="${azAZaz}${o9o9o9}"	# a-zA-z0-9	:alnum:

# characters allowed for key in key/value pairs
JSSH_KEYOK="[-${azAZo9},._]"

# read string from stdin and and strip invalid characters
# $1 - invalid charcaters are replaced with first character
#      or deleted if $1 is empty
jssh_stripKey() {	# tr: we must escape first - in [-a-z...]
	if [[ "$1" =~ ^${JSSH_KEYOK} ]]; then	# tr needs [\-...
 		tr -c "${JSSH_KEYOK/\[-/[\\-}\r\n" "${1:0:1}"
	else
 		tr -dc "${JSSH_KEYOK/\[-/[\\-}\r\n"
	fi
}

# use flock if command exist
if [ "$(LC_ALL=C type -t "flock")" = "file" ]; then

  ###############
  # we have flock
  # use flock for atomic operations

  # read content of a file in JSON.sh format into given ARRAY
  # $1 ARRAY name, must be declared with "declare -A ARRAY" upfront
  # $2 filename, must be relative to BASHBOT_ETC, and not contain '..'
  jssh_readDB() {
	local DB; DB="$(jssh_checkDB "$2")"
	[ -z "${DB}" ] && return 1
	[ ! -f "${DB}" ] && return 2
	# shared lock, many processes can read, max wait 1s
	{ flock -s -w 1 200; Json2Array "$1" <"${DB}"; } 200>"${DB}${JSSHDB_LOCKNAME}"
  }

  # write ARRAY content to a file in JSON.sh format
  # Warning: old content is overwritten
  # $1 ARRAY name, must be declared with "declare -A ARRAY" upfront
  # $2 filename (must exist!), must be relative to BASHBOT_ETC, and not contain '..'
  jssh_writeDB() {
	local DB; DB="$(jssh_checkDB "$2")"
	[ -z "${DB}" ] && return 1
	[ ! -f "${DB}" ] && return 2
	# exclusive lock, no other process can read or write, maximum wait to get lock is 10s
	{ flock -e -w 10 200; Array2Json "$1" >"${DB}"; } 200>"${DB}${JSSHDB_LOCKNAME}"
  }

  # update/write ARRAY content in file without deleting keys not in ARRAY
  # $1 ARRAY name, must be declared with "declare -A ARRAY" upfront
  # $2 filename (must exist!), must be relative to BASHBOT_ETC, and not contain '..'
  # complex slow, warpper async
  jssh_updateDB() {
	# for atomic update we can't use read/writeDB
	[ -z "$2" ] && return 1
	local DB="$2.jssh"	# check in async
	[ ! -f "${DB}" ] && return 2
	{ flock -e -w 10 200; jssh_updateDB_async "$@"; } 200>"${DB}${JSSHDB_LOCKNAME}"
  }

  # insert, update, apped key/value to jsshDB
  # $1 key name, can only contain -a-zA-Z0-9,._
  # $2 key value
  # $3 filename (must exist!), must be relative to BASHBOT_ETC, and not contain '..'
  alias jssh_insertDB=jssh_insertKeyDB	# backward compatibility
  # renamed to be more consistent
  jssh_insertKeyDB() {
	[[ "$1" =~ ^${JSSH_KEYOK}+$ ]] || return 3
	local DB; DB="$(jssh_checkDB "$3")"
	[ -z "${DB}" ] && return 1
	[ ! -f "${DB}" ] && return 2
	# start atomic update here, exclusive max wait 2, it's append, not overwrite
	{ flock -e -w 2 200
	 # it's append, but last one counts, its a simple DB ...
	  printf '["%s"]\t"%s"\n' "${1//,/\",\"}" "${2//\"/\\\"}" >>"${DB}"
	} 200>"${DB}${JSSHDB_LOCKNAME}"
	
  }

  # delete key/value from jsshDB
  # $1 key name, can only contain -a-zA-Z0-9,._
  # $2 filename (must exist!), must be relative to BASHBOT_ETC, and not contain '..'
  # medium complex slow, wrapper async
  jssh_deleteKeyDB() {
	[ -z "$2" ] && return 1
	[[ "$1" =~ ^${JSSH_KEYOK}+$ ]] || return 3
	local DB="$2.jssh"
	# start atomic delete here, exclusive max wait 10s 
	{ flock -e -w 10 200; jssh_deleteKeyDB_async "$@"; } 200>"${DB}${JSSHDB_LOCKNAME}"
  }

  # get key/value from jsshDB
  # $1 key name, can only contain -a-zA-Z0-9,._
  # $2 filename (must exist!), must be relative to BASHBOT_ETC, and not contain '..'
  alias jssh_getDB=jssh_getKeyDB
  jssh_getKeyDB() {
	[[ "$1" =~ ^${JSSH_KEYOK}+$ ]] || return 3
	local DB; DB="$(jssh_checkDB "$2")"
	[ -z "${DB}" ] && return 1
	# start atomic delete here, exclusive max wait 1s 
	{ flock -s -w 1 200
	[ -r "${DB}" ] && sed -n 's/\["'"$1"'"\]\t*"\(.*\)"/\1/p' "${DB}" | tail -n 1
	} 200>"${DB}${JSSHDB_LOCKNAME}"
  }


  # add a value to key, used for conters
  # $1 key name, can only contain -a-zA-Z0-9,._
  # $2 filename (must exist!), must be relative to BASHBOT_ETC, and not contain '..'
  # $3 optional count, value added to counter, add 1 if empty 
  # side effect: if $3 is not given, we add to end of file to be as fast as possible
  # complex, wrapper to async
  jssh_countKeyDB() {
	[ -z "$2" ] && return 1
	[[ "$1" =~ ^${JSSH_KEYOK}+$ ]] || return 3
	local DB="$2.jssh"
	# start atomic delete here, exclusive max wait 5 
	{ flock -e -w 5 200; jssh_countKeyDB_async "$@"; } 200>"${DB}${JSSHDB_LOCKNAME}"
  }

  # update key/value in place to jsshDB
  # $1 key name, can only contain -a-zA-Z0-9,._
  # $2 key value
  # $3 filename (must exist!), must be relative to BASHBOT_ETC, and not contain '..'
  #no own locking, so async is the same as updatekeyDB
  jssh_updateKeyDB() {
	[[ "$1" =~ ^${JSSH_KEYOK}+$ ]] || return 3
	[ -z "$3" ] && return 1
	declare -A updARR
	# shellcheck disable=SC2034
	updARR["$1"]="$2"
	jssh_updateDB "updARR" "$3" || return 3
  }

  # $1 filename (must exist!), must be relative to BASHBOT_ETC, and not contain '..'
  jssh_clearDB() {
	local DB; DB="$(jssh_checkDB "$1")"
	[ -z "${DB}" ] && return 1
	{ flock -e -w 10 200; printf '' >"${DB}"; } 200>"${DB}${JSSHDB_LOCKNAME}"
  } 

  # updates Array if DB file has changed since last call
  # $1 name of array to update
  # $2 database
  # $3 id used to identify caller
  # medium complex, wrapper async
  jssh_updateArray() { 
	[ -z "$2" ] && return 1
	local DB="$2.jssh"	# name check in async
	[ ! -f "${DB}" ] && return 2
	declare -n ARRAY="$1"
	[[ -z "${ARRAY[*]}" ||  "${DB}" -nt "${DB}.last$3" ]] && touch "${DB}.last$3" && jssh_readDB "$1" "$2"
  }

else
  #########
  # we have no flock, use non atomic functions
  alias jssh_readDB=ssh_readDB_async
  alias jssh_writeDB=jssh_writeDB_async
  alias jssh_updateDB=jssh_updateDB_async
  alias jssh_insertDB=jssh_insertDB_async
  alias ssh_deleteKeyDB=jssh_deleteKeyDB_async
  alias jssh_getDB=jssh_getKeyDB_async
  alias jssh_getKeyDB=jssh_getKeyDB_async
  alias jssh_countKeyDB=jssh_countKeyDB_async
  alias jssh_updateKeyDB=jssh_updateKeyDB_async
  alias jssh_clearDB=jssh_clearDB_async
  alias jssh_updateArray=updateArray_async
fi

##############
# no need for atomic

# print ARRAY content to stdout instead of file
# $1 ARRAY name, must be declared with "declare -A ARRAY" upfront
jssh_printDB_async() { jssh_printDB "$@"; }
jssh_printDB() {
	Array2Json "$1"
}

# $1 filename (must exist!), must be relative to BASHBOT_ETC, and not contain '..'
jssh_newDB_async() { jssh_newDB "$@"; }
jssh_newDB() {
	local DB; DB="$(jssh_checkDB "$1")"
	[ -z "${DB}" ] && return 1
	[ -f "${DB}" ] && return 2	# already exist
	touch "${DB}"
} 

# $1 filename, check filename, it must be relative to BASHBOT_VAR, and not contain '..'
# returns real path to DB file if everything is ok
jssh_checkDB_async() { jssh_checkDB "$@"; }
jssh_checkDB(){
	local DB
	[ -z "$1" ] && return 1
	[[ "$1" = *'../.'* ]] && return 2
	if [[ "$1" == "${BASHBOT_VAR:-.}"* ]] || [[ "$1" == "${BASHBOT_DATA:-.}"* ]]; then
		DB="$1.jssh"
	else
		DB="${BASHBOT_VAR:-.}/$1.jssh"
	fi
	[ "${DB}" != ".jssh" ] && printf '%s' "${DB}"
}


######################
# implementations as non atomic functions
# can be used explictitly or as fallback if flock is not available
jssh_readDB_async() {
	local DB; DB="$(jssh_checkDB "$2")"
	[ -z "${DB}" ] && return 1
	[ ! -f "${DB}" ] && return 2
	Json2Array "$1" <"${DB}"
}

jssh_writeDB_async() {
	local DB; DB="$(jssh_checkDB "$2")"
	[ -z "${DB}" ] && return 1
	[ ! -f "${DB}" ] && return 2
	Array2Json "$1" >"${DB}"
}

jssh_updateDB_async() {
	[ -z "$2" ] && return 1
	declare -n ARRAY="$1"
	[ -z "${ARRAY[*]}" ] && return 1
	declare -A oldARR
	jssh_readDB_async "oldARR" "$2" || return "$?"
	if [ -z "${oldARR[*]}" ]; then
		# no old content
		jssh_writeDB_async "$1" "$2"
	else
		# merge arrays
		local key
		for key in "${!ARRAY[@]}"
		do
		    oldARR["${key}"]="${ARRAY["${key}"]}"
		done
		Array2Json "oldARR" >"${DB}"
	fi
}

jssh_insertDB_async() { jssh_insertKeyDB "$@"; }
jssh_insertKeyDB_async() {
	[[ "$1" =~ ^${JSSH_KEYOK}+$ ]] || return 3
	local DB; DB="$(jssh_checkDB "$3")"
	[ -z "${DB}" ] && return 1
	[ ! -f "${DB}" ] && return 2
	# its append, but last one counts, its a simple DB ...
	printf '["%s"]\t"%s"\n' "${1//,/\",\"}" "${2//\"/\\\"}" >>"${DB}"
	
}

jssh_deleteKeyDB_async() {
	[[ "$1" =~ ^${JSSH_KEYOK}+$ ]] || return 3
	local DB; DB="$(jssh_checkDB "$2")"
	[ -z "${DB}" ] && return 1
	declare -A oldARR
	Json2Array "oldARR" <"${DB}"
	unset oldARR["$1"]
	Array2Json  "oldARR" >"${DB}"
}

jssh_getKeyDB_async() {
	[[ "$1" =~ ^${JSSH_KEYOK}+$ ]] || return 3
	local DB; DB="$(jssh_checkDB "$2")"
	[ -z "${DB}" ] && return 1
	[ -r "${DB}" ] && sed -n 's/\["'"$1"'"\]\t*"\(.*\)"/\1/p' "${DB}" | tail -n 1
}

jssh_countKeyDB_async() {
	[[ "$1" =~ ^${JSSH_KEYOK}+$ ]] || return 3
	local VAL DB; DB="$(jssh_checkDB "$2")"
	[ -z "${DB}" ] && return 1
	# start atomic delete here, exclusive max wait 5 
	if [ -n "$3" ]; then
		declare -A oldARR
		Json2Array "oldARR" <"${DB}"
		(( oldARR["$1"]+="$3" ));
		Array2Json  "oldARR" >"${DB}"
	elif [ -r "${DB}" ]; then
		# it's append, but last one counts, its a simple DB ...
		VAL="$(sed -n 's/\["'"$1"'"\]\t*"\(.*\)"/\1/p' "${DB}" | tail -n 1)"
		printf '["%s"]\t"%s"\n' "${1//,/\",\"}" "$((++VAL))" >>"${DB}"
	fi
  }

# update key/value in place to jsshDB
# $1 key name, can only contain -a-zA-Z0-9,._
# $2 key value
# $3 filename (must exist!), must be relative to BASHBOT_ETC, and not contain '..'
#no own locking, so async is the same as updatekeyDB
jssh_updateKeyDB_async() {
	[[ "$1" =~ ^${JSSH_KEYOK}+$ ]] || return 3
	[ -z "$3" ] && return 1
	declare -A updARR
	# shellcheck disable=SC2034
	updARR["$1"]="$2"
	jssh_updateDB_async "updARR" "$3" || return 3
}

jssh_clearDB_async() {
	local DB; DB="$(jssh_checkDB "$1")"
	[ -z "${DB}" ] && return 1
	printf '' >"${DB}"
} 

function jssh_updateArray_async() {
	local DB; DB="$(jssh_checkDB "$2")"
	[ -z "${DB}" ] && return 1
	[ ! -f "${DB}" ] && return 2
	declare -n ARRAY="$1"
	[[ -z "${ARRAY[*]}" ||  "${DB}" -nt "${DB}.last$3" ]] && touch "${DB}.last$3" && jssh_readDB_async "$1" "$2"
}

##############
# these 2 functions does all key/value store "magic"
# and convert from/to bash array

# read JSON.sh style data and asssign to an ARRAY
# $1 ARRAY name, must be declared with "declare -A ARRAY" before calling
Json2Array() {
	# shellcheck disable=SC1091,SC1090
	# step 1: output only basic pattern
	[ -z "$1" ] || source <( printf "$1"'=( %s )'\
		 "$(sed -E -n -e 's/[`´]//g' -e 's/\t(true|false)/\t"\1"/' -e 's/([^\]|^)\$/\1\\$/g' -e '/\["[-0-9a-zA-Z_,."]+"\]\+*\t/ s/\t/=/p')" )
}
# get Config Key from jssh file without jsshDB
# output ARRAY as JSON.sh style data
# $1 ARRAY name, must be declared with "declare -A ARRAY" before calling
Array2Json() {
	[ -z "$1" ] && return 1
	local key
	declare -n ARRAY="$1"
	for key in "${!ARRAY[@]}"
       	do
		[[ ! "${key}" =~ ^${JSSH_KEYOK}+$ || "${ARRAY[${key}]}" == "${JSSHDB_UNSET}" ]] && continue
		# in case value contains newline convert to \n
		: "${ARRAY[${key}]//$'\n'/\\n}"
		printf '["%s"]\t"%s"\n' "${key//,/\",\"}" "${_//\"/\\\"}"
       	done
}

##################################################################
#
# File: processUpdates.sh 
# Note: DO NOT EDIT! this file will be overwritten on update
#
##################################################################

##############
# manage webhooks

# $1 URL to sed updates to: https://host.dom[:port][/path], port and path are optional
#      port must be 443, 80, 88 8443, TOKEN will be added to URL for security
#      e.g. https://myhost.com -> https://myhost.com/12345678:azndfhbgdfbbbdsfg
# $2 max connections 1-100 default 1 (because of bash ;-)
set_webhook() {
	local  url='"url": "'"$1/${BOTTOKEN}/"'"'
	local  max=',"max_connections": 1'
	[[ "$2" =~ ^[0-9]+$ ]] && max=',"max_connections": '"$2"''
	# shellcheck disable=SC2153
	sendJson "" "${url}${max}" "${URL}/setWebhook"
	unset "BOTSENT[ID]" "BOTSENT[CHAT]"

}

get_webhook_info() {
	sendJson "" "" "${URL}/getWebhookInfo"
	if [ "${BOTSENT[OK]}" = "true" ]; then
		BOTSENT[URL]="${UPD[result,url]}"
		BOTSENT[COUNT]="${UPD[result,pending_update_count]}"
		BOTSENT[CERT]="${UPD[result,has_custom_certificate]}"
		BOTSENT[LASTERR]="${UPD[result,last_error_message]}"
		unset "BOTSENT[ID]" "BOTSENT[CHAT]"
	fi
}

# $1 drop pending updates true/false, default false
delete_webhook() {
	local drop; [ "$1" = "true" ] && drop='"drop_pending_updates": true'
	sendJson "" "${drop}" "${URL}/deleteWebhook"
	unset "BOTSENT[ID]" "BOTSENT[CHAT]"
}

################
# processing of array of updates starts here
process_multi_updates() {
	local max num debug="$1"
	# get num array elements
	max="$(grep -F ',"update_id"]'  <<< "${UPDATE}" | tail -1 | cut -d , -f 2 )"
	# escape bash $ expansion bug
	UPDATE="${UPDATE//$/\\$}"
	# convert updates to bash array
	Json2Array 'UPD' <<<"${UPDATE}"
	# iterate over array
	for ((num=0; num<=max; num++)); do
		process_update "${num}" "${debug}"
	done
}

################
# processing of a single array item of update
# $1 array index
process_update() {
	local chatuser="Chat" num="$1" debug="$2" 
	pre_process_message "${num}"
	# log message on debug
	[[ -n "${debug}" ]] && log_message "New Message ==========\n$(grep -F '["result",'"${num}" <<<"${UPDATE}")"

	# check for users / groups to ignore, inform them ...
	jssh_updateArray_async "BASHBOTBLOCKED" "${BLOCKEDFILE}"
	if [ -n "${USER[ID]}" ] && [[ -n "${BASHBOTBLOCKED[${USER[ID]}]}" || -n "${BASHBOTBLOCKED[${CHAT[ID]}]}" ]];then
		[  -n "${BASHBOTBLOCKED[${USER[ID]}]}" ] && chatuser="User"
		[ "${NOTIFY_BLOCKED_USERS}" == "yes" ] &&\
			send_normal_message "${CHAT[ID]}" "${chatuser} blocked because: ${BASHBOTBLOCKED[${USER[ID]}]} ${BASHBOTBLOCKED[${CHAT[ID]}]}" &
		return
	fi

	# process per message type
	if [ -n "${iQUERY[ID]}" ]; then
		process_inline_query "${num}" "${debug}"
	        printf "%(%c)T: Inline Query update received FROM=%s iQUERY=%s\n" -1\
			"${iQUERY[USERNAME]:0:20} (${iQUERY[USER_ID]})" "${iQUERY[0]}" >>"${UPDATELOG}"
	elif [ -n "${iBUTTON[ID]}" ]; then
		process_inline_button "${num}" "${debug}"
	        printf "%(%c)T: Inline Button update received FROM=%s CHAT=%s CALLBACK=%s DATA:%s \n" -1\
			"${iBUTTON[USERNAME]:0:20} (${iBUTTON[USER_ID]})" "${iBUTTON[CHAT_ID]}" "${iBUTTON[ID]}" "${iBUTTON[DATA]}" >>"${UPDATELOG}"
	else
		if grep -qs -e '\["result",'"${num}"',"edited_message"' <<<"${UPDATE}"; then
			# edited message
			UPDATE="${UPDATE//,${num},\"edited_message\",/,${num},\"message\",}"
			Json2Array 'UPD' <<<"${UPDATE}"
			MESSAGE[0]="/_edited_message "
		fi
		process_message "${num}" "${debug}"
	        printf "%(%c)T: update received FROM=%s CHAT=%s CMD=%s\n" -1 "${USER[USERNAME]:0:20} (${USER[ID]})"\
			"${CHAT[USERNAME]:0:20}${CHAT[TITLE]:0:30} (${CHAT[ID]})"\
			"${MESSAGE:0:30}${CAPTION:0:30}${URLS[*]}" >>"${UPDATELOG}"
		if [[ -z "${USER[ID]}" || -z "${CHAT[ID]}" ]]; then
			printf "%(%c)T: IGNORE unknown update type: %s\n" -1 "$(grep '\["result",'"${num}"'.*,"id"\]' <<<"${UPDATE}")" >>"${UPDATELOG}"
			return 1
		fi
	fi
	#####
	# process inline and message events
	# first classic command dispatcher
	# shellcheck disable=SC2153,SC1090
	{ source "${COMMANDS}" "${debug}"; } &

	# then all registered addons
	if [ -z "${iQUERY[ID]}" ]; then
		event_message "${debug}"
	else
		event_inline "${debug}"
	fi

	# last count users
	jssh_countKeyDB_async "${CHAT[ID]}" "${COUNTFILE}"
}

pre_process_message(){
	local num="$1"
	# unset everything to not have old values
	CMD=( ); iQUERY=( ); iBUTTON=(); MESSAGE=(); CHAT=(); USER=(); CONTACT=(); LOCATION=(); unset CAPTION
	REPLYTO=( ); FORWARD=( ); URLS=(); VENUE=( ); SERVICE=( ); NEWMEMBER=( ); LEFTMEMBER=( ); PINNED=( ); MIGRATE=( )
	iQUERY[ID]="${UPD["result,${num},inline_query,id"]}"
	iBUTTON[ID]="${UPD["result,${num},callback_query,id"]}"
	CHAT[ID]="${UPD["result,${num},message,chat,id"]}"
	USER[ID]="${UPD["result,${num},message,from,id"]}"
	[ -z "${CHAT[ID]}" ] && CHAT[ID]="${UPD["result,${num},edited_message,chat,id"]}"
	[ -z "${USER[ID]}" ] && USER[ID]="${UPD["result,${num},edited_message,from,id"]}"
	# always true
	return 0
}

process_inline_query() {
	local num="$1"
	iQUERY[0]="$(JsonDecode "${UPD["result,${num},inline_query,query"]}")"
	iQUERY[USER_ID]="${UPD["result,${num},inline_query,from,id"]}"
	iQUERY[FIRST_NAME]="$(JsonDecode "${UPD["result,${num},inline_query,from,first_name"]}")"
	iQUERY[LAST_NAME]="$(JsonDecode "${UPD["result,${num},inline_query,from,last_name"]}")"
	iQUERY[USERNAME]="$(JsonDecode "${UPD["result,${num},inline_query,from,username"]}")"
	# always true
	return 0
}

process_inline_button() {
	local num="$1"
	iBUTTON[DATA]="${UPD["result,${num},callback_query,data"]}"
	iBUTTON[CHAT_ID]="${UPD["result,${num},callback_query,message,chat,id"]}"
	iBUTTON[MESSAGE_ID]="${UPD["result,${num},callback_query,message,message_id"]}"
	iBUTTON[MESSAGE]="$(JsonDecode "${UPD["result,${num},callback_query,message,text"]}")"
# XXX should we give back pressed button, all buttons or nothing?
	iBUTTON[USER_ID]="${UPD["result,${num},callback_query,from,id"]}"
	iBUTTON[FIRST_NAME]="$(JsonDecode "${UPD["result,${num},callback_query,from,first_name"]}")"
	iBUTTON[LAST_NAME]="$(JsonDecode "${UPD["result,${num},callback_query,from,last_name"]}")"
	iBUTTON[USERNAME]="$(JsonDecode "${UPD["result,${num},callback_query,from,username"]}")"
	# always true
	return 0
}

process_message() {
	local num="$1"
	# Message
	MESSAGE[0]+="$(JsonDecode "${UPD["result,${num},message,text"]}" | sed 's|\\/|/|g')"
	MESSAGE[ID]="${UPD["result,${num},message,message_id"]}"
	MESSAGE[CAPTION]="$(JsonDecode "${UPD["result,${num},message,caption"]}")"
	CAPTION="${MESSAGE[CAPTION]}"	# backward compatibility 
	# dice received
	MESSAGE[DICE]="${UPD["result,${num},message,dice,emoji"]}"
	if [ -n "${MESSAGE[DICE]}" ]; then
		MESSAGE[RESULT]="${UPD["result,${num},message,dice,value"]}"
		MESSAGE[0]="/_dice_received ${MESSAGE[DICE]} ${MESSAGE[RESULT]}"
	fi
	# Chat ID is now parsed when update is received
	CHAT[LAST_NAME]="$(JsonDecode "${UPD["result,${num},message,chat,last_name"]}")"
	CHAT[FIRST_NAME]="$(JsonDecode "${UPD["result,${num},message,chat,first_name"]}")"
	CHAT[USERNAME]="$(JsonDecode "${UPD["result,${num},message,chat,username"]}")"
	# set real name as username if empty
	[ -z "${CHAT[USERNAME]}" ] && CHAT[USERNAME]="${CHAT[FIRST_NAME]} ${CHAT[LAST_NAME]}"
	CHAT[TITLE]="$(JsonDecode "${UPD["result,${num},message,chat,title"]}")"
	CHAT[TYPE]="$(JsonDecode "${UPD["result,${num},message,chat,type"]}")"
	CHAT[ALL_ADMIN]="${UPD["result,${num},message,chat,all_members_are_administrators"]}"

	# user ID is now parsed when update is received
	USER[FIRST_NAME]="$(JsonDecode "${UPD["result,${num},message,from,first_name"]}")"
	USER[LAST_NAME]="$(JsonDecode "${UPD["result,${num},message,from,last_name"]}")"
	USER[USERNAME]="$(JsonDecode "${UPD["result,${num},message,from,username"]}")"
	# set real name as username if empty
	[ -z "${USER[USERNAME]}" ] && USER[USERNAME]="${USER[FIRST_NAME]} ${USER[LAST_NAME]}"

	# in reply to message from
	if [ -n "${UPD["result,${num},message,reply_to_message,from,id"]}" ]; then
	   REPLYTO[UID]="${UPD["result,${num},message,reply_to_message,from,id"]}"
	   REPLYTO[0]="$(JsonDecode "${UPD["result,${num},message,reply_to_message,text"]}")"
	   REPLYTO[ID]="${UPD["result,${num},message,reply_to_message,message_id"]}"
	   REPLYTO[FIRST_NAME]="$(JsonDecode "${UPD["result,${num},message,reply_to_message,from,first_name"]}")"
	   REPLYTO[LAST_NAME]="$(JsonDecode "${UPD["result,${num},message,reply_to_message,from,last_name"]}")"
	   REPLYTO[USERNAME]="$(JsonDecode "${UPD["result,${num},message,reply_to_message,from,username"]}")"
	fi

	# forwarded message from
	if [ -n "${UPD["result,${num},message,forward_from,id"]}" ]; then
	   FORWARD[UID]="${UPD["result,${num},message,forward_from,id"]}"
	   FORWARD[ID]="${MESSAGE[ID]}"	# same as message ID
	   FORWARD[FIRST_NAME]="$(JsonDecode "${UPD["result,${num},message,forward_from,first_name"]}")"
	   FORWARD[LAST_NAME]="$(JsonDecode "${UPD["result,${num},message,forward_from,last_name"]}")"
	   FORWARD[USERNAME]="$(JsonDecode "${UPD["result,${num},message,forward_from,username"]}")"
	fi

	# get file URL from telegram, check for any of them!
	if grep -qs -e '\["result",'"${num}"',"message","[avpsd].*,"file_id"\]' <<<"${UPDATE}"; then
	    URLS[AUDIO]="$(get_file "${UPD["result,${num},message,audio,file_id"]}")"
	    URLS[DOCUMENT]="$(get_file "${UPD["result,${num},message,document,file_id"]}")"
	    URLS[PHOTO]="$(get_file "${UPD["result,${num},message,photo,0,file_id"]}")"
	    URLS[STICKER]="$(get_file "${UPD["result,${num},message,sticker,file_id"]}")"
	    URLS[VIDEO]="$(get_file "${UPD["result,${num},message,video,file_id"]}")"
	    URLS[VOICE]="$(get_file "${UPD["result,${num},message,voice,file_id"]}")"
	fi
	# Contact, must have phone_number
	if [ -n "${UPD["result,${num},message,contact,phone_number"]}" ]; then
		CONTACT[USER_ID]="$(JsonDecode  "${UPD["result,${num},message,contact,user_id"]}")"
		CONTACT[FIRST_NAME]="$(JsonDecode "${UPD["result,${num},message,contact,first_name"]}")"
		CONTACT[LAST_NAME]="$(JsonDecode "${UPD["result,${num},message,contact,last_name"]}")"
		CONTACT[NUMBER]="${UPD["result,${num},message,contact,phone_number"]}"
		CONTACT[VCARD]="${UPD["result,${num},message,contact,vcard"]}"
	fi

	# venue, must have a position
	if [ -n "${UPD["result,${num},message,venue,location,longitude"]}" ]; then
		VENUE[TITLE]="$(JsonDecode "${UPD["result,${num},message,venue,title"]}")"
		VENUE[ADDRESS]="$(JsonDecode "${UPD["result,${num},message,venue,address"]}")"
		VENUE[LONGITUDE]="${UPD["result,${num},message,venue,location,longitude"]}"
		VENUE[LATITUDE]="${UPD["result,${num},message,venue,location,latitude"]}"
		VENUE[FOURSQUARE]="${UPD["result,${num},message,venue,foursquare_id"]}"
	fi

	# Location
	LOCATION[LONGITUDE]="${UPD["result,${num},message,location,longitude"]}"
	LOCATION[LATITUDE]="${UPD["result,${num},message,location,latitude"]}"

	# service messages, group or channel only!
	if [[ "${CHAT[ID]}" == "-"* ]] ; then
	    # new chat member
	    if [ -n "${UPD["result,${num},message,new_chat_member,id"]}" ]; then
		SERVICE[NEWMEMBER]="${UPD["result,${num},message,new_chat_member,id"]}"
		NEWMEMBER[ID]="${SERVICE[NEWMEMBER]}"
		NEWMEMBER[FIRST_NAME]="$(JsonDecode "${UPD["result,${num},message,new_chat_member,first_name"]}")"
		NEWMEMBER[LAST_NAME]="$(JsonDecode "${UPD["result,${num},message,new_chat_member,last_name"]}")"
		NEWMEMBER[USERNAME]="$(JsonDecode "${UPD["result,${num},message,new_chat_member,username"]}")"
		NEWMEMBER[ISBOT]="${UPD["result,${num},message,new_chat_member,is_bot"]}"
		MESSAGE[0]="/_new_chat_member ${NEWMEMBER[ID]} ${NEWMEMBER[USERNAME]:=${NEWMEMBER[FIRST_NAME]} ${NEWMEMBER[LAST_NAME]}}"
	    fi
	    # left chat member
	    if [ -n "${UPD["result,${num},message,left_chat_member,id"]}" ]; then
		SERVICE[LEFTMEMBER]="${UPD["result,${num},message,left_chat_member,id"]}"
		LEFTMEMBER[ID]="${SERVICE[LEFTMEBER]}"
		LEFTMEMBER[FIRST_NAME]="$(JsonDecode "${UPD["result,${num},message,left_chat_member,first_name"]}")"
		LEFTMEMBER[LAST_NAME]="$(JsonDecode "${UPD["result,${num},message,left_chat_member,last_name"]}")"
		LEFTMEBER[USERNAME]="$(JsonDecode "${UPD["result,${num},message,left_chat_member,username"]}")"
		LEFTMEMBER[ISBOT]="${UPD["result,${num},message,left_chat_member,is_bot"]}"
		MESSAGE[0]="/_left_chat_member ${LEFTMEMBER[ID]} ${LEFTMEMBER[USERNAME]:=${LEFTMEMBER[FIRST_NAME]} ${LEFTMEMBER[LAST_NAME]}}"
	    fi
	    # chat title / photo, check for any of them!
	    if grep -qs -e '\["result",'"${num}"',"message","new_chat_[tp]' <<<"${UPDATE}"; then
		SERVICE[NEWTITLE]="$(JsonDecode "${UPD["result,${num},message,new_chat_title"]}")"
		[ -n "${SERVICE[NEWTITLE]}" ] &&\
			MESSAGE[0]="/_new_chat_title ${USER[ID]} ${SERVICE[NEWTITLE]}"
		SERVICE[NEWPHOTO]="$(get_file "${UPD["result,${num},message,new_chat_photo,0,file_id"]}")"
		[ -n "${SERVICE[NEWPHOTO]}" ] &&\
			 MESSAGE[0]="/_new_chat_photo ${USER[ID]} ${SERVICE[NEWPHOTO]}"
	    fi
	    # pinned message
	    if [ -n "${UPD["result,${num},message,pinned_message,message_id"]}" ]; then
		SERVICE[PINNED]="${UPD["result,${num},message,pinned_message,message_id"]}"
		PINNED[ID]="${SERVICE[PINNED]}"
		PINNED[MESSAGE]="$(JsonDecode "${UPD["result,${num},message,pinned_message,text"]}")"
		MESSAGE[0]="/_new_pinned_message ${USER[ID]} ${PINNED[ID]} ${PINNED[MESSAGE]}"
	    fi
	    # migrate to super group
	    if [ -n "${UPD["result,${num},message,migrate_to_chat_id"]}" ]; then
		MIGRATE[TO]="${UPD["result,${num},message,migrate_to_chat_id"]}"
		MIGRATE[FROM]="${UPD["result,${num},message,migrate_from_chat_id"]}"
		# CHAT is already migrated, so set new chat id
		[ "${CHAT[ID]}" = "${MIGRATE[FROM]}" ] && CHAT[ID]="${MIGRATE[FROM]}"
		SERVICE[MIGRATE]="${MIGRATE[FROM]} ${MIGRATE[TO]}"
		MESSAGE[0]="/_migrate_group ${SERVICE[MIGRATE]}"
	    fi
	    # set SERVICE to yes if a service message was received
	    [[ "${SERVICE[*]}" =~  ^[[:blank:]]*$ ]] || SERVICE[0]="yes"
	fi

	# split message in command and args
	[[ "${MESSAGE[0]}" == "/"* ]] && read -r CMD <<<"${MESSAGE[0]}" &&  CMD[0]="${CMD[0]%%@*}"
	# everything went well
	return 0
}

#########################
# bot startup actions, call before start polling or webhook loop
declare -A BASHBOTBLOCKED
start_bot() {
	local DEBUGMSG
	# startup message
	DEBUGMSG="BASHBOT startup actions, mode set to \"${1:-normal}\" =========="
	log_update "${DEBUGMSG}"
	# redirect to Debug.log
	if [[ "$1" == *"debug" ]]; then
		# shellcheck disable=SC2153
		exec &>>"${DEBUGLOG}"
		log_debug "${DEBUGMSG}";
	fi
	DEBUGMSG="$1"
	[[ "${DEBUGMSG}" == "xdebug"* ]] && set -x
	# cleaup old pipes and empty logfiles
	find "${DATADIR}" -type p -not -name "webhook-fifo-*" -delete
	find "${DATADIR}" -size 0 -name "*.log" -delete
	# load addons on startup
	for addons in "${ADDONDIR:-.}"/*.sh ; do
		# shellcheck disable=SC1090
		[ -r "${addons}" ] && source "${addons}" "startbot" "${DEBUGMSG}"
	done
	# shellcheck disable=SC1090
	source "${COMMANDS}" "startbot"
	# start timer events
	if [ -n "${BASHBOT_START_TIMER}" ] ; then
		# shellcheck disable=SC2064
		trap "event_timer ${DEBUGMSG}" ALRM
		start_timer &
		# shellcheck disable=SC2064
		trap "kill -9 $!; exit" EXIT INT HUP TERM QUIT 
	fi
	# cleanup on start
	bot_cleanup "startup"
	# read blocked users
	jssh_readDB_async "BASHBOTBLOCKED" "${BLOCKEDFILE}"
	# inform botadmin about start
	send_normal_message "$(getConfigKey "botadmin")" "Bot ${ME} $2 started ..." &
}

# main polling updates loop, should never terminate
get_updates(){
	local errsleep="200" DEBUG="$1" OFFSET=0
	# adaptive sleep defaults
	local nextsleep="100"
	local stepsleep="${BASHBOT_SLEEP_STEP:-100}"
	local maxsleep="${BASHBOT_SLEEP:-5000}"
	printf "%(%c)T: %b\n" -1 "Bot startup actions done, start polling updates ..."
	while true; do
		# adaptive sleep in ms rounded to next 0.1 s
		sleep "$(_round_float "${nextsleep}e-3" "1")"
		# get next update
		# shellcheck disable=SC2153
		UPDATE="$(getJson "${URL}/getUpdates?offset=${OFFSET}" 2>/dev/null | "${JSONSHFILE}" -b -n 2>/dev/null | iconv -f utf-8 -t utf-8 -c)"
		# did we get an response?
		if [ -n "${UPDATE}" ]; then
			# we got something, do processing
			[ "${OFFSET}" = "-999" ] && [ "${nextsleep}" -gt "$((maxsleep*2))" ] &&\
				log_error "Recovered from timeout/broken/no connection, continue with telegram updates"
			# calculate next sleep interval
			((nextsleep+= stepsleep , nextsleep= nextsleep>maxsleep ?maxsleep:nextsleep))
			# warn if webhook is set
			if grep -q '^\["error_code"\]	409' <<<"${UPDATE}"; then
				[ "${OFFSET}" != "-999" ] && nextsleep="${stepsleep}"
				OFFSET="-999"; errsleep="$(_round_float "$(( errsleep= 300*nextsleep ))e-3")"
				log_error "Warning conflicting webhook set, can't get updates until your run delete_webhook! Sleep $((errsleep/60)) min ..."
				sleep "${errsleep}"
				continue
			fi
			# Offset
			OFFSET="$(grep <<<"${UPDATE}" '\["result",[0-9]*,"update_id"\]' | tail -1 | cut -f 2)"
			((OFFSET++))

			if [ "${OFFSET}" != "1" ]; then
				nextsleep="100"
				process_multi_updates "${DEBUG}"
			fi
		else
			# oops, something bad happened, wait maxsleep*10
			(( nextsleep=nextsleep*2 , nextsleep= nextsleep>maxsleep*10 ?maxsleep*10:nextsleep ))
			# second time, report problem
			if [ "${OFFSET}" = "-999" ]; then
			    log_error "Repeated timeout/broken/no connection on telegram update, sleep $(_round_float "${nextsleep}e-3")s"
			    # try to recover
			    if _is_function bashbotBlockRecover && [ -z "$(getJson "${ME_URL}")" ]; then
				log_error "Try to recover, calling bashbotBlockRecover ..."
				bashbotBlockRecover >>"${ERRORLOG}"
			    fi
			fi
			OFFSET="-999"
		fi
	done
}



declare -Ax BASHBOT_EVENT_INLINE BASHBOT_EVENT_MESSAGE BASHBOT_EVENT_CMD BASHBOT_EVENT_REPLYTO BASHBOT_EVENT_FORWARD BASHBOT_EVENT_SEND
declare -Ax BASHBOT_EVENT_CONTACT BASHBOT_EVENT_LOCATION BASHBOT_EVENT_FILE BASHBOT_EVENT_TEXT BASHBOT_EVENT_TIMER BASHBOT_BLOCKED

start_timer(){
	# send alarm every ~60 s
	while :; do
		sleep 59.5
    		kill -ALRM $$
	done;
}

EVENT_TIMER="0"
event_timer() {
	local key timer debug="$1"
	(( EVENT_TIMER++ ))
	# shellcheck disable=SC2153
	for key in "${!BASHBOT_EVENT_TIMER[@]}"
	do
		timer="${key##*,}"
		[[ ! "${timer}" =~ ^-*[1-9][0-9]*$ ]] && continue
		if [ "$(( EVENT_TIMER % timer ))" = "0" ]; then
			_exec_if_function "${BASHBOT_EVENT_TIMER[${key}]}" "timer" "${key}" "${debug}"
			[ "$(( EVENT_TIMER % timer ))" -lt "0" ] && \
				unset BASHBOT_EVENT_TIMER["${key}"]
		fi
	done
}

event_inline() {
	local key debug="$1"
	# shellcheck disable=SC2153
	for key in "${!BASHBOT_EVENT_INLINE[@]}"
	do
		_exec_if_function "${BASHBOT_EVENT_INLINE[${key}]}" "inline" "${key}" "${debug}"
	done
}
event_message() {
	local key debug="$1"
	# ${MESSAEG[*]} event_message
	# shellcheck disable=SC2153
	for key in "${!BASHBOT_EVENT_MESSAGE[@]}"
	do
		 _exec_if_function "${BASHBOT_EVENT_MESSAGE[${key}]}" "message" "${key}" "${debug}"
	done
	
	# ${TEXT[*]} event_text
	if [ -n "${MESSAGE[0]}" ]; then
		# shellcheck disable=SC2153
		for key in "${!BASHBOT_EVENT_TEXT[@]}"
		do
			_exec_if_function "${BASHBOT_EVENT_TEXT[${key}]}" "text" "${key}" "${debug}"
		done

		# ${CMD[*]} event_cmd
		if [ -n "${CMD[0]}" ]; then
			# shellcheck disable=SC2153
			for key in "${!BASHBOT_EVENT_CMD[@]}"
			do
				_exec_if_function "${BASHBOT_EVENT_CMD[${key}]}" "command" "${key}" "${debug}"
			done
		fi
	fi
	# ${REPLYTO[*]} event_replyto
	if [ -n "${REPLYTO[UID]}" ]; then
		# shellcheck disable=SC2153
		for key in "${!BASHBOT_EVENT_REPLYTO[@]}"
		do
			_exec_if_function "${BASHBOT_EVENT_REPLYTO[${key}]}" "replyto" "${key}" "${debug}"
		done
	fi

	# ${FORWARD[*]} event_forward
	if [ -n "${FORWARD[UID]}" ]; then
		# shellcheck disable=SC2153
		for key in "${!BASHBOT_EVENT_FORWARD[@]}"
		do
			 _exec_if_function && "${BASHBOT_EVENT_FORWARD[${key}]}" "forward" "${key}" "${debug}"
		done
	fi

	# ${CONTACT[*]} event_contact
	if [ -n "${CONTACT[FIRST_NAME]}" ]; then
		# shellcheck disable=SC2153
		for key in "${!BASHBOT_EVENT_CONTACT[@]}"
		do
			_exec_if_function "${BASHBOT_EVENT_CONTACT[${key}]}" "contact" "${key}" "${debug}"
		done
	fi

	# ${VENUE[*]} event_location
	# ${LOCATION[*]} event_location
	if [ -n "${LOCATION[LONGITUDE]}" ] || [ -n "${VENUE[TITLE]}" ]; then
		# shellcheck disable=SC2153
		for key in "${!BASHBOT_EVENT_LOCATION[@]}"
		do
			_exec_if_function "${BASHBOT_EVENT_LOCATION[${key}]}" "location" "${key}" "${debug}"
		done
	fi

	# ${URLS[*]} event_file
	# NOTE: compare again #URLS -1 blanks!
	if [[ "${URLS[*]}" != "     " ]]; then
		# shellcheck disable=SC2153
		for key in "${!BASHBOT_EVENT_FILE[@]}"
		do
			_exec_if_function "${BASHBOT_EVENT_FILE[${key}]}" "file" "${key}" "${debug}"
		done
	fi

}


# file: modules/message.sh
# do not edit, this file will be overwritten on update

# This file is public domain in the USA and all free countries.
# Elsewhere, consider it to be WTFPLv2. (wtfpl.net/txt/copying)
#
# shellcheck disable=SC1117

# will be automatically sourced from bashbot

# source once magic, function named like file
eval "$(basename "${BASH_SOURCE[0]}")(){ :; }"

# source from commands.sh to use the sendMessage functions

MSG_URL=${URL}'/sendMessage'
EDIT_URL=${URL}'/editMessageText'

#
# send/edit message variants ------------------
#

# $1 CHAT $2 message
send_normal_message() {
	local len text; text="$(JsonEscape "$2")"
	until [ -z "${text}" ]; do
		if [ "${#text}" -le 4096 ]; then
			sendJson "$1" '"text":"'"${text}"'"' "${MSG_URL}"
			break
		else
			len=4095
			[ "${text:4095:2}" != "\n" ] &&\
				len="${text:0:4096}" && len="${len%\\n*}" && len="${#len}"
			sendJson "$1" '"text":"'"${text:0:${len}}"'"' "${MSG_URL}"
			text="${text:$((len+2))}"
		fi
	done
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2"
}

# $1 CHAT $2 message
send_markdown_message() {
	_format_message_url "$1" "$2" ',"parse_mode":"markdown"' "${MSG_URL}"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2"
}

# $1 CHAT $2 message
send_markdownv2_message() {
	_markdownv2_message_url "$1" "$2" ',"parse_mode":"markdownv2"' "${MSG_URL}"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2"
}

# $1 CHAT $2 message
send_html_message() {
	_format_message_url "$1" "$2" ',"parse_mode":"html"' "${MSG_URL}"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2"
}

# $1 CHAT $2 msg-id $3 message
edit_normal_message() {
	_format_message_url "$1" "$3" ',"message_id":'"$2"'' "${EDIT_URL}"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3"
}

# $1 CHAT $2 msg-id $3 message
edit_markdown_message() {
	_format_message_url "$1" "$3" ',"message_id":'"$2"',"parse_mode":"markdown"' "${EDIT_URL}"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3"
}

# $1 CHAT $2 msg-id $3 message
edit_markdownv2_message() {
	_markdownv2_message_url "$1" "$3" ',"message_id":'"$2"',"parse_mode":"markdownv2"' "${EDIT_URL}"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3"
}

# $1 CHAT $2 msg-id $3 message
edit_html_message() {
	_format_message_url "$1" "$3" ',"message_id":'"$2"',"parse_mode":"html"' "${EDIT_URL}"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3"
}

# $1 chat $2 mesage_id, $3 caption
edit_message_caption() {
	sendJson "$1" '"message_id":'"$2"',"caption":"'"$3"'"' "${URL}/editMessageCaption"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3"
}


# $ chat $2 msg_id $3 nolog
delete_message() {
	[ -z "$3" ] && log_update "Delete Message CHAT=$1 MSG_ID=$2"
	sendJson "$1" '"message_id": '"$2"'' "${URL}/deleteMessage"
	[ "${BOTSENT[OK]}" = "true" ] && BOTSENT[CHAT]="$1"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3"
}


# internal function, send/edit formatted message with parse_mode and URL
# $1 CHAT $2 message $3 action $4 URL
_format_message_url(){
	local text; text="$(JsonEscape "$2")"
	[ "${#text}" -ge 4096 ] && log_error "Warning: html/markdown message longer than 4096 characters, message is rejected if formatting crosses 4096 border."
	until [ -z "${text}" ]; do
		sendJson "$1" '"text":"'"${text:0:4096}"'"'"$3"'' "$4"
		text="${text:4096}"
	done
}

# internal function, send/edit markdownv2 message with URL
# $1 CHAT $2 message $3 action $4 URL
_markdownv2_message_url() {
	local text; text="$(JsonEscape "$2")"
	[ "${#text}" -ge 4096 ] && log_error "Warning: markdownv2 message longer than 4096 characters, message is rejected if formatting crosses 4096 border."
	# markdown v2 needs additional double escaping!
	text="$(sed -E -e 's|([_|~`>+=#{}()!.-])|\\\1|g' <<< "${text}")"
	until [ -z "${text}" ]; do
		sendJson "$1" '"text":"'"${text:0:4096}"'"'"$3"'' "$4"
		text="${text:4096}"
	done
}

#
# send keyboard, buttons, files ---------------
#

# $1 CHAT $2 message $3 keyboard
send_keyboard() {
	if [[ "$3" != *'['* ]]; then old_send_keyboard "${@}"; return; fi
	local text='"text":"'"Keyboard:"'"'
	if [ -n "$2" ]; then
		text="$(JsonEscape "$2")"
		text='"text":"'"${text//$'\n'/\\n}"'"'
	fi
	local one_time=', "one_time_keyboard":true' && [ -n "$4" ] && one_time=""
	# '"text":"$2", "reply_markup": {"keyboard": [ $3 ], "one_time_keyboard": true}'
	sendJson "$1" "${text}"', "reply_markup": {"keyboard": [ '"$3"' ] '"${one_time}"'}' "${MSG_URL}"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2"
}

# $1 CHAT $2 message $3 remove
remove_keyboard() {
	local text='"text":"'"remove custom keyboard ..."'"'
	if [ -n "$2" ]; then
		text="$(JsonEscape "$2")"
		text='"text":"'"${text//$'\n'/\\n}"'"'
	fi
	sendJson "$1" "${text}"', "reply_markup": {"remove_keyboard":true}' "${MSG_URL}"
	# delete message if no message or $3 not empty
	#JSON='"text":"$2", "reply_markup": {"remove_keyboard":true}'
	[[ -z "$2" || -n "$3" ]] && delete_message "$1" "${BOTSENT[ID]}" "nolog"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2"
}

# buttons will specified as "texts
#|url" ... "text|url" empty arg starts new row
# url not starting with http:// or https:// will be send as callback_data 
send_inline_buttons(){
	send_inline_keyboard "$1" "$2" "$(_button_row "${@:3}")"
}

# $1 CHAT $2 message-id $3 buttons
# buttons will specified as "text|url" ... "text|url" empty arg starts new row
# url not starting with http:// or https:// will be send as callback_data 
edit_inline_buttons(){
	edit_inline_keyboard "$1" "$2" "$(_button_row "${@:3}")"
}


# $1 CHAT $2 message $3 button text $4 button url
send_button() {
	send_inline_keyboard "$1" "$2" '[{"text":"'"$(JsonEscape "$3")"'", "url":"'"$4"'"}]'
}

# helper function to create json for a button row
# buttons will specified as "text|url" ... "text|url" empty arg starts new row
# url not starting with http:// or https:// will be send as callback_data 
_button_row() {
	[ -z "$1" ] && return 1
	local arg type json sep
	for arg in "$@"
	do
		[ -z "${arg}" ] && sep="],[" && continue
		type="callback_data"
		[[ "${arg##*|}" =~ ^(https*://|tg://) ]] && type="url"
		json+="${sep}"'{"text":"'"$(JsonEscape "${arg%|*}")"'", "'"${type}"'":"'"${arg##*|}"'"}'
		sep=","
	done
	printf "[%s]" "${json}"
}

# raw inline functions, for special use
# $1 CHAT $2 message-id $3 keyboard
edit_inline_keyboard() {
	# JSON='"message_id":"$2", "reply_markup": {"inline_keyboard": [ $3->[{"text":"text", "url":"url"}]<- ]}'
	sendJson "$1" '"message_id":'"$2"', "reply_markup": {"inline_keyboard": [ '"$3"' ]}' "${URL}/editMessageReplyMarkup"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2"
}


# $1 CHAT $2 message $3 keyboard
send_inline_keyboard() {
	local text; text='"text":"'$(JsonEscape "$2")'"'; [ -z "$2" ] && text='"text":"..."'
	sendJson "$1" "${text}"', "reply_markup": {"inline_keyboard": [ '"$3"' ]}' "${MSG_URL}"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3"
}

# $1 callback id, $2 text to show, alert if not empty
answer_callback_query() {
	local alert
	[ -n "$3" ] && alert='","show_alert": true'
	sendJson "" '"callback_query_id": "'"$1"'","text":"'"$2${alert}"'"' "${URL}/answerCallbackQuery"
}

# $1 chat, $2 file_id on telegram server 
send_sticker() {
	sendJson "$1" '"sticker": "'"$2"'"' "${URL}/sendSticker"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2"
}


# only curl can send files ... 
if detect_curl ; then
  # there are no checks if URL or ID exists
  # $1 chat $3 ... $n URL or ID
  send_album(){
	[ -z "$1" ] && return 1
	[ -z "$3" ] && return 2	# minimum 2 files
	local CHAT JSON IMAGE; CHAT="$1"; shift 
	for IMAGE in "$@"
	do
		[ -n "${JSON}" ] && JSON+=","
		JSON+='{"type":"photo","media":"'${IMAGE}'"}'
	done
	# shellcheck disable=SC2086
	res="$("${BASHBOT_CURL}" -s -k ${BASHBOT_CURL_ARGS} "${URL}/sendMediaGroup" -F "chat_id=${CHAT}"\
			-F "media=[${JSON}]" | "${JSONSHFILE}" -s -b -n 2>/dev/null )"
	sendJsonResult "${res}" "send_album (curl)" "${CHAT}" "$@"
	[[ -z "${SOURCE}" && -n "${BASHBOT_EVENT_SEND[*]}" ]] && event_send "album" "$@" &
  }
else
  send_album(){
	log_error "Sorry, wget Album upload not implemented"
	BOTSENT[OK]="false"
	[[ -z "${SOURCE}" && -n "${BASHBOT_EVENT_SEND[*]}" ]] && event_send "album" "$@" &
  }
fi

# supports local file, URL and file_id
# $1 chat, $2 file https::// file_id:// , $3 caption, $4 extension (optional)
send_file(){
	local url what num stat media capt file="$2" ext="$4"
	capt="$(JsonEscape "$3")"
	if [[ "${file}" =~ ^https*:// ]]; then
		media="URL"
	elif [[ "${file}" == file_id://* ]]; then
		media="ID"
		file="${file#file_id://}"
	else
		# we have a file, check file location ...
		media="FILE"
		file="$(checkUploadFile "$1" "$2" "send_file")"
		[ -z "${file}" ] && return 1
		# file OK, let's continue
	fi

	# no type given, use file ext, if no ext type photo
	if [ -z "${ext}" ]; then
		ext="${file##*.}"
		[ "${ext}" = "${file}" ] && ext="photo"
	fi
	# select upload URL
	case "${ext}" in
		photo|png|jpg|jpeg|gif|pic)
			url="${URL}/sendPhoto"; what="photo"; num=",0"; stat="upload_photo"
			;;
        	audio|mp3|flac)
			url="${URL}/sendAudio"; what="audio"; stat="upload_audio"
			;;
		sticker|webp)
			url="${URL}/sendSticker"; what="sticker"; stat="upload_photo"
			;;
		video|mp4)
			url="${URL}/sendVideo"; what="video"; stat="upload_video"
			;;
		voice|ogg)
			url="${URL}/sendVoice"; what="voice"; stat="record_audio"
			;;
		*)	url="${URL}/sendDocument"; what="document"; stat="upload_document"
			;;
	esac

	# show file upload to user
	send_action "$1" "${stat}"
	# select method to send
	case "${media}" in
		FILE)	# send local file ...
			sendUpload "$1" "${what}" "${file}" "${url}" "${capt//\\n/$'\n'}";;

		URL|ID)	# send URL, file_id ...
			sendJson "$1" '"'"${what}"'":"'"${file}"'","caption":"'"${capt//\\n/$'\n'}"'"' "${url}"
	esac
	# get file_id and file_type
	if [ "${BOTSENT[OK]}" = "true" ]; then
		BOTSENT[FILE_ID]="${UPD["result,${what}${num},file_id"]}"
		BOTSENT[FILE_TYPE]="${what}"
	fi
	return 0
}

# $1 chat $2 typing upload_photo record_video upload_video record_audio upload_audio upload_document find_location
send_action() {
	[ -z "$2" ] && return
	sendJson "$1" '"action": "'"$2"'"' "${URL}/sendChatAction" &
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2"
}

# $1 chat $2 emoji “🎲”, “🎯”, “🏀”, “⚽”, “🎰" "🎳"
# code: "\ud83c\udfb2" "\ud83c\udfaf" "\ud83c\udfc0" "\u26bd" "\ud83c\udfb0"
# text: ":game_die:" ":dart:" ":basketball:" ":soccer:" :slot_machine:"
# $3 reply_to_id
send_dice() {
	local reply emoji='\ud83c\udfb2'	# default "🎲"
	[[ "$3" =~ ^[${o9o9o9}-]+$ ]] && reply=',"reply_to_message_id":'"$3"',"allow_sending_without_reply": true'
	case "$2" in # convert input to single character emoji
		*🎲*|*game*|*dice*|*'dfb2'*|*'DFB2'*)	: ;;
		*🎯*|*dart*  |*'dfaf'*|*'DFAF'*)	emoji='\ud83c\udfaf' ;;
		*🏀*|*basket*|*'dfc0'*|*'DFC0'*)	emoji='\ud83c\udfc0' ;;
		*⚽*|*soccer*|*'26bd'*|*'26BD'*)	emoji='\u26bd' ;;
		*🎰*|*slot*  |*'dfb0'*|*'DFB0'*)	emoji='\ud83c\udfb0' ;;
		*🎳*|*bowl*  |*'dfb3'*|*'DFB3'*)	emoji='\ud83c\udfb3' ;;
	esac
	sendJson "$1" '"emoji": "'"${emoji}"'"'"${reply}" "${URL}/sendDice"
	if [ "${BOTSENT[OK]}" = "true" ]; then
		BOTSENT[DICE]="${UPD["result,dice,emoji"]}"
		BOTSENT[RESULT]="${UPD["result,dice,value"]}"
	else
		# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
		processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2"
	fi
}

# $1 CHAT $2 lat $3 long
send_location() {
	[ -z "$3" ] && return
	sendJson "$1" '"latitude": '"$2"', "longitude": '"$3"'' "${URL}/sendLocation"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3"
}

# $1 CHAT $2 lat $3 long $4 title $5 address $6 foursquare id
send_venue() {
	local add=""
	[ -z "$5" ] && return
	[ -n "$6" ] && add=', "foursquare_id": '"$6"''
	sendJson "$1" '"latitude": '"$2"', "longitude": '"$3"', "address": "'"$5"'", "title": "'"$4"'"'"${add}" "${URL}/sendVenue"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3" "$4" "$5" "$6"
}


#
# other send message variants ---------------------------------
#

# $1 CHAT $2 from chat  $3 from msg id
forward_message() {
	[ -z "$3" ] && return
	sendJson "$1" '"from_chat_id": '"$2"', "message_id": '"$3"'' "${URL}/forwardMessage"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3"
}

# $1 CHAT $2 from chat  $3 from msg id
copy_message() {
	[ -z "$3" ] && return
	sendJson "$1" '"from_chat_id": '"$2"', "message_id": '"$3"'' "${URL}/copyMessage"
	# func="$1" err="$2" chat="$3" user="$4" emsg="$5" remaining args
	[ -n "${BOTSENT[ERROR]}" ] && processError "${FUNCNAME[0]}" "${BOTSENT[ERROR]}" "$1" "" "${BOTSENT[DESCRIPTION]}" "$2" "$3"
}

# $1 CHAT $2 bashbot formatted message, see manual advanced usage
send_message() {
	[ -z "$2" ] && return
	local text keyboard btext burl no_keyboard file lat long title address sent
	text="$(sed <<< "$2" 's/ mykeyboardend.*//;s/ *my[kfltab][a-z]\{2,13\}startshere.*//')$(sed <<< "$2" -n '/mytextstartshere/ s/.*mytextstartshere//p')"
	#shellcheck disable=SC2001
	text="$(sed <<< "${text}" 's/ *mynewlinestartshere */\n/g')"
	text="${text//$'\n'/\\n}"
	[ "$3" != "safe" ] && {
		no_keyboard="$(sed <<< "$2" '/mykeyboardendshere/!d;s/.*mykeyboardendshere.*/mykeyboardendshere/')"
		keyboard="$(sed <<< "$2" '/mykeyboardstartshere /!d;s/.*mykeyboardstartshere *//;s/ *my[nkfltab][a-z]\{2,13\}startshere.*//;s/ *mykeyboardendshere.*//')"
		btext="$(sed <<< "$2" '/mybtextstartshere /!d;s/.*mybtextstartshere //;s/ *my[nkfltab][a-z]\{2,13\}startshere.*//;s/ *mykeyboardendshere.*//')"
		burl="$(sed <<< "$2" '/myburlstartshere /!d;s/.*myburlstartshere //;s/ *my[nkfltab][a-z]\{2,13\}startshere.*//g;s/ *mykeyboardendshere.*//g')"
		file="$(sed <<< "$2" '/myfile[^s]*startshere /!d;s/.*myfile[^s]*startshere //;s/ *my[nkfltab][a-z]\{2,13\}startshere.*//;s/ *mykeyboardendshere.*//')"
		lat="$(sed <<< "$2" '/mylatstartshere /!d;s/.*mylatstartshere //;s/ *my[nkfltab][a-z]\{2,13\}startshere.*//;s/ *mykeyboardendshere.*//')"
		long="$(sed <<< "$2" '/mylongstartshere /!d;s/.*mylongstartshere //;s/ *my[nkfltab][a-z]\{2,13\}startshere.*//;s/ *mykeyboardendshere.*//')"
		title="$(sed <<< "$2" '/mytitlestartshere /!d;s/.*mytitlestartshere //;s/ *my[kfltab][a-z]\{2,13\}startshere.*//;s/ *mykeyboardendshere.*//')"
		address="$(sed <<< "$2" '/myaddressstartshere /!d;s/.*myaddressstartshere //;s/ *my[nkfltab][a-z]\{2,13\}startshere.*//;s/ *mykeyboardendshere.*//')"
	}
	if [ -n "${no_keyboard}" ]; then
		remove_keyboard "$1" "${text}"
		sent=y
	fi
	if [ -n "${keyboard}" ]; then
		if [[ "${keyboard}" != *"["* ]]; then	# pre 0.60 style
			keyboard="[ ${keyboard//\" \"/\" \] , \[ \"} ]"
		fi
		send_keyboard "$1" "${text}" "${keyboard}"
		sent=y
	fi
	if [ -n "${btext}" ] && [ -n "${burl}" ]; then
		send_button "$1" "${text}" "${btext}" "${burl}"
		sent=y
	fi
	if [ -n "${file}" ]; then
		send_file "$1" "${file}" "${text}"
		sent=y
	fi
	if [ -n "${lat}" ] && [ -n "${long}" ]; then
		if [ -n "${address}" ] && [ -n "${title}" ]; then
			send_venue "$1" "${lat}" "${long}" "${title}" "${address}"
		else
			send_location "$1" "${lat}" "${long}"
		fi
		sent=y
	fi
	if [ "${sent}" != "y" ];then
		send_text_mode "$1" "${text}"
	fi

}

# $1 CHAT $2 message starting possibly with html_parse_mode or markdown_parse_mode
# not working, fix or remove after 1.0!!
send_text_mode() {
	case "$2" in
		'html_parse_mode'*)
			send_html_message "$1" "${2//html_parse_mode}"
			;;
		'markdown_parse_mode'*)
			send_markdown_message "$1" "${2//markdown_parse_mode}"
			;;
		*)
			send_normal_message "$1" "$2"
			;;
	esac
}


##############################
# read commands file if we are not sourced
COMMANDS="${BASHBOT_ETC:-.}/commands.sh"
if [  -r "${COMMANDS}" ]; then
	# shellcheck source=./commands.sh
	 source "${COMMANDS}" "source"
else
	[ -z "${SOURCE}" ] && printf "${RED}Warning: ${COMMANDS} does not exist or is not readable!.${NN}"
fi
# no debug checks on source
[ -z "${SOURCE}" ] && debug_checks "start" "$@"


#####################
# BASHBOT INTERNAL functions
#

# do we have BSD sed
sed '1ia' </dev/null 2>/dev/null || printf "${ORANGE}Warning: You may run on a BSD style system without gnu utils ...${NN}"
#jsonDB is now mandatory
if ! _is_function jssh_newDB; then
	printf "${RED}ERROR: Mandatory module jsonDB is missing or not readable!${NN}"
	exit_source 6
fi

# $1 postfix, e.g. chatid
# $2 prefix, back- or startbot-
procname(){
	printf '%s\n' "$2${ME}_$1"
}

# $1 string to search for programme incl. parameters
# returns a list of PIDs of all current bot processes matching $1
proclist() {
	# shellcheck disable=SC2009
	ps -fu "${UID}" | grep -F "$1" | grep -v ' grep'| grep -F "${ME}" | sed 's/\s\+/\t/g' | cut -f 2
}

# $1 string to search for programme to kill
killallproc() {
	local procid; procid="$(proclist "$1")"
	if [ -n "${procid}" ] ; then
		# shellcheck disable=SC2046
		kill $(proclist "$1")
		sleep 1
		procid="$(proclist "$1")"
		# shellcheck disable=SC2046
		[ -n "${procid}" ] && kill $(proclist -9 "$1")
	fi
	debug_checks "end killallproc" "$1"
}

# URL path for file id, $1 file_id
# use download_file "path" to  download file
get_file() {
	[ -z "$1" ] && return
	sendJson ""  '"file_id": "'"$1"'"' "${URL}/getFile"
	printf "%s\n" "${UPD["result,file_path"]}"
}
# download file to DATADIR
# $1 URL path, $2 proposed filename (may modified/ignored)
# outputs final filename
# keep old function name for backward compatibility
alias download="download_file"
download_file() {
	local url="$1" file="${2:-$1}"
	# old mode if full URL is given
	if [[  "${1}" =~ ^https*:// ]]; then
	   # random filename if not given for http
	   if [ -z "$2" ]; then
		: "$(mktemp -u  -p . "XXXXXXXXXX" 2>/dev/null)"
		file="download-${_#./}"
	  fi
	else
		# prefix https://api.telegram...
		url="${FILEURL}/${url}"
	fi
	# filename: replace "/" with "-", use mktemp if exist
	file="${DATADIR:-.}/${file//\//-}"
	[ -f "${file}" ] && file="$(mktemp -p "${DATADIR:-.}" "XXXXX-${file##*/}" )"
	getJson "${url}" >"${file}" || return
	# output absolute file path
	printf "%s\n" "$(cd "${file%/*}" >/dev/null 2>&1 && pwd)/${file##*/}"
}
# notify mycommands about errors while sending
# $1 calling function  $2 error $3 chat $4 user $5 error message $6 ... remaining args to calling function
# calls function based on error: bashbotError{function} basbotError{error}
# if no specific function exist try to call bashbotProcessError
processError(){
	local func="$1" err="$2"
	[[ "${err}" != "4"* ]] && return 1
	# check for bashbotError${func} provided in mycommands
	# shellcheck disable=SC2082
	if _is_function "bashbotError_${func}"; then 
		"bashbotError_${func}" "$@"
	# check for bashbotError${err} provided in mycommands
	elif _is_function "bashbotError_${err}"; then 
		"bashbotError_${err}" "$@"
	# noting found, try bashbotProcessError
	else
		_exec_if_function bashbotProcessError "$@"
	fi
}

# iconv used to filter out broken utf characters, if not installed fake it
if ! _exists iconv; then
	log_update "Warning: iconv not installed, pls imstall iconv!"
	function iconv() { cat; }
fi

TIMEOUT="${BASHBOT_TIMEOUT:-20}"
[[ "${TIMEOUT}" =~ ^[${o9o9o9}]+$ ]] || TIMEOUT="20"

# usage: sendJson "chat" "JSON" "URL"
sendJson(){
	local json chat=""
	if [ -n "$1" ]; then
		 chat='"chat_id":'"$1"','
		 [[ "$1" == *[!${o9o9o9}-]* ]] && chat='"chat_id":"'"$1"' NAN",'	# chat id not a number!
	fi
	# compose final json
	json='{'"${chat} $(iconv -f utf-8 -t utf-8 -c <<<"$2")"'}'
	if [ -n "${BASHBOTDEBUG}" ] ; then
		log_update "sendJson (${DETECTED_CURL}) CHAT=${chat#*:} JSON=$(cleanEscape "${json:0:100}") URL=${3##*/}"
		log_message "DEBUG sendJson ==========\n$("${JSONSHFILE}" -b -n  <<<"$(cleanEscape "${json}")" 2>&1)"
	fi
	# chat id not a number
	if [[ "${chat}" == *"NAN\"," ]]; then
		sendJsonResult "$(printf '["ok"]\tfalse\n["error_code"]\t400\n["description"]\t"Bad Request: chat id not a number"\n')"\
			"sendJson (NAN)" "$@"
		return
	fi
	# OK here we go ...
	# route to curl/wget specific function
	res="$(sendJson_do "${json}" "$3")"
	# check telegram response
	sendJsonResult "${res}" "sendJson (${DETECTED_CURL})" "$@"
	[ -n "${BASHBOT_EVENT_SEND[*]}" ] && event_send "send" "${@}" &
}

UPLOADDIR="${BASHBOT_UPLOAD:-${DATADIR}/upload}"

# $1 chat $2 file, $3 calling function
# return final file name or empty string on error
checkUploadFile() {
	local err file="$2"
	[[ "${file}" == *'..'* || "${file}" == '.'* ]] && err=1 	# no directory traversal
	if [[ "${file}" == '/'* ]] ; then
		[[ ! "${file}" =~ ${FILE_REGEX} ]] && err=2	# absolute must match REGEX
	else
		file="${UPLOADDIR:-NOUPLOADDIR}/${file}"	# others must be in UPLOADDIR
	fi
	[ ! -r "${file}" ] && err=3	# and file must exits of course
	# file path error, generate error response
	if [ -n "${err}" ]; then
	    BOTSENT=(); BOTSENT[OK]="false"
	    case "${err}" in
		1) BOTSENT[ERROR]="Path to file $2 contains to much '../' or starts with '.'";;
		2) BOTSENT[ERROR]="Path to file $2 does not match regex: ${FILE_REGEX} ";;
		3) if [[ "$2" == "/"* ]];then
			BOTSENT[ERROR]="File not found: $2"
		   else
			BOTSENT[ERROR]="File not found: ${UPLOADDIR}/$2"
		   fi;;
	    esac
	    [ -n "${BASHBOTDEBUG}" ] && log_debug "$3: CHAT=$1 FILE=$2 MSG=${BOTSENT[DESCRIPTION]}"
	    return 1
	fi
	printf "%s\n" "${file}"
}


#
# curl / wget specific functions
#
if detect_curl ; then
  # here we have curl ----
  [ -z "${BASHBOT_CURL}" ] && BASHBOT_CURL="curl"
  # $1 URL, $2 hack: log getJson if not ""
  getJson(){
	# shellcheck disable=SC2086
	"${BASHBOT_CURL}" -sL -k ${BASHBOT_CURL_ARGS} -m "${TIMEOUT}" "$1"
  }
  # curl variant for sendJson
  # usage: "JSON" "URL"
  sendJson_do(){
	# shellcheck disable=SC2086
	"${BASHBOT_CURL}" -s -k ${BASHBOT_CURL_ARGS} -m "${TIMEOUT}"\
		-d "$1" -X POST "$2" -H "Content-Type: application/json" | "${JSONSHFILE}" -b -n 2>/dev/null
  }
  #$1 Chat, $2 what, $3 file, $4 URL, $5 caption
  sendUpload() {
	[ "$#" -lt 4  ] && return
	if [ -n "$5" ]; then
		[ -n "${BASHBOTDEBUG}" ] &&\
			log_update "sendUpload CHAT=$1 WHAT=$2  FILE=$3 CAPT=$5"
		# shellcheck disable=SC2086
		res="$("${BASHBOT_CURL}" -s -k ${BASHBOT_CURL_ARGS} "$4" -F "chat_id=$1"\
			-F "$2=@$3;${3##*/}" -F "caption=$5" | "${JSONSHFILE}" -b -n 2>/dev/null )"
	else
		# shellcheck disable=SC2086
		res="$("${BASHBOT_CURL}" -s -k ${BASHBOT_CURL_ARGS} "$4" -F "chat_id=$1"\
			-F "$2=@$3;${3##*/}" | "${JSONSHFILE}" -b -n 2>/dev/null )"
	fi
	sendJsonResult "${res}" "sendUpload (curl)" "$@"
	[ -n "${BASHBOT_EVENT_SEND[*]}" ] && event_send "upload" "$@" &
  }
else
  # NO curl, try wget
  if _exists wget; then
    getJson(){
	# shellcheck disable=SC2086
	wget --no-check-certificate -t 2 -T "${TIMEOUT}" ${BASHBOT_WGET_ARGS} -qO - "$1"
    }
    # curl variant for sendJson
    # usage: "JSON" "URL"
    sendJson_do(){
	# shellcheck disable=SC2086
	wget --no-check-certificate -t 2 -T "${TIMEOUT}" ${BASHBOT_WGET_ARGS} -qO - --post-data="$1" \
		--header='Content-Type:application/json' "$2" | "${JSONSHFILE}" -b -n 2>/dev/null
    }
    sendUpload() {
	log_error "Sorry, wget does not support file upload"
	BOTSENT[OK]="false"
	[ -n "${BASHBOT_EVENT_SEND[*]}" ] && event_send "upload" "$@" &
    }
  else
	# ups, no curl AND no wget
	if [ -n "${BASHBOT_WGET}" ]; then
		printf "${RED}Error: You set BASHBOT_WGET but no wget found!${NN}"
	else
		printf "${RED}Error: curl and wget not found, install curl!${NN}"
	fi
	exit_source 8
  fi
fi 

# retry sendJson
# $1 function $2 sleep $3 ... $n arguments
sendJsonRetry(){
	local retry="$1"; shift
	[[ "$1" =~ ^\ *[${o9o9o9}.]+\ *$ ]] && sleep "$1"; shift
	printf "%(%c)T: RETRY %s %s %s\n" -1 "${retry}" "$1" "${2:0:60}"
	case "${retry}" in
		'sendJson'*)
			sendJson "$@"	
			;;
		'sendUpload'*)
			sendUpload "$@"	
			;;
		'send_album'*)
			send_album "$@"	
			;;
		*)
			log_error "Error: unknown function ${retry}, cannot retry"
			return
			;;
	esac
	[ "${BOTSENT[OK]}" = "true" ] && log_error "Retry OK:${retry} $1 ${2:0:60}"
} >>"${ERRORLOG}"

# process sendJson result
# stdout is written to ERROR.log
# $1 result $2 function $3 .. $n original arguments, $3 is Chat_id
sendJsonResult(){
	local offset=0
	BOTSENT=( )
	Json2Array 'UPD' <<<"$1"
	[ -n "${BASHBOTDEBUG}" ] && log_message "New Result ==========\n$1"
	BOTSENT[OK]="${UPD["ok"]}"
	if [ "${BOTSENT[OK]}" = "true" ]; then
		BOTSENT[ID]="${UPD["result,message_id"]}"
		BOTSENT[CHAT]="${UPD["result,chat,id"]}"
		[ -n "${UPD["result"]}" ] && BOTSENT[RESULT]="${UPD["result"]}"
		return
		# hot path everything OK!
	else
	    # oops something went wrong!
	    if [ -n "$1" ]; then
			BOTSENT[ERROR]="${UPD["error_code"]}"
			BOTSENT[DESCRIPTION]="${UPD["description"]}"
			[ -n "${UPD["parameters,retry_after"]}" ] && BOTSENT[RETRY]="${UPD["parameters,retry_after"]}"
	    else
			BOTSENT[OK]="false"
			BOTSENT[ERROR]="999"
			BOTSENT[DESCRIPTION]="Send to telegram not possible, timeout/broken/no connection"
	    fi
	    # log error
	    [[ "${BOTSENT[ERROR]}" = "400" && "${BOTSENT[DESCRIPTION]}" == *"starting at byte offset"* ]] &&\
			 offset="${BOTSENT[DESCRIPTION]%* }"
	    printf "%(%c)T: RESULT=%s FUNC=%s CHAT[ID]=%s ERROR=%s DESC=%s ACTION=%s\n" -1\
			"${BOTSENT[OK]}"  "$2" "$3" "${BOTSENT[ERROR]}" "${BOTSENT[DESCRIPTION]}" "${4:${offset}:100}"
	    # warm path, do not retry on error, also if we use wegt
	    [ -n "${BASHBOT_RETRY}${BASHBOT_WGET}" ] && return

	    # OK, we can retry sendJson, let's see what's failed
	    # throttled, telegram say we send too many messages
	    if [ -n "${BOTSENT[RETRY]}" ]; then
			BASHBOT_RETRY="$(( ++BOTSENT[RETRY] ))"
			printf "Retry %s in %s seconds ...\n" "$2" "${BASHBOT_RETRY}"
			sendJsonRetry "$2" "${BASHBOT_RETRY}" "${@:3}"
			unset BASHBOT_RETRY
			return
	    fi
	    # timeout, failed connection or blocked
	    if [ "${BOTSENT[ERROR]}" == "999" ];then
		# check if default curl and args are OK
		if ! curl -sL -k -m 2 "${URL}" >/dev/null 2>&1 ; then
			printf "%(%c)T: BASHBOT IP Address seems blocked!\n" -1
			# user provided function to recover or notify block
			if _exec_if_function bashbotBlockRecover; then
				BASHBOT_RETRY="2"
				printf "bashbotBlockRecover returned true, retry %s ...\n" "$2"
				sendJsonRetry "$2" "${BASHBOT_RETRY}" "${@:3}"
				unset BASHBOT_RETRY
			fi
	       # seems not blocked, try if blockrecover and default curl args working
		elif [ -n "${BASHBOT_CURL_ARGS}" ] || [ "${BASHBOT_CURL}" != "curl" ]; then
			printf "Problem with \"%s %s\"? retry %s with default config ...\n"\
				"${BASHBOT_CURL}" "${BASHBOT_CURL_ARGS}" "$2"
			BASHBOT_RETRY="2"; BASHBOT_CURL="curl"; BASHBOT_CURL_ARGS=""
			_exec_if_function bashbotBlockRecover
			sendJsonRetry "$2" "${BASHBOT_RETRY}" "${@:3}"
			unset BASHBOT_RETRY
		fi
		[ -n "${BOTSENT[ERROR]}" ] && processError "$3" "${BOTSENT[ERROR]}" "$4" "" "${BOTSENT[DESCRIPTION]}" "$5" "$6"
	    fi
	fi
} >>"${ERRORLOG}"

# convert common telegram entities to JSON
# title caption description markup inlinekeyboard
title2Json(){
	local title caption desc markup keyboard
	[ -n "$1" ] && title=',"title":"'$(JsonEscape "$1")'"'
	[ -n "$2" ] && caption=',"caption":"'$(JsonEscape "$2")'"'
	[ -n "$3" ] && desc=',"description":"'$(JsonEscape "$3")'"'
	[ -n "$4" ] && markup=',"parse_mode":"'"$4"'"'
	[ -n "$5" ] && keyboard=',"reply_markup":"'$(JsonEscape "$5")'"'
	printf '%s\n' "${title}${caption}${desc}${markup}${keyboard}"
}

# get bot name and id from telegram
getBotName() {
	declare -A BOTARRAY
	Json2Array 'BOTARRAY' <<<"$(getJson "${ME_URL}" | "${JSONSHFILE}" -b -n 2>/dev/null)"
	[ -z "${BOTARRAY["result","username"]}" ] && return 1
	# save botname and id
	setConfigKey "botname" "${BOTARRAY["result","username"]}"
	setConfigKey "botid" "${BOTARRAY["result","id"]}"
	printf "${BOTARRAY["result","username"]}\n"
}

# pure bash implementation, done by KayM (@gnadelwartz)
# see https://stackoverflow.com/a/55666449/9381171
JsonDecode() {
	local remain U out="$1"
	local regexp='(.*)\\u[dD]([0-9a-fA-F]{3})\\u[dD]([0-9a-fA-F]{3})(.*)'
	while [[ "${out}" =~ ${regexp} ]] ; do
	U=$(( ( (0xd${BASH_REMATCH[2]} & 0x3ff) <<10 ) | ( 0xd${BASH_REMATCH[3]} & 0x3ff ) + 0x10000 ))
			remain="$(printf '\\U%8.8x' "${U}")${BASH_REMATCH[4]}${remain}"
			out="${BASH_REMATCH[1]}"
	done
	printf "%b\n" "${out}${remain}"
}


EVENT_SEND="0"
declare -Ax BASHBOT_EVENT_SEND
event_send() {
	# max recursion level 5 to avoid fork bombs
	(( EVENT_SEND++ )); [ "${EVENT_SEND}" -gt "5" ] && return
	# shellcheck disable=SC2153
	for key in "${!BASHBOT_EVENT_SEND[@]}"
	do
		_exec_if_function "${BASHBOT_EVENT_SEND[${key}]}" "$@"
	done
}

# cleanup activities on startup, called from startbot and resume background jobs
# $1 action, timestamp for action is saved in config
bot_cleanup() {
	# cleanup countfile on startup
	jssh_deleteKeyDB "CLEAN_COUNTER_DATABASE_ON_STARTUP" "${COUNTFILE}"
        [ -f "${COUNTFILE}.jssh.flock" ] && rm -f "${COUNTFILE}.jssh.flock"
	# store action time and cleanup botconfig on startup
	[ -n "$1" ] && jssh_updateKeyDB "$1" "$(_date)" "${BOTCONFIG}"
        [ -f "${BOTCONFIG}.jssh.flock" ] && rm -f "${BOTCONFIG}.jssh.flock"
}

# fallback version, full version is in  bin/bashbot_init.in.sh
# initialize bot environment, user and permissions
bot_init() {
	if [ -n "${BASHBOT_HOME}" ] && ! cd "${BASHBOT_HOME}"; then
		 printf "Can't change to BASHBOT_HOME"
		 exit 1
	fi
	# initialize addons
	printf "Initialize addons ...\n"
	for addons in "${ADDONDIR:-.}"/*.sh ; do
		# shellcheck source=./modules/aliases.sh
		[ -r "${addons}" ] && source "${addons}" "init" "$1"
	done
	printf "Done.\n"
	# adjust permissions
	printf "Adjusting files and permissions ...\n"
	chmod 711 .
	chmod -R o-w ./*
	chmod -R u+w "${COUNTFILE}"* "${BLOCKEDFILE}"* "${DATADIR}" logs "${LOGDIR}/"*.log 2>/dev/null
	chmod -R o-r,o-w "${COUNTFILE}"* "${BLOCKEDFILE}"* "${DATADIR}" "${BOTACL}" 2>/dev/null
	# jsshDB must writeable by owner
	find . -name '*.jssh*' -exec chmod u+w \{\} +
	printf "Done.\n"
	_exec_if_function my_init
}

if ! _is_function send_message ; then
	printf "${RED}ERROR: send_message is not available, did you deactivate ${MODULEDIR}/sendMessage.sh?${NN}"
	exit_source 1
fi

# check if JSON.awk exist and has x flag
JSONAWKFILE="${JSONSHFILE%.sh}.awk"
if [ -x "${JSONAWKFILE}" ] && _exists awk ; then
	JSONSHFILE="JsonAwk"; JsonAwk() { "${JSONAWKFILE}" -v "BRIEF=8" -v "STRICT=0" -; }
fi

# source the script with source as param to use functions in other scripts
# do not execute if read from other scripts

BOTADMIN="$(getConfigKey "botadmin")"

if [ -z "${SOURCE}" ]; then
  ##############
  # internal options only for use from bashbot and developers
  # shellcheck disable=SC2221,SC2222
  case "$1" in
	# update botname when starting only
	"botname"|"start"*)
		ME="$(getBotName)"
		if [ -n "${ME}" ]; then
			# ok we have a connection and got botname, save it
			[ -n "${INTERACTIVE}" ] && printf "${GREY}Bottoken is valid ...${NN}"
			jssh_updateKeyDB "botname" "${ME}" "${BOTCONFIG}"
			rm -f "${BOTCONFIG}.jssh.flock"
		else
			printf "${GREY}Info: Can't get Botname from Telegram, try cached one ...${NN}"
			ME="$(getConfigKey "botname")"
			if [ -z "${ME}" ]; then
			    printf "${RED}ERROR: No cached botname, can't continue! ...${NN}"
			    exit 1
			fi
		fi
		[ -n "${INTERACTIVE}" ] && printf "Bot Name: %s\n" "${ME}"
		[ "$1" = "botname" ] && exit
		;;&
	# used to send output of background and interactive to chats
	"outproc")	# $2 chat_id $3 identifier of job, internal use only!
		[ -z "$3" ] && printf "No job identifier\n" && exit 3
		[ -z "$2"  ] && printf "No chat to send to\n" && exit 3
		ME="$(getConfigKey "botname")"
		# read until terminated
		while read -r line ;do
			[ -n "${line}" ] && send_message "$2" "${line}"
		done 
		# cleanup datadir, keep logfile if not empty
		rm -f -r "${DATADIR:-.}/$3"
		[ -s "${DATADIR:-.}/$3.log" ] || rm -f "${DATADIR:-.}/$3.log"
		debug_checks "end outproc" "$@"
		exit
		;;
	# finally starts the read update loop, internal use only
	"startbot" )
		_exec_if_function start_bot "$2" "polling mode"
		_exec_if_function get_updates "$2"
		debug_checks "end startbot" "$@"
		exit
		;;
	# run after every update to update files and adjust permissions
	"init") 
		# shellcheck source=./bin/bashbot._init.inc.sh"
		[ -r "${BASHBOT_HOME:-.}/bin/bashbot_init.inc.sh" ] && source "${BASHBOT_HOME:-.}/bin/bashbot_init.inc.sh"
		bot_init "$2"
		debug_checks "end init" "$@"
		exit
		;;
	# stats deprecated
	"stats"|"count")
		printf "${ORANGE}Stats is a separate command now, see bin/bashbot_stats.sh --help${NN}"
		"${BASHBOT_HOME:-.}"/bin/bashbot_stats.sh --help
		exit
		;;
	# broadcast deprecated
	'broadcast')
		printf "${ORANGE}Broadcast is a separate command now, see bin/send_broadcast.sh --help${NN}"
		"${BASHBOT_HOME:-.}"/bin/send_broadcast.sh --help
		exit
		;;
	# does what it says
	"status")
		ME="$(getConfigKey "botname")"
		SESSION="${ME:-_bot}-startbot"
		BOTPID="$(proclist "${SESSION}")"
		if [ -n "${BOTPID}" ]; then
			printf "${GREEN}Bot is running with UID ${RUNUSER}.${NN}"
			exit
		else
			printf "${ORANGE}No Bot running with UID ${RUNUSER}.${NN}"
			exit 5
		fi
		debug_checks "end status" "$@"
		;;
		 
	# start bot as background job and check if bot is running
	"start")
		SESSION="${ME:-_bot}-startbot"
		BOTPID="$(proclist "${SESSION}")"
		if _is_function process_update; then 
			# shellcheck disable=SC2086
			[ -n "${BOTPID}" ] && kill ${BOTPID} && printf "${GREY}Stop already running bot ...${NN}"
			nohup "${SCRIPT}" "startbot" "$2" "${SESSION}" &>/dev/null &
			printf "Session Name: %s\n" "${SESSION}"
			sleep 1
		else
			printf "${ORANGE}Update processing disabled, bot can only send messages.${NN}"
			[ -n "${BOTPID}" ] && printf "${ORANGE}Already running bot found ...${NN}"
		fi
		if [ -n "$(proclist "${SESSION}")" ]; then
		 	printf "${GREEN}Bot started successfully.${NN}"
		else
			printf "${RED}An error occurred while starting the bot.${NN}"
			exit 5
		fi
		debug_checks "end start" "$@"
		;;
	# does what it says
	"stop")
		ME="$(getConfigKey "botname")"
		SESSION="${ME:-_bot}-startbot"
		BOTPID="$(proclist "${SESSION}")"
		if [ -n "${BOTPID}" ]; then
			# shellcheck disable=SC2086
			if kill ${BOTPID}; then
				# inform botadmin about stop
				send_normal_message "${BOTADMIN}" "Bot ${ME} polling mode stopped ..." &
				printf "${GREEN}OK. Bot stopped successfully.${NN}"
			else
				printf "${RED}An error occurred while stopping bot.${NN}"
				exit 5
			fi
		else
			printf "${ORANGE}No Bot running with UID ${RUNUSER}.${NN}"
		fi
		debug_checks "end stop" "$@"
		exit
		;;
	# suspend, resume or kill background jobs
	"suspendb"*|"resumeb"*|'restartb'*|"killb"*)
  		_is_function job_control || { printf "${RED}Module background is not available!${NN}"; exit 3; }
		ME="$(getConfigKey "botname")"
		job_control "$1"
		debug_checks "end background $1" "$@"
		;;
	*)
		printf "${RED}${REALME##*/}: unknown command${NN}"
		printf "${ORANGE}Available commands: ${GREY}${BOTCOMMANDS}${NN}" && exit
		exit 4
		;;
  esac

  # warn if root
  if [[ "${UID}" -eq "0" ]] ; then
	printf "\n${ORANGE}WARNING: ${SCRIPT} was started as ROOT (UID 0)!${NN}"
	printf "${ORANGE}You are at HIGH RISK when running a Telegram BOT with root privileges!${NN}"
  fi
fi # end source
