#!/bin/bash
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 3 ]];then
    logger_error "specify INST_MODULES_LOG_DIR HOST_INFO and ACTION_NAME not valid!!"
    exit 1
fi

INST_MODULES_LOG_DIR="$1"
HOST_INFO="$2"
ACTION_NAME="$3"

ES_USER=`whoami`
ES_GROUP=`whoami`
HOST_PASSWORD="$ENV_PASSWORD"
HOST_NODENAME="$ENV_NODENAME"

HOST_FICLIENTIP="$ENV_FICLIENTIP"
HOST_FICLIENTWKDIR="$ENV_FICLIENTWKDIR"
HOST_NGINXIP="$ENV_NGINXIP"
HOST_NGINXWKDIR="$ENV_NGINXWKDIR"
if [[ "$HOST_FICLIENTIP" == "" ]];then
    logger_error "specify ENV_FICLIENTIP not valid!!"
    exit 1
fi

SSHIP=`echo $HOST_INFO | awk -F "@" '{print $1}'`
SSHPORT=`echo $HOST_INFO | awk -F "@" '{print $2}'`

LOGDIR_PREFIX="slowlog"
REMOTE_COLLECTLOG="${LOGDIR_PREFIX}_${HOST_NODENAME}"

# 每小时目录
TIMESTMP=$(date '+%Y-%m-%d-%H')
BASE_COLLECTDIR="`mkdir -p $curwkdir/../collect; cd $curwkdir/../collect; pwd`"
LOG_COLLECTDIR="$BASE_COLLECTDIR/$TIMESTMP"
COLLECT_LOCK_FLAG="$BASE_COLLECTDIR/$TIMESTMP/collect.lock"
ES_COLLECTDIR="$LOG_COLLECTDIR"
NGINX_COLLECTDIR="$LOG_COLLECTDIR"

function package_remote_eslogs()
{
ssh $ES_USER@${SSHIP} << eeooff
mkdir -p $INST_MODULES_LOG_DIR/$REMOTE_COLLECTLOG
rm -f $INST_MODULES_LOG_DIR/$REMOTE_COLLECTLOG/* 2>/dev/null
mv $INST_MODULES_LOG_DIR/*slowlog.json $INST_MODULES_LOG_DIR/${REMOTE_COLLECTLOG} 2>/dev/null
mv $INST_MODULES_LOG_DIR/*slowlog.log $INST_MODULES_LOG_DIR/${REMOTE_COLLECTLOG} 2>/dev/null
echo "es:${HOST_NODENAME}">> $INST_MODULES_LOG_DIR/${REMOTE_COLLECTLOG}/log.list
cd $INST_MODULES_LOG_DIR
rm -f $INST_MODULES_LOG_DIR/${REMOTE_COLLECTLOG}.zip 2>/dev/null
# 压缩时清理原目录
zip -q -r -m $INST_MODULES_LOG_DIR/${REMOTE_COLLECTLOG}.zip ${REMOTE_COLLECTLOG}
eeooff
    return $?
}

function collect_eslogs()
{
    package_remote_eslogs
    if [ $? -ne 0 ];then
        logger_error "package_remote_eslogs of $HOST_NODENAME on $HOST_INFO failed!!"
        return 1
    fi

    mkdir -p $ES_COLLECTDIR
    scp ${ES_USER}@${SSHIP}:$INST_MODULES_LOG_DIR/${REMOTE_COLLECTLOG}.zip $ES_COLLECTDIR 1>/dev/null
    if [ $? -ne 0 ]; then
        logger_error "scp ${ES_COLLECTDIR}.zip from remote ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi
    logger_info "scp ${ES_COLLECTDIR}.zip from remote ${SSHIP}:${HOST_NODENAME} successfully"
}

function collect_nginxlogs()
{
    exec 9<>$COLLECT_LOCK_FLAG
    flock -n 9
    if [ $? -ne 0 ]; then
        return 0
    fi

    mkdir -p $NGINX_COLLECTDIR
    NGINX_REMOTE_LOGDIR="$HOST_NGINXWKDIR/logs"

ssh $ES_USER@$HOST_NGINXIP << eeooff
mkdir -p $NGINX_REMOTE_LOGDIR/$LOGDIR_PREFIX
rm -f $NGINX_REMOTE_LOGDIR/$LOGDIR_PREFIX/* 2>/dev/null
cp $NGINX_REMOTE_LOGDIR/*.log $NGINX_REMOTE_LOGDIR/$LOGDIR_PREFIX 2>/dev/null
echo "" > $NGINX_REMOTE_LOGDIR/access.log
echo "" > $NGINX_REMOTE_LOGDIR/error.log
echo "nginx:${HOST_NGINXIP}">> $NGINX_REMOTE_LOGDIR/$LOGDIR_PREFIX/log.list
cd $NGINX_REMOTE_LOGDIR
rm $NGINX_REMOTE_LOGDIR/${LOGDIR_PREFIX}.zip 2>/dev/null
# 压缩时清理原目录
zip -q -r -m $NGINX_REMOTE_LOGDIR/${LOGDIR_PREFIX}.zip $LOGDIR_PREFIX
eeooff
    if [ $? -ne 0 ];then
        logger_error "package_remote_nginxlogs of $HOST_NODENAME on $HOST_INFO failed!!"
        return 1
    fi

    scp ${ES_USER}@$HOST_NGINXIP:$NGINX_REMOTE_LOGDIR/${LOGDIR_PREFIX}.zip $NGINX_COLLECTDIR 1>/dev/null
    if [ $? -ne 0 ]; then
        logger_error "scp ${LOGDIR_PREFIX}.zip from remote nginx $HOST_NGINXIP failed"
        return 1
    fi

    rm -f $COLLECT_LOCK_FLAG 2>/dev/null
    logger_info "scp ${LOGDIR_PREFIX}.zip from remote nginx $HOST_NGINXIP successfully"
}


function main()
{
    collect_eslogs
    if [ $? -ne 0 ];then
        logger_error "collect eslogs failed"
        exit 1
    fi

    collect_nginxlogs
    if [ $? -ne 0 ];then
        logger_error "collect nginx logs failed"
        exit 1
    fi
}
main "$@"
