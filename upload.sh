#!/bin/bash
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 1 ]];then
    logger_error "specify CLUSTERNAME not valid!!"
    exit 1
fi
CLUSTERNAME="$1"

HOST_FICLIENTIP="$ENV_FICLIENTIP"
HOST_FICLIENTWKDIR="$ENV_FICLIENTWKDIR"
if [[ "$HOST_FICLIENTIP" == "" ]];then
    logger_error "specify ENV_FICLIENTIP not valid!!"
    exit 1
fi

ES_USER=`whoami`
ES_GROUP=`whoami`
# 每小时目录
TIMESTMP=$(date '+%Y-%m-%d-%H')

BASE_COLLECTDIR="`mkdir -p $curwkdir/../collect; cd $curwkdir/../collect; pwd`"
FICLIENT_COLLECTDIR="$HOST_FICLIENTWKDIR/collect"

function ctl_remote_hdfs()
{
ssh $ES_USER@${HOST_FICLIENTIP} << eeooff
    bash $FICLIENT_COLLECTDIR/agent/shellscript/agentFiclient.sh "$CLUSTERNAME" "$HOST_FICLIENTWKDIR" "$TIMESTMP"
eeooff
    return $?
}

function prepare_ficlient()
{

ssh $ES_USER@${HOST_FICLIENTIP} << eeooff
mkdir -p $FICLIENT_COLLECTDIR/agent/shellscript
chmod -Rf 750 $FICLIENT_COLLECTDIR/agent/shellscript
eeooff
    if [ $? -ne 0 ];then
        logger_error "prepare agent dir on ficlient ${HOST_FICLIENTIP} failed!!"
        return 1
    fi

    scp $curwkdir/*.sh $ES_USER@${HOST_FICLIENTIP}:$FICLIENT_COLLECTDIR/agent/shellscript 1>/dev/null
    if [ $? -ne 0 ];then
        logger_error "prepare agent shellscript on ficlient ${HOST_FICLIENTIP} failed!!"
        return 1
    fi
    logger_info "prepare agent on ficlient ${HOST_FICLIENTIP} successfully"
}

function send_package2FIclient()
{
    cd $BASE_COLLECTDIR
    rm -f ${TIMESTMP}.tar.gz 2>/dev/null
    tar -zcf ${TIMESTMP}.tar.gz $TIMESTMP
    if [ $? -ne 0 ];then
        logger_error "pack ${TIMESTMP}.tar.gz in $BASE_COLLECTDIR failed"
        return 1
    fi

    scp ${TIMESTMP}.tar.gz $ES_USER@${HOST_FICLIENTIP}:$FICLIENT_COLLECTDIR 1>/dev/null
    if [ $? -ne 0 ];then
        logger_error "scp ${TIMESTMP}.tar.gz to remote $FICLIENT_COLLECTDIR of ${HOST_FICLIENTIP} failed"
        return 1
    fi

    rm -rf $BASE_COLLECTDIR/$TIMESTMP
    logger_info "send packages to remote $FICLIENT_COLLECTDIR of ${HOST_FICLIENTIP} ok"
}

function main()
{
    prepare_ficlient
    if [ $? -ne 0 ];then
        return 1
    fi

    send_package2FIclient
    if [ $? -ne 0 ];then
        return 1
    fi

    ctl_remote_hdfs
    if [ $? -ne 0 ];then
        logger_error "upload packages on ${HOST_FICLIENTIP} failed"
        return 1
    fi
}
main "$@"
