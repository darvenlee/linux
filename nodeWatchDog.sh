#!/bin/bash
# 1. 定时监控模块
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh

if [[ $# -lt 2 ]];then
    logger_WTdog "specify ES_INSTALL_DIR ES_INSTANCE_NAME not valid!!"
    exit 1
fi

ES_INSTALL_DIR="$1"
ES_INSTANCE_NAME="$2"

function watch_es()
{
    if [ `ps axf | grep "org.elasticsearch.bootstrap.Elasticsearch" | grep "$ES_INSTALL_DIR" | grep "/bin/java" |  grep -v grep | wc -l` -ne 0 ];then
        logger_WTdog "$ES_INSTALL_DIR is ok"
        return 0
    fi

    if [ ! -d $ES_INSTALL_DIR ];then
        logger_WTdog "dir $ES_INSTALL_DIR has been removed"
        return 0
    fi

    cd $ES_INSTALL_DIR
    ./bin/elasticsearch -d -p pid
    if [  $? -ne 0 ];then
        logger_WTdog "$ES_INSTANCE_NAME start failed"
        return 1
    fi
    logger_WTdog "start es $ES_INSTANCE_NAME ok"
}

function main()
{
    while /bin/true
    do
        sleep 30
        watch_es
    done
}
main "$@"
