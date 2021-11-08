#!/bin/bash
# 安装前系统资源检查
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 3 ]];then
    logger_error "specify NODE_INSTALL_DIR NODE_DATA_DIR HOST_INFO not valid!!"
    exit 1
fi
NODE_INSTALL_DIR="$1"
NODE_DATA_DIR="$2"
HOST_INFO="$3"

CONFIG_DIR="`cd $curwkdir/../config; pwd`"
SYS_CONFIG_DIR="$CONFIG_DIR/sys_config"
RESLIMITFILE="$SYS_CONFIG_DIR/resLimit.properties"

# resLimit.properties中设置会覆盖这边的默认值;
AVAIL_INSTALL_DISK=10
AVAIL_DATA_DISK=10
AVAIL_MEMORY=2
MAX_DISK_USAGED=80

function checkDiskUsage()
{
    usedDiskPercent=`df $NODE_INSTALL_DIR -m -P | column -t  | sed -n "2p" | awk '{print $5}' | tr -d %`
    if [[ ${usedDiskPercent} -gt ${MAX_DISK_USAGED%%\%} ]]; then
        logger_error "The used space of install dir the $NODE_INSTALL_DIR is ${usedDiskPercent}G, more than max ${MAX_DISK_USAGED}%."
        return 1
    else
        logger_info "The used space of the install dir $NODE_INSTALL_DIR is ${usedDiskPercent}%, max ${MAX_DISK_USAGED}%."
    fi

    usedDiskPercent=`df $NODE_DATA_DIR -m -P | column -t  | sed -n "2p" | awk '{print $5}' | tr -d %`
    if [[ ${usedDiskPercent} -gt ${MAX_DISK_USAGED%%\%} ]]; then
        logger_error "The used space of the data dir $NODE_DATA_DIR is ${usedDiskPercent}%, more than max ${MAX_DISK_USAGED}%."
        return 1
    else
        logger_info "The used space of the data dir $NODE_DATA_DIR is ${usedDiskPercent}%, max ${MAX_DISK_USAGED}%."
    fi

    return 0
}

function checkFreeDisk()
{
    freeDisksize=`df $NODE_INSTALL_DIR -m -P | column -t  | sed -n "2p" | awk '{print $4}'`
    freeDisksize_g=$(( $freeDisksize / 1024 ))
    if [[ ${freeDisksize_g} -lt ${AVAIL_INSTALL_DISK%%GB} ]]; then
        logger_error "The available space of the install dir $NODE_INSTALL_DIR is ${freeDisksize_g}G, less than min needed ${AVAIL_INSTALL_DISK}G."
        return 1
    else
        logger_info "The available space of the install dir $NODE_INSTALL_DIR is ${freeDisksize_g}G, needed ${AVAIL_INSTALL_DISK}G."
    fi

    freeDisksize=`df $NODE_DATA_DIR -m -P | column -t  | sed -n "2p" | awk '{print $4}'`
    freeDisksize_g=$(( $freeDisksize / 1024 ))
    if [[ ${freeDisksize_g} -lt ${AVAIL_DATA_DISK%%GB} ]]; then
        logger_error "The available space of the data dir $NODE_DATA_DIR is ${freeDisksize_g}G, less than min needed ${AVAIL_DATA_DISK}G."
        return 1
    else
        logger_info "The available space of the data dir $NODE_DATA_DIR is ${freeDisksize_g}G, needed ${AVAIL_DATA_DISK}G."
    fi

    return 0
}

function checkMemory()
{
    availMem_G=`free -g  | column -t  | sed -n "2p" | awk '{print $7}'`
    if [[ ${availMem_G} -lt ${AVAIL_MEMORY%%GB} ]]; then
        logger_error "The available memory is ${availMem_G}G, less than min needed ${AVAIL_MEMORY}G."
        return 1
    else
        logger_info "The available memory is ${availMem_G}G, needed ${AVAIL_MEMORY}G."
    fi

    return 0
}

function main()
{
    # 先清除原内容
    rm -rf $SYS_CONFIG_DIR
    mkdir -p $SYS_CONFIG_DIR
    if [ -f $CONFIG_DIR/sysconfig.tar.gz ];then
        logger_info "use user speicfy $CONFIG_DIR/sysconfig.tar.gz"
        tar -zxf $CONFIG_DIR/sysconfig.tar.gz -C $CONFIG_DIR
        if [ $? -ne 0 ];then
            logger_error "unpack $CONFIG_DIR/sysconfig.tar.gz failed."
            return 1
        fi
    fi

    if [ ! -f $RESLIMITFILE ];then
        logger_info "no $RESLIMITFILE specify, no need to check"
        return 0
    fi

    mkdir -p $NODE_INSTALL_DIR
    mkdir -p $NODE_DATA_DIR
    dos2unix -q $RESLIMITFILE 2>/dev/null
    source $RESLIMITFILE
    checkFreeDisk
    if [ $? -ne 0 ];then
        logger_error "checkFreeDisk on $HOST_INFO failed!!"
        return 1
    fi

    checkDiskUsage
    if [ $? -ne 0 ];then
        logger_error "checkDiskUsage on $HOST_INFO failed!!"
        return 1
    fi

    checkMemory
    if [ $? -ne 0 ];then
        logger_error "checkMemory on $HOST_INFO failed!!"
        return 1
    fi

    logger_info "check system resource on $HOST_INFO ok"
}
main "$@"
