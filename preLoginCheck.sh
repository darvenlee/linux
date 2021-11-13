#!/bin/bash
# 安装前置检查
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh

if [[ $# -lt 1 ]];then
    logger_error "specify HOST_INFO not valid!!"
    exit 1
fi
HOST_INFO="$1"

ES_USER=$ENV_SYSTEMUSER
ES_GROUP=$ENV_SYSTEMGROUP
HOST_PASSWORD="$ENV_PASSWORD"
if [[ "$ES_USER" == "" ]];then
    logger_info "not specify ES_USER param. use default `whoami`"
    ES_USER=`whoami`
    ES_GROUP=`whoami`
fi

SSHIP=`echo $HOST_INFO | awk -F "@" '{print $1}'`
SSHPORT=`echo $HOST_INFO | awk -F "@" '{print $2}'`

function preLoginCheck()
{
/usr/bin/expect << LOGINEOF
set timeout 5
spawn ssh $ES_USER@${SSHIP}
expect {
    "*(yes/no)?"
    {
        send "yes\r"
        expect "*assword:" {send "${HOST_PASSWORD}\r"}
    }
    "*assword:"
    {
        send "${HOST_PASSWORD}\r"
    }
    "*]$*"
    {
        send "exit\r"
    }
}
LOGINEOF
}
preLoginCheck
