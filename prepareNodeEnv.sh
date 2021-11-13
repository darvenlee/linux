#!/bin/bash
# 配置节点上的操作系统配置,比如：sysctl.conf和limits.conf
# 执行用户必须具备sudo权限
# 未指定定制系统文件,则直接拷贝系统文件,修改后再覆盖回去
# 否则,将定制的内容追加到系统文件中,并去掉重复信息
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
CONFIG_DIR="$curwkdir/../config"
SYS_CONFIG_DIR="$CONFIG_DIR/sys_config"
ES_DATA_DIR="$1"
source $curwkdir/deployLogger.sh

ES_USER=`whoami`
ES_GROUP=`whoami`

function clear_sysctlKey()
{
    local key="$1"
    local cfgfile="$2"
    sed -i "/${key}/d" $cfgfile
}

function clearSysctl()
{
    local tmpCfg=$1
    keys=("vm.max_map_count" "vm.overcommit_memory")
    for clearkey in ${keys[@]}
    do
        clear_sysctlKey $clearkey $tmpCfg
    done
}

function clear_limitKey()
{
    local key="$1"
    local cfgfile="$2"
    sed -i "/${ES_USER} - ${key}/d" $cfgfile
    sed -i "/${ES_USER} soft ${key}/d" $cfgfile
    sed -i "/${ES_USER} hard ${key}/d" $cfgfile
}

function clearLimits()
{
    local tmpCfg=$1
    keys=("core" "as" "nofile" "memlock")
    for clearkey in ${keys[@]}
    do
        clear_limitKey $clearkey $tmpCfg
    done
}

function set_sysctl()
{
    local sysctlCfg="/etc/sysctl.conf"
    local specifySysctlCfg="$SYS_CONFIG_DIR/sysctl.conf"
    local tmpSysctlCfg="$SYS_CONFIG_DIR/tempsysctl.conf"

    # 未指定定制系统文件,则直接拷贝系统文件,修改后再覆盖回去
    # 否则,将定制的内容追加到系统文件中并去掉重复信息
    if [ ! -f $specifySysctlCfg ];then
        logger_info "modify $specifySysctlCfg of system directly."
        touch $specifySysctlCfg
        sudo cp $sysctlCfg $specifySysctlCfg
        if [ $? -ne 0 ];then
            logger_error "cp $sysctlCfg to $specifySysctlCfg failed."
            return 1
        fi
        clearSysctl $specifySysctlCfg

        local key="vm.max_map_count"
        local value="65535000"
        echo "${key} = ${value}" >> $specifySysctlCfg
    else
        touch $tmpSysctlCfg
        sudo cp $sysctlCfg $tmpSysctlCfg
        if [ $? -ne 0 ];then
            logger_error "cp $sysctlCfg to $tmpSysctlCfg failed."
            return 1
        fi
        clearSysctl $tmpSysctlCfg
        echo "" >> $tmpSysctlCfg
        dos2unix -q $specifySysctlCfg
        cat $specifySysctlCfg  >> $tmpSysctlCfg
        mv $tmpSysctlCfg $specifySysctlCfg
    fi

    sudo cp $specifySysctlCfg $sysctlCfg
    if [ $? -ne 0 ];then
        logger_error "overwrite $tmpSysctlCfg to $sysctlCfg failed."
        return 1
    fi

    # 触发生效
    sudo sysctl -p &>/dev/null
    logger_info "set node $sysctlCfg ok. config=`sudo sysctl -a`"
}

function set_ulimits()
{
    local limitCfg="/etc/security/limits.conf"
    local specifyLimitCfg="$SYS_CONFIG_DIR/limits.conf"
    local tmpLimitCfg="$SYS_CONFIG_DIR/templimits.conf"

    # 未指定定制系统文件,则直接拷贝系统文件,修改后再覆盖回去
    # 否则,将定制的内容追加到系统文件中并去掉重复信息
    if [ ! -f $specifyLimitCfg ];then
        logger_info "modify $limitCfg of system directly."
        touch $specifyLimitCfg
        sudo cp $limitCfg $specifyLimitCfg
        if [ $? -ne 0 ];then
            logger_error "cp $limitCfg to $tmpLimitCfg failed."
            return 1
        fi
        clearLimits $specifyLimitCfg
        
        local key="core"
        echo "$ES_USER soft ${key} 65535000" >>$specifyLimitCfg
        echo "$ES_USER hard ${key} 65535000" >>$specifyLimitCfg

        # 设置虚拟内存上限
        key="as"
        echo "$ES_USER - ${key} unlimited" >>$specifyLimitCfg

        # 设置文件句柄上限;设置过大会引发数值翻转
        key="nofile"
        echo "$ES_USER soft ${key} 1000000" >>$specifyLimitCfg
        echo "$ES_USER hard ${key} 1000000" >>$specifyLimitCfg

        # 设置可锁定内存上限
        key="memlock"
        echo "$ES_USER - ${key} unlimited" >>$specifyLimitCfg
    else
        touch $tmpLimitCfg
        sudo cp $limitCfg $tmpLimitCfg
        if [ $? -ne 0 ];then
            logger_error "cp $limitCfg to $tmpLimitCfg failed."
            return 1
        fi
        clearLimits $tmpLimitCfg
        echo "" >> $tmpLimitCfg
        dos2unix -q  $specifyLimitCfg
        cat $specifyLimitCfg >> $tmpLimitCfg
        mv $tmpLimitCfg $specifyLimitCfg
    fi

    sudo cp $specifyLimitCfg $limitCfg
    if [ $? -ne 0 ];then
        logger_error "overwrite $specifyLimitCfg to $limitCfg failed."
        return 1
    fi

    logger_info "set node limits.conf ok. config=`ulimit -a`"
}

function modify_blockDev()
{
    if [ "$ES_DATA_DIR" == "" ];then
        logger_info "have not specify ES_DATA_DIR, no need to modify blockDev."
        return 0
    fi

    if [ ! -d "$ES_DATA_DIR" ];then
        logger_error "specify $ES_DATA_DIR invalid."
        return 1
    fi

    modifyDev=`df -h $ES_DATA_DIR | tail -1 | awk -F ' ' '{print $1}'`
    sudo blockdev --setra ${READ_AHEAD_SIZE} $modifyDev
    if [ $? -ne 0 ];then
        logger_error "modify block dev failed."
        return 1
    fi

    # 尝试加入到重启计划中
    if [ `cat /etc/rc.local | grep "blockdev --setra" | grep "$modifyDev" | wc -l` -eq 0 ];then
        logger_info "try to modify blockDev in /etc/rc.local."
        rm -f  $curwkdir/rc.local 2>/dev/null
        touch $curwkdir/rc.local
        sudo cp /etc/rc.local $curwkdir/rc.local
        sudo echo "blockdev --setra ${READ_AHEAD_SIZE} $modifyDev" >> $curwkdir/rc.local
        sudo cp $curwkdir/rc.local /etc/rc.local
        if [ $? -ne 0 ];then
            logger_error "overwrite /etc/rc.local with $curwkdir/rc.local failed."
        fi
        rm -f  $curwkdir/rc.local 2>/dev/null
    fi
    logger_info "modify blockDev for $modifyDev ok."
    return 0
}

function modify_dns()
{
    # 修改dns相关的信息,规避FI的dns解析挂死问题
    if [ `sudo cat /etc/resolv.conf | grep -i "^nameserver" | wc -l` -ne 0 ];then
        sudo sed  -i "s/^nameserver/#nameserver/g" /etc/resolv.conf
        logger_info "modify /etc/resolv.conf ok."
    fi

    if [ `sudo cat /etc/hosts | grep -i "hadoop.hadoop.com" | wc -l` -ne 0 ];then
        sudo sed -i "/hadoop.com/d" /etc/hosts
        sudo echo "1.1.1.1 hadoop.hadoop.com" >> /etc/hosts
        sudo echo "" >> /etc/hosts
        logger_info "modify /etc/hosts ok."
    fi

    logger_info "modify dns ok."
    return 0
}

function main()
{
    sudo -n true
    if [ $? -ne 0 ];then
        logger_error "user `whoami` do not have sudo permission with no password."
        return 1
    fi

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

    set_sysctl
    if [ $? -ne 0 ];then
        logger_error "set sysctl failed"
        return 1
    fi

    set_ulimits
    if [ $? -ne 0 ];then
        logger_error "set ulimits failed"
        return 1
    fi

    source $SYS_CONFIG_DIR/kernel.conf
    modify_blockDev
    if [ $? -ne 0 ];then
        logger_error "modify blockDev failed"
        return 1
    fi
    logger_info "prepare node env ok."
}
main $@
