#!/bin/bash
# 1. 远程登陆对应节点,然后远程执行action
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 4 ]];then
    logger_error "specify SOFTWARE_DIR INSTALL_DIRHOST_INFO and ACTION_NAME not valid!!"
    exit 1
fi

INST_SOFTWARE_DIR="$1"
INST_MODULES_INSTALL_DIR="$2"
HOST_INFO="$3"
ACTION_NAME="$4"

ES_USER=$ENV_SYSTEMUSER
ES_GROUP=$ENV_SYSTEMGROUP
HOST_PASSWORD="$ENV_PASSWORD"
HOST_NODENAME=$ENV_NODENAME
MODULE_SPCIFY="$ENV_SPCIFYMODULES"
JDK_PKG="$ENV_JDK"
if [[ "$ES_USER" == "" ]];then
    logger_info "not specify ES_USER param. use default `whoami`"
    ES_USER=`whoami`
    ES_GROUP=`whoami`
fi
SSHIP=`echo $HOST_INFO | awk -F "@" '{print $1}'`
SSHPORT=`echo $HOST_INFO | awk -F "@" '{print $2}'`

function preRefreshAgent()
{
    agentName="agentPkg.tar.gz"
ssh $ES_USER@${SSHIP} << eeooff
chmod 700 $INST_SOFTWARE_DIR/shellscript/* 2>/dev/null
tar -zxf $INST_SOFTWARE_DIR/$agentName -C $INST_SOFTWARE_DIR
eeooff
    return $?
}

function doAction_modules()
{
    if [ "$ACTION_NAME" == "refresh" ];then
        preRefreshAgent
        if [ $? -ne 0 ];then
            logger_error "pre refresh agent pkg for $HOST_NODENAME on $HOST_INFO failed."
            return 1
        fi
        logger_info "pre refresh agent pkg for $HOST_NODENAME on $HOST_INFO ok."
    fi
    
ssh $ES_USER@${SSHIP} << eeooff
chmod 500 $INST_SOFTWARE_DIR/shellscript/* 2>/dev/null
bash $INST_SOFTWARE_DIR/shellscript/agentCtlModules.sh $INST_MODULES_INSTALL_DIR  ${ACTION_NAME} $MODULE_SPCIFY $JDK_PKG 2>&1 1>/dev/null
eeooff
    return $?
}

function main()
{
    # 由于免密登录首次会询问yes/no需要事先处理一下
    bash $curwkdir/preLoginCheck.sh $HOST_INFO
    if [ $? -ne 0 ];then
        logger_error "loggin on ${SSHIP} with $ES_USER failed!!"
        return 1
    fi

    doAction_modules
    if [ $? -ne 0 ];then
        logger_error "do action $ACTION_NAME for $HOST_NODENAME on $HOST_INFO failed!!"
        exit 1
    fi
}
main "$@"

