#!/bin/bash
# 1. 生成单个节点需要的ES包并压缩成$ES_PKG_NAME.tar.gz
# 2. 将生成的es包+agent包,远程传送到HOST_INFO对应的$DST_SOFTWARE_DIR目录
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 5 ]];then
    logger_error "specify ES_PKG_NAME DST_SOFTWARE_DIR and HOST_INFO ACTION_NAME CLUSTER_TYPE not valid!!"
    exit 1
fi
ES_PKG_NAME="$1"
DST_SOFTWARE_DIR="$2"
HOST_INFO="$3"
ACTION_NAME="$4"
CLUSTER_TYPE="$5"

ES_USER="$ENV_SYSTEMUSER"
ES_GROUP="$ENV_SYSTEMGROUP"
HOST_PASSWORD="$ENV_PASSWORD"
HOST_NODENAME="$ENV_NODENAME"
if [[ "$ES_USER" == "" ]];then
    logger_info "not specify ES_USER param. use default `whoami`"
    ES_USER=`whoami`
    ES_GROUP=`whoami`
fi

SSHIP=`echo $HOST_INFO | awk -F "@" '{print $1}'`
SSHPORT=`echo $HOST_INFO | awk -F "@" '{print $2}'`

# 模块配置文件目录以及软件目录
NODE_DIST_CFG_DIR="$curwkdir/../config/nodesDistCfg/$HOST_NODENAME"

SRC_SOFTWARE_DIR="$curwkdir/../software"
SRC_PLUGIN_DIR="$SRC_SOFTWARE_DIR/plugin"
SRC_REFRESH_DIR="$curwkdir/../software/refresh"
ES_REFRESH_DIR="$SRC_REFRESH_DIR/es"
PACKING_LOCK_FLAG="$SRC_SOFTWARE_DIR/packing_${HOST_NODENAME}.lock"
TEMP_PACKING_DIR="$SRC_SOFTWARE_DIR/pack_${HOST_NODENAME}"
ES_CONFIG_DIR="$NODE_DIST_CFG_DIR/es"

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

function prepare_esPkg()
{
    if [ ! -f $SRC_SOFTWARE_DIR/$ES_PKG_NAME ]; then
        logger_error "$SRC_SOFTWARE_DIR/$ES_PKG_NAME file not exists."
        return 1
    fi

    # 取software目录下elasticsearch*tar.gz包
    cp $SRC_SOFTWARE_DIR/$ES_PKG_NAME $TEMP_PACKING_DIR/$ES_PKG_NAME
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "cp es package ${ES_PKG_NAME} to $TEMP_PACKING_DIR/$ES_PKG_NAME failed"
        return 1
    fi

    # 拷贝es安装包到远程地址
    # TODO: 此处会需要交互式输入密码
    scp $TEMP_PACKING_DIR/${ES_PKG_NAME} ${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR}  1>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "scp es package ${ES_PKG_NAME} to ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi
    logger_info "scp ${ES_PKG_NAME} to ${SSHIP}:${HOST_NODENAME}successfully"
}

function prepare_esCfg()
{
    local esConfigName="esconfig.tar.gz"

    if [ ! -f $ES_CONFIG_DIR/elasticsearch.yml ]; then
        logger_error "$ES_CONFIG_DIR/elasticsearch.yml not exists."
        return 1
    fi

    cd $TEMP_PACKING_DIR
    # 删除其中的模板文件
    rm -rf $ES_CONFIG_DIR/elasticsearch_template_*.yml 2>/dev/null
    cp $ES_CONFIG_DIR/* $TEMP_PACKING_DIR/config/  2>/dev/null

    # 压缩准备好的es配置文件
    tar -zcf $esConfigName config
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "packing config $esConfigName to $TEMP_PACKING_DIR failed"
        return 1
    fi

    # 拷贝eSConfig.tar.gz到远程地址
    # TODO: 此处会需要交互式输入密码
    scp $TEMP_PACKING_DIR/$esConfigName ${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR}/config 1>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "scp config $esConfigName to ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi
    logger_info "scp $esConfigName to ${SSHIP}:${HOST_NODENAME} successfully"
}

function prepare_plugin()
{
    # 拷贝plugin到远程地址
    for pluginName in `cd $SRC_SOFTWARE_DIR/plugin; ls *.zip 2>/dev/null`
    do
        scp $SRC_SOFTWARE_DIR/plugin/$pluginName ${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR}/plugin 1>/dev/null
        ret=$?
        if [ $ret -ne 0 ]; then
            logger_error "scp $pluginName to ${SSHIP}:${HOST_NODENAME} failed"
            return 1
        fi
    done

    logger_info "scp plugins to ${SSHIP}:${HOST_NODENAME} successfully"
}

function prepare_ES()
{
    bash $curwkdir/isNeedDeploy.sh $NODE_DIST_CFG_DIR "es"
    if [ $? -ne 0 ];then
        return 0
    fi

    prepare_esPkg
    if [ $? -ne 0 ]; then
        return 1
    fi

    prepare_esCfg
    if [ $? -ne 0 ]; then
        return 1
    fi
        
    prepare_plugin
    if [ $? -ne 0 ]; then
        return 1
    fi
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

    prepare_ES
    if [ $? -ne 0 ]; then
        return 1
    fi

    clean_enviroment
    logger_info "prepare packages to ${SSHIP}:${HOST_NODENAME} successfully"
    return 0
}

function refresh_esCfg()
{
    if [ ! -d $ES_CONFIG_DIR ];then
        logger_info "$ES_CONFIG_DIR not exists, no need to refresh."
        return 0
    fi

    mkdir -p $TEMP_PACKING_DIR/refresh/esConfig
    rm -rf $TEMP_PACKING_DIR/refresh/esConfig/* 2>/dev/null
    # 删除其中的模板文件
    rm -rf $ES_CONFIG_DIR/elasticsearch_template_*.yml 2>/dev/null
    cp -rf $ES_CONFIG_DIR/* $TEMP_PACKING_DIR/refresh/esConfig
    logger_info "refresh es config files to $TEMP_PACKING_DIR/refresh/esConfig."
}

function refresh_ES()
{
    bash $curwkdir/isNeedDeploy.sh $NODE_DIST_CFG_DIR  "es"
    if [ $? -ne 0 ];then
        return 0
    fi

    if [ ! -d $ES_REFRESH_DIR ]; then
        logger_info "$ES_REFRESH_DIR not exist, nothing to refresh for ES cluster."
        return 0
    fi

    if [ `find $ES_REFRESH_DIR -type f | grep -v ".txt" | wc -l` -eq 0 ]; then
        logger_info "find nothing to refresh to ES cluster."
        return 0
    fi

    local refreshName="es-refresh.tar.gz"
    rm -rf $TEMP_PACKING_DIR/refresh 2>/dev/null
    mkdir -p $TEMP_PACKING_DIR/refresh
    # jprofile需要重启es因此需要和es一块refresh
    cp -rf $ES_REFRESH_DIR/* $TEMP_PACKING_DIR/refresh 2>/dev/null

    # 刷新最新生成的es配置文件
    refresh_esCfg
    if [ $? -ne 0 ]; then
        logger_error "refresh esCfg to ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi
    
    cd $TEMP_PACKING_DIR
    tar -zcf $TEMP_PACKING_DIR/$refreshName refresh
    if [ $? -ne 0 ]; then
        logger_error "packing $refreshName to $TEMP_PACKING_DIR failed"
        return 1
    fi

    # 拷贝refresh.tar.gz到远程地址
    # TODO: 此处会需要交互式输入密码
    scp $TEMP_PACKING_DIR/$refreshName ${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR} 1>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "scp refresh $refreshName to ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi
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

    refresh_ES
    if [ $? -ne 0 ]; then
        logger_error "refresh es to ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi
    clean_enviroment
    logger_info "refresh packages to ${SSHIP}:${HOST_NODENAME} successfully"
}

function refresh_recall_pkg()
{
    if [ ! -d $SRC_REFRESH_DIR ]; then
        logger_info "$SRC_REFRESH_DIR not exists, nothing to refresh."
        return 0
    fi

    bash $curwkdir/prepareAgent.sh  $DST_SOFTWARE_DIR  $HOST_INFO  prepare $CLUSTER_TYPE
    if [ $? -ne 0 ]; then
        return 1
    fi

    local RECALL_PLUGIN_DIR="$ES_REFRESH_DIR/esPlugin"

    if [ ! -d "$RECALL_PLUGIN_DIR" ]; then
        logger_info "$RECALL_PLUGIN_DIR not exist, nothing to install for ES cluster."
        return 0
    fi

    if [ "$(find "$RECALL_PLUGIN_DIR" -type f | grep -E "$RECALL_PLUGIN_DIR/poisson_recall_.*.zip" | wc -l)" -eq 0 ]; then
        logger_info "find no recall_plugin to install to ES cluster."
        return 0
    fi

    for packagePath in "$RECALL_PLUGIN_DIR"/poisson_recall_*.zip; do
        packageName=$(basename "$packagePath")
        if [ -f "$SRC_PLUGIN_DIR"/"$packageName" ]; then
            logger_error "find package named ${packageName} in both ${SRC_PLUGIN_DIR} and ${RECALL_PLUGIN_DIR}.
            this plugin may already have been installed. Delete this package in ${SRC_PLUGIN_DIR}
            if still want to install this plugin, or delete ${RECALL_PLUGIN_DIR} to skip this plugin"

            return 1
        fi
    done

    local install_pkg_name="es-recall-install.tar.gz"
    rm -rf "$TEMP_PACKING_DIR"/recall_install 2>/dev/null
    mkdir -p "$TEMP_PACKING_DIR"/recall_install
    cp -rf "$RECALL_PLUGIN_DIR"/poisson_recall_*.zip "$TEMP_PACKING_DIR/recall_install"

    tar -zcf "$TEMP_PACKING_DIR/$install_pkg_name" -C "$TEMP_PACKING_DIR" recall_install
    if [ $? -ne 0 ]; then
        logger_error "packing $install_pkg_name to $TEMP_PACKING_DIR failed"
        return 1
    fi

    scp "$TEMP_PACKING_DIR/$install_pkg_name" "${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR}" 1>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "scp recall plugin pkg installation $install_pkg_name to ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi

    clean_enviroment
    logger_info "refresh poisson_recall plugin packages to ${SSHIP}:${HOST_NODENAME} successfully"
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

