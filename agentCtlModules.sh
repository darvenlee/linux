#!/bin/bash
# 1. 远程执行agent控制modules目前只支持如下动作ACTION_NAME:
# install/uninstall/start/stop/restart/refresh
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 4 ]];then
    logger_error "specify INSTALL_ROOT_DIR ACTION_NAME MODULE_SPCIFY JDK_PKG not valid!!"
    exit 1
fi

INSTALL_ROOT_DIR="$1"
ACTION_NAME="$2"
MODULE_SPCIFY="$3"
JDK_PKG="$4"

MODULES_INSTALL_ROOT_DIR="$INSTALL_ROOT_DIR"
MODULES_SOFTWAR_DIR="$curwkdir/../modules"
SOFTWARE_DIR="$curwkdir/.."

# 各模块的软件以及安装目录
SURPPORT_CTL_ACTIONS=("install" "uninstall" "start" "stop" "restart" "refresh")
NODE_DIST_CFG_DIR="$curwkdir/../config"
# 返回0表示是多实例
# 返回1表示不是多实例
function hasMutiInsts()
{
    local moduleName="$1"
    if [ ! -f $NODE_DIST_CFG_DIR/deploy.properties ];then
        return 1
    fi

    cat $NODE_DIST_CFG_DIR/deploy.properties | grep -w "^${moduleName}" | grep "multi" &>/dev/null
    ret=$?
    if [ $ret -eq 0 ];then
        logger_info "$moduleName has multi instances."
    fi

    return $ret
}

function deal_Insts()
{
    local moduleName="$1"
    local actionName="$2"

    bash $curwkdir/agentCtlModuleInst.sh $MODULES_INSTALL_ROOT_DIR "${moduleName}" $actionName
    if [ $? -ne 0 ];then
        logger_error "$actionName $moduleName failed"
        return 1
    fi
    return 0
}

function change_permission()
{
    local moduleName=$1
    if [ ! -d $MODULES_INSTALL_ROOT_DIR/$moduleName ];then
        return 0
    fi

    chmod -Rf 500 $MODULES_INSTALL_ROOT_DIR/$moduleName/bin 2>/dev/null
    find $MODULES_INSTALL_ROOT_DIR/$moduleName/config -type f  | xargs chmod 600 2>/dev/null
    find $MODULES_INSTALL_ROOT_DIR/$moduleName/config -type d  | xargs chmod 700 2>/dev/null
    logger_info "refresh permission in $MODULES_INSTALL_ROOT_DIR/$moduleName ok"
}

function deal_ByModuleApp()
{
    local moduleName="$1"
    local actionName="$2"

    hasMutiInsts $moduleName
    if [ $? -eq 0 ];then
        # 带有多实例的模块需要按多实例方式拷贝源软件处理
        deal_Insts $moduleName $actionName
        if [ $? -ne 0 ];then
            logger_error "${actionName} $moduleName failed"
            return 1
        fi
    else
        if [ ! -f $MODULES_INSTALL_ROOT_DIR/$moduleName/bin/app.sh ];then
            logger_error "bin/app.sh ${actionName} for $moduleName not exist"
            return 0
        fi

        bash $MODULES_INSTALL_ROOT_DIR/$moduleName/bin/app.sh $actionName
        if [ $? -ne 0 ];then
            logger_error "${actionName} $moduleName by ModuleApp failed: $MODULES_INSTALL_ROOT_DIR/$moduleName/bin/app.sh"
            return 1
        fi

        if [ "$actionName" == "start" ];then
            change_permission $moduleName
        fi
    fi
    logger_info "${actionName} $moduleName by ModuleApp ok: $MODULES_INSTALL_ROOT_DIR/$moduleName/bin/app.sh"
}

function stop_module()
{
    local moduleName="$1"
    if [ ! -d $MODULES_INSTALL_ROOT_DIR/$moduleName ];then
        logger_info "$MODULES_SOFTWAR_DIR/$moduleName not exist"
        return 0
    fi

    deal_ByModuleApp $moduleName stop
    logger_info "stop $MODULES_INSTALL_ROOT_DIR/$moduleName ok"
}

function uninstall_module()
{
    local moduleName="$1"
    stop_module $moduleName

    deal_ByModuleApp $moduleName uninstall
    # 不提高权限删除不掉
    chmod +w -Rf $MODULES_INSTALL_ROOT_DIR/$moduleName
    rm -rf $MODULES_INSTALL_ROOT_DIR/$moduleName 2>/dev/null
    logger_info "uninstall $moduleName ok"
}


function reinstall_module()
{
    local moduleName="$1"
    if [ ! -d $MODULES_SOFTWAR_DIR/$moduleName ];then
        logger_error "$MODULES_SOFTWAR_DIR/$moduleName not exist"
        return 1
    fi

    if [ -d $MODULES_INSTALL_ROOT_DIR/$moduleName ];then
        logger_info "try to uninstall $MODULES_INSTALL_ROOT_DIR/$moduleName first"
        uninstall_module $moduleName
    fi

    cp -rf $MODULES_SOFTWAR_DIR/$moduleName $MODULES_INSTALL_ROOT_DIR
    deal_ByModuleApp $moduleName install
    if [  $? -ne 0 ];then
        logger_error "reinstall $moduleName failed"
        return 1
    fi
    logger_info "reinstall $moduleName ok."
}


function reinstall_modules()
{
    local softwaredir="$1"
    if [ ! -d $softwaredir ];then
        logger_info "$softwaredir not exist"
        return 0
    fi

    local actionName="install"
    mkdir -p $MODULES_INSTALL_ROOT_DIR

    create_df_link
    if [ $? -ne 0 ]; then
        logger_error "create df link failed!!"
        return 1
    fi

    # 根据softwaredir目录下的模块包自动识别是否需要重装
    for pkgname in `cd $softwaredir; ls *tar.gz 2>/dev/null`
    do
        moduleName=${pkgname%%.tar.gz}
        bash $curwkdir/isNeedDeploy.sh $NODE_DIST_CFG_DIR "$moduleName" $MODULE_SPCIFY
        if [ $? -ne 0 ];then
            logger_info "$actionName for $moduleName no need to deal"
            continue
        fi

        # modules软件都统一解压到固定的模块软件目录；为了后文代码统一
        rm -rf $MODULES_SOFTWAR_DIR/$moduleName 2>/dev/null
        tar -zxf $softwaredir/$pkgname -C $MODULES_SOFTWAR_DIR
        if [  $? -ne 0 ];then
            logger_error "unpack $pkgname to $MODULES_SOFTWAR_DIR failed"
            return 1
        fi
        logger_info "unpack $pkgname to $MODULES_SOFTWAR_DIR ok"

        reinstall_module "$moduleName"
        if [ $? -ne 0 ];then
            logger_error "$actionName $moduleName failed"
            return 1
        fi

        # 使用完后必须删除软件包；
        # install和refresh是根据包自动识别是否需要重装的
        rm -f $softwaredir/$pkgname  2>/dev/null
        logger_info "$actionName $moduleName ok"
    done
}

function uninstall_modules()
{
    if [ ! -d $MODULES_INSTALL_ROOT_DIR ];then
        logger_info "$MODULES_INSTALL_ROOT_DIR not exist, may be no modules deploy on this node"
        return 0
    fi

    delete_df_link
    local actionName="uninstall"
    for moduleName in `cd $MODULES_INSTALL_ROOT_DIR; ls 2>/dev/null`
    do
        if [ ! -d $MODULES_INSTALL_ROOT_DIR/$moduleName ];then
            continue
        fi

        bash $curwkdir/isNeedDeploy.sh $NODE_DIST_CFG_DIR "$moduleName" $MODULE_SPCIFY
        if [ $? -ne 0 ];then
            logger_info "$actionName for $moduleName no need to deal"
            continue
        fi

        uninstall_module $moduleName
        logger_info "uninstall $moduleName ok"
    done
}

function create_df_link()
{
    local install_dir=${MODULES_INSTALL_ROOT_DIR%/modules*}
    local es_link_paths=$(find ${install_dir} -maxdepth 1 -type l)
    if [ -z "${es_link_paths}" ]; then
        return 0
    fi

    local module_node_name=$(basename ${MODULES_INSTALL_ROOT_DIR})
    # ${es_link_paths} cannot add quote
    for es_link_path in ${es_link_paths}
    do
        local es_real_path=$(readlink ${es_link_path})
        local es_node_name=$(basename ${es_real_path})
        if [ "${es_node_name}" == "${module_node_name}" ]; then
            local df_link_path=$(dirname ${MODULES_INSTALL_ROOT_DIR})/$(basename ${es_link_path})
            if [ -d "${df_link_path}" -a ! -L "${df_link_path}" ]; then
                logger_error "${df_link_path} exists as a directory, cannot create df link."
                return 1
            fi
            rm -f ${df_link_path}
            ln -s ${MODULES_INSTALL_ROOT_DIR} ${df_link_path}
            if [ $? -ne 0 ]; then
                logger_error "create df link failed: ln -s ${MODULES_INSTALL_ROOT_DIR} ${df_link_path}"
                return 1
            fi
        fi
    done
}

function delete_df_link()
{
    local df_link_dir=$(dirname ${MODULES_INSTALL_ROOT_DIR})
    local df_link_paths=$(find ${df_link_dir} -maxdepth 1 -type l)
    if [ -z "${df_link_paths}" ]; then
        return 0
    fi
    for df_link_path in ${df_link_paths}
    do
        local link_path=$(readlink ${df_link_path})
        if [ "${link_path}" == "${MODULES_INSTALL_ROOT_DIR}" ]; then
            rm -f ${df_link_path}
        fi
    done
}

function action_modules()
{
    local actionName="$1"
    if [ ! -d $MODULES_INSTALL_ROOT_DIR ];then
        logger_info "$MODULES_INSTALL_ROOT_DIR not exist, may be no modules deploy on this node"
        return 0
    fi

    for moduleName in `cd $MODULES_INSTALL_ROOT_DIR; ls`
    do
        if [ ! -d $MODULES_INSTALL_ROOT_DIR/$moduleName ];then
            continue
        fi

        bash $curwkdir/isNeedDeploy.sh $NODE_DIST_CFG_DIR "$moduleName" $MODULE_SPCIFY
        if [ $? -ne 0 ];then
            logger_info "$moduleName no need to deal"
            continue
        fi

        deal_ByModuleApp $moduleName ${actionName}
        if [ $? -ne 0 ];then
            return 1
        fi

        logger_info "${actionName} $moduleName ok"
    done
}

function refresh_modules()
{
    reinstall_modules $MODULES_SOFTWAR_DIR
    action_modules "start"
}

function ctl_for_modules()
{
    local actionName="$1"
    if [ "$actionName" == "install" ];then
        reinstall_modules $MODULES_SOFTWAR_DIR
    elif [ "$actionName" == "uninstall" ];then
        uninstall_modules
    elif [ "$actionName" == "refresh" ];then
        refresh_modules
    else
        action_modules "$actionName"
    fi

    return $?
}

function install_Java()
{
    JAVA_HOME=`ls -d $MODULES_INSTALL_ROOT_DIR/jre* 2>/dev/null`
    if [ "${JAVA_HOME}" != "" ];then
        logger_info "jre already installed, JAVA_HOME=$JAVA_HOME."
        export JAVA_HOME=$JAVA_HOME
        return 0
    fi

    if [ ! -f $SOFTWARE_DIR/$JDK_PKG ];then
        logger_error "$SOFTWARE_DIR/$JDK_PKG not exists"
        return 1
    fi

    logger_info "unpack java $SOFTWARE_DIR/$JDK_PKG to $MODULES_INSTALL_ROOT_DIR."
    tar -zxf $SOFTWARE_DIR/$JDK_PKG -C $MODULES_INSTALL_ROOT_DIR
    if [ $? -ne 0 ];then
        logger_error "unpack $packName failed"
        return 1
    fi

    JAVA_HOME=`ls -d $MODULES_INSTALL_ROOT_DIR/jre* 2>/dev/null`
    export JAVA_HOME=$JAVA_HOME
    rm -rf $MODULES_INSTALL_ROOT_DIR/jdk* 2>/dev/null
    logger_info "install java ok, JAVA_HOME=$JAVA_HOME."
}

function main()
{
    if [ `echo ${SURPPORT_CTL_ACTIONS[@]} | grep $ACTION_NAME | wc -l` -eq 0 ];then
        logger_info "${ACTION_NAME} for ctl_for_modules not support yet, only support: ${SURPPORT_CTL_ACTIONS[@]}."
        return 0
    fi

    if [ "$ACTION_NAME" != "uninstall" ];then
        if [ "${NODEJS_HOME}" == "" ];then
            logger_info "install pm2 in $MODULES_INSTALL_ROOT_DIR for modules...."
            bash $curwkdir/installPm2.sh
            if [ $? -ne 0 ];then
                logger_error "install pm2 failed"
            fi
        fi

        # JAVA_HOME必须使用自带的java包
        logger_info "install java in $MODULES_INSTALL_ROOT_DIR for modules...."
        install_Java
        if [ $? -ne 0 ];then
            logger_error "install java failed"
            return 1
        fi
        logger_info "install java JAVA_HOME=$JAVA_HOME"
    fi

    logger_info "begin to ${ACTION_NAME} for modules...."
    ctl_for_modules ${ACTION_NAME}
    if [ $? -ne 0 ];then
        logger_error "$ACTION_NAME for modules failed"
        exit 1
    fi

    if [ "$ACTION_NAME" == "uninstall" ];then
      if [[ "$MODULE_SPCIFY" =~ "file-fetcher" ]];then
        rm -rf $MODULES_INSTALL_ROOT_DIR/jre* 2>/dev/null
        logger_info "uninstall modules jre ok"
      fi
    fi
    logger_info "end to ${ACTION_NAME} for modules...."
}
main $@
