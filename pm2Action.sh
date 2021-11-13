#!/bin/bash
# start/stop/restart
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 3 ]];then
    logger_error "specify ACTION_NAME InstBinDir AppName ES_PKG_NAME PARALIST not valid!!"
    exit 1
fi

ACTION_NAME="$1"
InstBinDir="$2"
AppName="$3"
PARALIST="$4"

baselogdir=`cd $curwkdir/../log; pwd`
logdir="$baselogdir/pm2log"
mkdir -p $logdir

function pm2_start()
{
    pm2 start $InstBinDir/$AppName --name "$InstBinDir/$AppName" -l "$logdir/${AppName}.log" --watch $InstBinDir -- "${PARALIST}"
}

function pm2_stop()
{
    pm2 stop $InstBinDir/$AppName
}

function pm2_delete()
{
    pm2 delete $InstBinDir/$AppName
}

function pm2_restart()
{
    pm2 restart $InstBinDir/$AppName
}


function main()
{
    logger_info "begin to ${ACTION_NAME} by pm2 for $AppName...."
    if [ "$ACTION_NAME" == "start" ];then
        pm2_start
        ret=$?
    elif [ "$ACTION_NAME" == "stop" ];then
        pm2_stop
        ret=$?
    elif [ "$ACTION_NAME" == "uninstall" ];then
        pm2_delete
        ret=$?
    elif [ "$ACTION_NAME" == "restart" ];then
        pm2_restart
        ret=$?
    else
        logger_info "${ACTION_NAME} not supported...."
    fi
    logger_info "end to ${ACTION_NAME} by pm2 for $AppName...."
    return $ret

}
main
