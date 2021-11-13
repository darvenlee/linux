#!/bin/bash
# 安装前置检查
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh

if [[ $# -lt 5 ]];then
    logger_error "specify HOST_INFO NODE_SOFTWARE_DIR NODE_DATA_DIRS CHECK_SUDO CLUSTER_TYPE not valid!!"
    exit 1
fi
HOST_INFO="$1"
NODE_SOFTWARE_DIR="$2"
#将传入的路径按逗号分隔成路径数组
NODE_DATA_DIRS=(${3//,/ })
CHECK_SUDO="$4"
CLUSTER_TYPE="$5"

SOFTWARE_ROOT_DIR="`cd $curwkdir/../software; pwd`"
SOFTWARE_RUNTIME_ROOT_DIR="$SOFTWARE_ROOT_DIR/index-runtime"
ES_USER=$ENV_SYSTEMUSER
ES_GROUP=$ENV_SYSTEMGROUP
HOST_PASSWORD="$ENV_PASSWORD"
HOST_NODENAME=$ENV_NODENAME
JDK_PKG="$ENV_JDK"
if [[ "$ES_USER" == "" ]];then
    logger_info "not specify ES_USER param. use default `whoami`"
    ES_USER=`whoami`
    ES_GROUP=`whoami`
fi

SSHIP=`echo $HOST_INFO | awk -F "@" '{print $1}'`
SSHPORT=`echo $HOST_INFO | awk -F "@" '{print $2}'`

function checkSudoPermission()
{
ssh $ES_USER@${SSHIP} << eeooff
# 检查是否有sudo权限
sudo -n true
eeooff
    return $? 
}

function checkPathPermission()
{
    local checkPath=$1
ssh $ES_USER@${SSHIP} << eeooff
mkdir -p $checkPath
eeooff
    return $? 
}

function remoteAgentCheck()
{
for dir in ${NODE_DATA_DIRS[*]}
do
ssh $ES_USER@${SSHIP} << eeooff
chmod +x $NODE_SOFTWARE_DIR/shellscript/* 2>/dev/null
bash $NODE_SOFTWARE_DIR/shellscript/agentCheck.sh $NODE_SOFTWARE_DIR ${dir} $HOST_INFO 2>&1
eeooff
if [[ $? -ne 0 ]];then
     logger_error "remoteAgentCheck for $HOST_NODENAME on ${dir} of $HOST_INFO failed!!"
     return 1
fi
     logger_info "remoteAgentCheck for $HOST_NODENAME on ${dir} of $HOST_INFO success!!"
done
    return $?
}

function preInstallCheck()
{
    if [[ "$CHECK_SUDO" == "yes" ]];then
        checkSudoPermission
        if [ $? -ne 0 ];then
            logger_error "do not have sudo permission on ${SSHIP} with $ES_USER!!"
            return 1
        fi
    fi

    checkPathPermission $NODE_SOFTWARE_DIR
    if [ $? -ne 0 ];then
        logger_error "do not have write permission in $NODE_SOFTWARE_DIR on ${SSHIP} with $ES_USER!!"
        return 1
    fi

    checkPathPermission $NODE_SOFTWARE_DIR/pm2_monit
    if [ $? -ne 0 ];then
        logger_error "do not have write permission in $NODE_SOFTWARE_DIR/pm2_monit on ${SSHIP} with $ES_USER!!"
        return 1
    fi

    for dir in ${NODE_DATA_DIRS[*]}
    do
        checkPathPermission ${dir}
        if [ $? -ne 0 ];then
            logger_error "do not have write permission in ${dir} on ${SSHIP} with $ES_USER!!"
            return 1
        fi
    done
    return $?
}

function prepare_JDKPkg()
{
    if [ `ls $SOFTWARE_RUNTIME_ROOT_DIR/$JDK_PKG 2>/dev/null | wc -l` -ne 0 ];then
        # 拷贝jre到远程地址
        scp $SOFTWARE_RUNTIME_ROOT_DIR/$JDK_PKG ${ES_USER}@${SSHIP}:$NODE_SOFTWARE_DIR 1>/dev/null
        if [ $? -ne 0 ]; then
            logger_error "scp $JDK_PKG to ${SSHIP}:${HOST_NODENAME}failed"
            return 1
        fi
        logger_info "scp $JDK_PKG to ${SSHIP}:${HOST_NODENAME} successfully"
    else
        logger_error "please prepare jre $JDK_PKG in $SOFTWARE_RUNTIME_ROOT_DIR"
        return 1
    fi
}

function prepare_preInstallPkg()
{
    prepare_JDKPkg
    if [ $? -ne 0 ]; then
        return 1
    fi

    if [ `ls $SOFTWARE_ROOT_DIR/pm2_monit/* 2>/dev/null | wc -l` -ne 0 ];then
        # 拷贝jre到远程地址
        scp $SOFTWARE_ROOT_DIR/pm2_monit/* ${ES_USER}@${SSHIP}:$NODE_SOFTWARE_DIR/pm2_monit 1>/dev/null
        if [ $? -ne 0 ]; then
            logger_error "scp pm2_monit to ${SSHIP}:${HOST_NODENAME}failed"
            return 1
        fi
        logger_info "scp pm2_monit to ${SSHIP}:${HOST_NODENAME} successfully"
    fi
}

function main()
{
    # 由于免密登录首次会询问yes/no需要事先处理一下
    bash $curwkdir/preLoginCheck.sh $HOST_INFO
    if [ $? -ne 0 ];then
        logger_error "loggin on ${SSHIP} with $ES_USER failed!!"
        return 1
    fi

    preInstallCheck
    if [ $? -ne 0 ];then
        logger_error "preInstallCheck for $HOST_NODENAME on $HOST_INFO failed!!"
        return 1
    fi

    bash $curwkdir/prepareAgent.sh  $NODE_SOFTWARE_DIR  $HOST_INFO  prepare $CLUSTER_TYPE
    if [ $? -ne 0 ]; then
        logger_error "prepareAgent.sh for $HOST_NODENAME on $HOST_INFO in $NODE_SOFTWARE_DIR  failed!!"
        return 1
    fi

    remoteAgentCheck
    if [ $? -ne 0 ];then
        logger_error "remoteAgentCheck for $HOST_NODENAME on $HOST_INFO failed!!"
        return 1
    fi

    prepare_preInstallPkg
    if [ $? -ne 0 ];then
        logger_error "prepare_preInstallPkg for $HOST_NODENAME on $HOST_INFO failed!!"
        return 1
    fi

    logger_info "preInstallCheck for $HOST_NODENAME on $HOST_INFO ok"
}
main "$@"
