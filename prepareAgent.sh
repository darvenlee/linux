#!/bin/bash
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
if [[ "$ES_USER" == "" ]];then
    logger_info "not specify ES_USER param. use default `whoami`"
    ES_USER=`whoami`
    ES_GROUP=`whoami`
fi

SSHIP=`echo $HOST_INFO | awk -F "@" '{print $1}'`
SSHPORT=`echo $HOST_INFO | awk -F "@" '{print $2}'`

SRC_SOFTWARE_DIR="$curwkdir/../software"
TEMP_PACKING_DIR="$SRC_SOFTWARE_DIR/pack_${HOST_NODENAME}"
NODE_DIST_CFG_DIR="$curwkdir/../config/nodesDistCfg/$HOST_NODENAME"
SYS_CONFIG_DIR="$curwkdir/../config/sys_config"
CONFIG_DIR="$curwkdir/../config"

function prepare_remote_dir()
{
ssh $ES_USER@${SSHIP} << eeooff
mkdir -p ${DST_SOFTWARE_DIR}/config
mkdir -p ${DST_SOFTWARE_DIR}/plugin
mkdir -p ${DST_SOFTWARE_DIR}/shellscript
mkdir -p ${DST_SOFTWARE_DIR}/modules
mkdir -p ${DST_SOFTWARE_DIR}/pm2_monit
chmod 750 -Rf ${DST_SOFTWARE_DIR}
eeooff
    if [ $? -ne 0 ]; then
        logger_error "ssh to $ES_USER@${SSHIP} and prepare dir ${DST_SOFTWARE_DIR} failed"
        return 1
    fi
    logger_info "ssh to ${SSHIP}:${HOST_NODENAME} with $ES_USER and prepare dir ok"
}

function prepare_distCfg()
{
    # 拷贝deploy.properties到远程地址
    if [ -f $NODE_DIST_CFG_DIR/deploy.properties ];then
        scp $NODE_DIST_CFG_DIR/deploy.properties ${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR}/config 1>/dev/null
        ret=$?
        if [ $ret -ne 0 ]; then
            logger_error "scp deploy.properties to ${SSHIP}:${HOST_NODENAME} failed"
            return 1
        fi
        logger_info "scp deploy.properties to ${SSHIP}:${HOST_NODENAME} successfully"
    fi
}

function backup_cluster_cfg()
{
    date=$(date '+%Y-%m-%d')
    backup_pkg_name="config_back-${date}.tar.gz"

    mkdir -p "${TEMP_PACKING_DIR}/config_backup"
    cp ${CONFIG_DIR}/cluster_nodes_cfg* ${TEMP_PACKING_DIR}/config_backup/

    cd ${TEMP_PACKING_DIR}
    tar -zcf "${backup_pkg_name}" config_backup
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_warn "packing backup config ${backup_pkg_name} to ${TEMP_PACKING_DIR} failed"
        return 0
    fi

    scp "${TEMP_PACKING_DIR}/${backup_pkg_name}" "${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR}/config" 1>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_warn "scp backup tar to ${SSHIP}:${HOST_NODENAME} failed"
        return 0
    fi
}

function prepare_sysCfg()
{
    local sysConfigName="sysconfig.tar.gz"

    if [ `ls $SYS_CONFIG_DIR/ | wc -l` -eq 0 ]; then
        logger_info "$SYS_CONFIG_DIR not exists config."
        return 0
    fi

    mkdir -p $TEMP_PACKING_DIR/sys_config

    # 如果sys_config有$CLUSTER_TYPE文件夹, 且部署集群也是$CLUSTER_TYPE，则进行sys_config文件刷新
    find $SYS_CONFIG_DIR -maxdepth 1 -type f -exec cp {} $TEMP_PACKING_DIR/sys_config \;
    if [ -n $CLUSTER_TYPE -a -d $SYS_CONFIG_DIR/$CLUSTER_TYPE ]; then
        cp $SYS_CONFIG_DIR/$CLUSTER_TYPE/* $TEMP_PACKING_DIR/sys_config
    fi

    dos2unix -q $TEMP_PACKING_DIR/sys_config/* 2>/dev/null

    # 动态刷新为实际用户
    sed -i "s/@USERNAME/${ES_USER}/g" $TEMP_PACKING_DIR/sys_config/limits.conf 2>/dev/null
    sed -i "s/@USERNAME/${ES_USER}/g" $TEMP_PACKING_DIR/sys_config/sysctl.conf  2>/dev/null

    cd $TEMP_PACKING_DIR
    # 压缩准备好的sys配置文件
    tar -zcf $sysConfigName sys_config
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "packing config $sysConfigName to $TEMP_PACKING_DIR failed"
        return 1
    fi

    # 拷贝sysconfig.tar.gz到远程地址
    # TODO: 此处会需要交互式输入密码
    scp $TEMP_PACKING_DIR/$sysConfigName ${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR}/config 1>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "scp config $sysConfigName to ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi
    logger_info "scp $sysConfigName to ${SSHIP}:${HOST_NODENAME} successfully"
}

function prepare_agentPkg()
{
    prepare_remote_dir
    if [ $? -ne 0 ]; then
        return 1
    fi

    prepare_sysCfg
    if [ $? -ne 0 ]; then
        return 1
    fi

    prepare_distCfg
    if [ $? -ne 0 ]; then
        return 1
    fi

    backup_cluster_cfg

    # 拷贝agent脚本到远程地址
    scp $curwkdir/*.sh ${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR}/shellscript 1>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "scp agentScript to ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi
    logger_info "scp agentScript to ${SSHIP}:${HOST_NODENAME} successfully"
}

function refresh_agentPkg()
{
    prepare_remote_dir
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    prepare_sysCfg
    if [ $? -ne 0 ]; then
        return 1
    fi

    prepare_distCfg
    if [ $? -ne 0 ]; then
        return 1
    fi

    agentName="agentPkg.tar.gz"

    mkdir -p $TEMP_PACKING_DIR/shellscript
    cp -rf $curwkdir/* $TEMP_PACKING_DIR/shellscript

    cd $TEMP_PACKING_DIR
    tar -zcf $agentName shellscript
    if [ $? -ne 0 ]; then
        logger_error "pack $agentName of shellscript for ${SSHIP}:${HOST_NODENAME} failed"
        return 1
    fi

    # 拷贝agent脚本到远程地址
    scp $TEMP_PACKING_DIR/$agentName ${ES_USER}@${SSHIP}:${DST_SOFTWARE_DIR} 1>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        logger_error "refresh $agentName to ${SSHIP}:${HOST_NODENAME}failed"
        return 1
    fi

    logger_info "refresh $agentName to ${SSHIP}:${HOST_NODENAME} successfully"
}


function main()
{
    ${ACTION_NAME}_agentPkg
    if [ $? -ne 0 ];then
        exit 1
    fi
}
main "$@"

