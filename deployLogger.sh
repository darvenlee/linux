#!/bin/bash
logger_curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"

ES_USER=`whoami`
ES_GROUP=`whoami`

DEPLOY_LOGDIR="${logger_curwkdir}/../log"
__DEPLOY_LOGDIR_SH__="${DEPLOY_LOGDIR}"
# 主流程迁移日志
LOG_FILE_NAME="${DEPLOY_LOGDIR}/deploy.log"
# 系统异常日志记录
LOG_FATL_FILE_NAME="${DEPLOY_LOGDIR}/fatal.log"
# watchdog日志
WATCHDOG_LOG_FILE_NAME="${DEPLOY_LOGDIR}/watchdog.log"

LOG_FILE_LIST="${LOG_FILE_NAME} ${LOG_FATL_FILE_NAME} ${WATCHDOG_LOG_FILE_NAME}"

function logger_touch_file()
{
    touch $LOG_FILE_LIST &>/dev/null
    chmod 640 $LOG_FILE_LIST &>/dev/null
    chown $ES_USER:$ES_GROUP $LOG_FILE_LIST &>/dev/null
    return 0
}

function logger_current_time()
{
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
}

function logger_zip_logfile()
{
    local FILESIZE=0
    local TIME_NOW=0
    local BACKUPFILE=""
    # 日志大于20M开始压缩
    local MAX_LOG_FILE_SIZE=20     #limit of log file size,unit:K

    FILESIZE=$(find $DEPLOY_LOGDIR -name "*\.log" 2>/dev/null | xargs du -shm | awk '{sum += $1}; END {print sum}')
    if [ -z "${FILESIZE}" ]; then
        return 0
    fi

    if [ "${FILESIZE}" -lt "${MAX_LOG_FILE_SIZE}" ]; then
        return 0
    fi

    #backup the file
    TIME_NOW=$(date +'%Y%m%d-%H%M%S')
    BACKUPFILE=${DEPLOY_LOGDIR}/${TIME_NOW}.zip

    local oldDir=`pwd`
    # 临时进到日志目录里面，更方便压缩
    cd $DEPLOY_LOGDIR
    ls *.log 2>/dev/null | xargs zip -jmq "${BACKUPFILE}" &>/dev/null
    cd $oldDir

    logger_touch_file
    chmod 400 "${BACKUPFILE}" &>/dev/null
    chown $ES_USER:$ES_GROUP $BACKUPFILE
    return 0
}

#本接口只用于记录系统致命性异常的日志:
#比如密码加解密失败,gauss的ssl证书访问权限不对
function logger_fatal()
{
    logger_zip_logfile
    echo -e "$(logger_current_time) [FATAL] ${1}"
    echo -e "$(logger_current_time) ${1}" >> ${LOG_FATL_FILE_NAME}
    return 0
}

function logger_error()
{
    logger_zip_logfile
    echo -e "$(logger_current_time) [ERROR] ${1}"
    echo -e "$(logger_current_time) [ERROR] ${1}" >> ${LOG_FILE_NAME}
    return 0
}

function logger_warn()
{
    logger_zip_logfile
    echo -e "$(logger_current_time) [WARN] ${1}"
    echo -e "$(logger_current_time) [WARN] ${1}" >> ${LOG_FILE_NAME}
    return 0
}

function logger_info()
{
    logger_zip_logfile
    echo -e "$(logger_current_time) [INFO] ${1}" >> ${LOG_FILE_NAME}
    return 0
}

function logger_WTdog()
{
    logger_zip_logfile
    echo -e "$(logger_current_time) [INFO] ${1}" >> ${WATCHDOG_LOG_FILE_NAME}
    return 0
}

if [ ! -f $LOG_FATL_FILE_NAME ];then
    mkdir -p $DEPLOY_LOGDIR  &>/dev/null
    chown -Rf $ES_USER:$ES_GROUP ${DEPLOY_LOGDIR}  &>/dev/null
    logger_touch_file
fi
