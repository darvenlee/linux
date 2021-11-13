#!/bin/bash
# 生成并传输modules的包到目的地
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 4 ]];then
    logger_error "specify DST_SOFTWARE_DIR and HOST_INFO ACTION_NAME CLUSTER_TYPE not valid!!"
    exit 1
fi

DST_SOFTWARE_DIR="$1"
HOST_INFO="$2"
ACTION_NAME="$3"
CLUSTER_TYPE="$4"

ES_USER="$ENV_SYSTEMUSER"
ES_GROUP="$ENV_SYSTEMGROUP"
HOST_PASSWORD="$ENV_PASSWORD"
HOST_NODENAME="$ENV_NODENAME"
MODULE_SPCIFY="$ENV_SPCIFYMODULES"
if [[ "$ES_USER" == "" ]];then
    logger_info "not specify ES_USER param. use default `whoami`"
    ES_USER=`whoami`
    ES_GROUP=`whoami`
fi
SSHIP=`echo $HOST_INFO | awk -F "@" '{print $1}'`
SSHPORT=`echo $HOST_INFO | awk -F "@" '{print $2}'`

# 模块配置文件目录以及软件目录
NODE_DIST_CFG_DIR="$curwkdir/../config/nodesDistCfg/$HOST_NODENAME"
MODULES_SOFTWAR_DIR="$curwkdir/../software/modules"

SRC_SOFTWARE_DIR="$curwkdir/../software"
SRC_REFRESH_DIR="$curwkdir/../software/refresh"
MODULES_REFRESH_DIR="$SRC_REFRESH_DIR/modules"
PACKING_LOCK_FLAG="$SRC_SOFTWARE_DIR/packing_${HOST_NODENAME}.lock"
TEMP_PACKING_DIR="$SRC_SOFTWARE_DIR/pack_${HOST_NODENAME}"

function clean_enviroment()
{
    if [[ -d $TEMP_PACKING_DIR ]];then
        rm -rf $TEMP_PACKING_DIR
    fi
    clear_packingflag
}

function clear_packingflag()
{
    if [[ -f  $PACKING_LOCK_FLAG ]]; then
        rm -f $PACKING_LOCK_FLAG
    fi
}

function prepare_module()
{
    local moduleName="$1"
    local softwaredir="$2"
    local pkgName="${moduleName}.tar.gz"
    local cfgdir="$NODE_DIST_CFG_DIR/$moduleName"

    rm -rf $TEMP_PACKING_DIR/$moduleName 2>/dev/null
    mkdir -p $TEMP_PACKING_DIR/$moduleName/config

    # 准备软件包
    cp -rf $softwaredir/$moduleName/* $TEMP_PACKING_DIR/$moduleName 2>/dev/null
    
    # 准备配置文件
    if [ -d $cfgdir ]; then
        logger_info "prepare config of $moduleName for ${SSHIP}:${HOST_NODENAME}"
        cp -rf $cfgdir/* $TEMP_PACKING_DIR/$moduleName/config 2>/dev/null
        dos2unix -q $TEMP_PACKING_DIR/$moduleName/config/*.properties  2>/dev/null
    fi

    cd $TEMP_PACKING_DIR
    tar -zcf $pkgName $moduleName
    if [ $? -ne 0 ]; then
        logger_error "pack $pkgName of $moduleName for ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi

    # 拷贝$moduleName.tar.gz到远程地址
    scp $TEMP_PACKING_DIR/$pkgName ${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR}/modules 1>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "scp $pkgName of $moduleName to ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi

    rm -f $TEMP_PACKING_DIR/$pkgName
    logger_info "scp pkg(include config) of $moduleName to ${SSHIP}:${HOST_NODENAME} successfully"
}

function prepare_modules()
{
    local softwaredir="$1"
    if [ ! -d $softwaredir ];then
        logger_info "no modules pkg need to prepare"
        return 0
    fi

    for module in `cd $softwaredir; ls 2>/dev/null`
    do
        bash $curwkdir/isNeedDeploy.sh $NODE_DIST_CFG_DIR "$module" "$MODULE_SPCIFY"
        if [ $? -ne 0 ];then
            continue
        fi

        if [ ! -d $softwaredir/$module ];then
            continue
        fi

        if [ `ls $softwaredir/$module | grep -v ".txt" | wc -l` -eq 0 ];then
            logger_info "$module no need to deploy, can not find any software."
            continue
        fi

        logger_info "start to prepare pkg for $module"
        prepare_module "$module" $softwaredir
        if [ $? -ne 0 ]; then
            logger_info "prepare $module failed"
            return 1
        fi
        logger_info "prepare pkg for $module ok"
    done
}

function prepare_pkg()
{
    exec 9<>$PACKING_LOCK_FLAG
    flock -n 9
    if [ $? -ne 0 ]; then
        logger_error "$HOST_INFO is packing, can not redo, please waitting"
        return 1
    fi
    rm -rf $TEMP_PACKING_DIR
    mkdir -p $TEMP_PACKING_DIR
    mkdir -p $TEMP_PACKING_DIR/config

    bash $curwkdir/prepareAgent.sh  $DST_SOFTWARE_DIR  $HOST_INFO  $ACTION_NAME $CLUSTER_TYPE
    if [ $? -ne 0 ]; then
        return 1
    fi

    # 将software/modules下的软件包按模块粒度分发出去
    prepare_modules "$MODULES_SOFTWAR_DIR"
    if [ $? -ne 0 ]; then
        return 1
    fi

    clean_enviroment
    logger_info "prepare packages to ${SSHIP}:${HOST_NODENAME} successfully"
    return 0
}

function refresh_modules()
{
    prepare_modules "$MODULES_REFRESH_DIR"
}

function refresh_pkg()
{
    if [ ! -d $SRC_REFRESH_DIR ]; then
        logger_info "$SRC_REFRESH_DIR not exists, nothing to refresh."
        return 0
    fi

    bash $curwkdir/prepareAgent.sh  $DST_SOFTWARE_DIR  $HOST_INFO  $ACTION_NAME $CLUSTER_TYPE
    if [ $? -ne 0 ]; then
        return 1
    fi

    # 刷新modules软件;简单点直接借用原来的软件目录
    refresh_modules
    if [ $? -ne 0 ]; then
        logger_error "refresh modules to ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi

    clean_enviroment
    logger_info "refresh packages to ${SSHIP}:${HOST_NODENAME} successfully"
}

function main()
{
    # 由于免密登录首次会询问yes/no需要事先处理一下
    bash $curwkdir/preLoginCheck.sh $HOST_INFO
    if [ $? -ne 0 ];then
        logger_error "loggin on ${SSHIP} with $ES_USER failed!!"
        return 1
    fi
    
    ${ACTION_NAME}_pkg
    if [ $? -ne 0 ];then
        clean_enviroment
        exit 1
    fi
}
main "$@"

