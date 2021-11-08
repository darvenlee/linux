#!/bin/bash
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 5 ]];then
    logger_error "specify HOST_INFO TOPIC_NAME ZK_CLUSTER PARTITION_NUM KAFKA_CLIENT_DIR not valid!!"
    exit 1
fi

LOGIN_USER=$ENV_LOGIN_USER
HOST_PASSWORD="$ENV_PASSWORD"
if [[ "$LOGIN_USER" == "" ]];then
    logger_fatal "invalid LOGIN_USER param. please specify ENV_LOGIN_USER"
    exit 1
fi

HOST_INFO=$1
TOPIC_NAME=$2
ZK_CLUSTER=$3
PARTITION_NUM=$4
KAFKA_CLIENT_DIR=$5

SSHIP=`echo $HOST_INFO | awk -F "@" '{print $1}'`
SSHPORT=`echo $HOST_INFO | awk -F "@" '{print $2}'`
function create_topic()
{
ssh $LOGIN_USER@${SSHIP} << eeooff
cd $KAFKA_CLIENT_DIR
bin/kafka-topics.sh --zookeeper ${ZK_CLUSTER}/kafka --create --topic ${TOPIC_NAME} --partitions $PARTITION_NUM --replication-factor 1
eeooff
    return $?
}


logger_info "create topic ${TOPIC_NAME}."
create_topic
if [ $? -ne 0 ];then
    logger_error "create topic ${TOPIC_NAME} failed."
    exit 1
fi
logger_info "create topic ${TOPIC_NAME}  ok."
