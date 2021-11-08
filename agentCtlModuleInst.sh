#!/bin/bash
# 1. 远程执行agent控制modules下的instance目前只支持如下动作ACTION_NAME:
# install/uninstall/start/stop/restart/refresh
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 3 ]];then
    logger_error "specify MODULES_INSTALL_ROOT_DIR ACTION_NAME MODULE_NAME not valid!!"
    exit 1
fi

MODULES_INSTALL_ROOT_DIR="$1"
MODULE_NAME="$2"
ACTION_NAME="$3"

MODULES_SOFTWAR_DIR="$curwkdir/../modules"
function change_permission()
{
    local instName="$1"
    local moduleName="$MODULE_NAME"
    if [ ! -d $MODULES_INSTALL_ROOT_DIR/$moduleName/$instName ];then
        return 0
    fi

    chmod -Rf 500 $MODULES_INSTALL_ROOT_DIR/$moduleName/$instName/bin 2>/dev/null
    find $MODULES_INSTALL_ROOT_DIR/$moduleName/$instName/config -type f  | xargs chmod 600 2>/dev/null
    find $MODULES_INSTALL_ROOT_DIR/$moduleName/$instName/config -type d  | xargs chmod 700 2>/dev/null
    logger_info "refresh permission in $MODULES_INSTALL_ROOT_DIR/$moduleName/$instName ok"
}

function execute_appscript()
{
    local actionName="$1"
    local instName="$2"
    local moduleName="$MODULE_NAME"

    local appShell="$MODULES_INSTALL_ROOT_DIR/$moduleName/$instName/bin/app.sh"
    if [ ! -f $appShell ];then
        logger_error "bin/app.sh ${actionName} for $moduleName not exist"
        return 0
    fi
    logger_info "execute: $appShell $actionName"
    bash $appShell $actionName
}

function action_instances()
{
    local actionName="$1"
    if [ ! -d $MODULES_INSTALL_ROOT_DIR/$MODULE_NAME ];then
        return 0
    fi

    for instName in `cd $MODULES_INSTALL_ROOT_DIR/$MODULE_NAME; ls 2>/dev/null`
    do
        execute_appscript $actionName $instName
        if [  $? -ne 0 ];then
            logger_error "$actionName $MODULE_NAME for $instName failed"
            return 1
        fi

        if [ "$actionName" == "start" ];then
            change_permission
        fi
        
        logger_info "$actionName $MODULE_NAME for $instName ok"
    done
}

function uninstall_instances()
{
    local moduleName="$MODULE_NAME"
    if [ ! -d $MODULES_INSTALL_ROOT_DIR/$moduleName ];then
        return 0
    fi

    for instName in `cd $MODULES_INSTALL_ROOT_DIR/$moduleName; ls 2>/dev/null`
    do
        execute_appscript stop $instName
        if [  $? -ne 0 ];then
            logger_error "stop $MODULE_NAME for $instName failed"
            return 1
        fi

        execute_appscript uninstall $instName
        if [  $? -ne 0 ];then
            logger_error "uninstall $MODULE_NAME for $instName failed"
            return 1
        fi
        
        # 不提高权限删除不掉
        chmod +w -Rf $MODULES_INSTALL_ROOT_DIR/$moduleName/$instName
        rm -rf $MODULES_INSTALL_ROOT_DIR/$moduleName/$instName
        logger_info "uninstall $moduleName for $instName ok"
    done
}

function install_instances()
{
    local moduleName="$MODULE_NAME"
    local tmpcfg="$MODULES_SOFTWAR_DIR/tmpCfg/${moduleName}"

    rm -rf $MODULES_INSTALL_ROOT_DIR/$moduleName 2>/dev/null
    rm -rf $tmpcfg 2>/dev/null
    mkdir -p $tmpcfg

    mv $MODULES_SOFTWAR_DIR/$moduleName/config/${moduleName}-* $tmpcfg
    for instName in `cd $tmpcfg; ls 2>/dev/null`
    do
        mkdir -p $MODULES_INSTALL_ROOT_DIR/$moduleName/$instName
        cp -rf $MODULES_SOFTWAR_DIR/$moduleName/* $MODULES_INSTALL_ROOT_DIR/$moduleName/$instName
        cp -rf $tmpcfg/$instName $MODULES_INSTALL_ROOT_DIR/$moduleName

        execute_appscript install $instName
        if [  $? -ne 0 ];then
            logger_error "install $MODULE_NAME for $instName failed"
            return 1
        fi
        logger_info "install $moduleName for $instName ok"
    done
    rm -rf $tmpcfg 2>/dev/null
}

function refresh_instances()
{
    uninstall_instances
    install_instances
}

function ctl_for_instances()
{
    local actionName="$1"
    if [ "$actionName" == "install" ];then
        install_instances
    elif [ "$actionName" == "uninstall" ];then
        uninstall_instances
    elif [ "$actionName" == "refresh" ];then
        refresh_instances
    else
        action_instances "$actionName"
    fi

    return $?
}

function main()
{
    logger_info "begin to ${ACTION_NAME} for $MODULE_NAME instances...."
    ctl_for_instances ${ACTION_NAME}
    if [ $? -ne 0 ];then
        logger_error "$ACTION_NAME for $MODULE_NAME failed"
        exit 1
    fi
    logger_info "end to ${ACTION_NAME} for $MODULE_NAME instances...."
}
main $@
