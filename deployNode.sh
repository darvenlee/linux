#!/bin/bash
# 1. 远程登陆对应节点,然后远程执行action
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 5 ]];then
    logger_error "specify ES_PKG_NAME SOFTWARE_DIR INST_ES_INSTALL_DIR HOST_INFO and ACTION_NAME not valid!!"
    exit 1
fi
ES_PKG_NAME="$1"
INST_SOFTWARE_DIR="$2"
INST_ES_INSTALL_DIR="$3"
#将传入的路径按逗号分隔成路径数组
INST_ES_DATA_DIRS=(${4//,/ })
HOST_INFO="$5"
ACTION_NAME="$6"
MODULE="$7"
NODE_TYPE="$8"
MULTI_NODE_SOFT_LINK_MODE="$9"
INSTANCE_NUMBER="${10}"

ES_USER=$ENV_SYSTEMUSER
ES_GROUP=$ENV_SYSTEMGROUP
HOST_PASSWORD="$ENV_PASSWORD"
HOST_NODENAME=$ENV_NODENAME
DEBUG_FLAG=$ENV_ISDEBUG
JDK_PKG="$ENV_JDK"
ENV_LOGS_PATH="$ENV_LOGS_PATH"
if [[ "$ES_USER" == "" ]];then
    logger_fatal "invalid ES_USER param. please specify ENV_SYSTEMUSER"
    exit 1
fi
SSHIP=`echo $HOST_INFO | awk -F "@" '{print $1}'`
SSHPORT=`echo $HOST_INFO | awk -F "@" '{print $2}'`

function preRefreshAgent()
{
    agentName="agentPkg.tar.gz"
ssh $ES_USER@${SSHIP} << eeooff
chmod 750 $INST_SOFTWARE_DIR/shellscript/* 2>/dev/null
tar -zxf $INST_SOFTWARE_DIR/$agentName -C $INST_SOFTWARE_DIR
eeooff
    return $?
}

function doAction_es()
{
    if [ "$ACTION_NAME" == "refresh" ];then
        preRefreshAgent
        if [ $? -ne 0 ];then
            logger_error "pre refresh agent pkg for $HOST_NODENAME on $HOST_INFO failed."
            return 1
        fi
        logger_info "pre refresh agent pkg for $HOST_NODENAME on $HOST_INFO ok."
    fi

for dir in ${INST_ES_DATA_DIRS[*]}
do
ssh $ES_USER@${SSHIP} << eeooff
chmod 500 $INST_SOFTWARE_DIR/shellscript/* 2>/dev/null
bash $INST_SOFTWARE_DIR/shellscript/agentAction.sh $INST_ES_INSTALL_DIR $dir $HOST_NODENAME $ES_PKG_NAME $ACTION_NAME $DEBUG_FLAG $JDK_PKG $MODULE $NODE_TYPE $ENV_LOGS_PATH $MULTI_NODE_SOFT_LINK_MODE $INSTANCE_NUMBER 2>&1 1>/dev/null
eeooff
 if [[ $? -ne 0 ]];then
      logger_error "do action $ACTION_NAME for $HOST_NODENAME on $dir of $HOST_INFO failed!!"
      return 1
 fi
      logger_info "do action $ACTION_NAME for $HOST_NODENAME on $dir of $HOST_INFO success!!"
done

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

    doAction_es
    if [ $? -ne 0 ];then
        logger_error "do action $ACTION_NAME for $HOST_NODENAME on $HOST_INFO failed!!"
        exit 1
    fi
}
main "$@"

