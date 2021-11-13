#!/bin/bash
# 参数1:需要判断是否需要部署的模块
# 参数2:操作人员指定的当前允许操作的模块列表;不指定表示没有限制
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 2 ]];then
    logger_error "specify NODE_DIST_CFG_DIR MODULES_NAME not valid!!"
    exit 1
fi
NODE_DIST_CFG_DIR="$1"
MODULES_NAME="$2"
SPECIFY_ACTION_MODULES="$3"

# 返回0表示需要部署
# 返回1表示不需要部署
function needDeploy()
{
    if [ "$SPECIFY_ACTION_MODULES" != "" ];then
        # 如果指定了操作的模块;则部署必须以指定的为准
        echo "$SPECIFY_ACTION_MODULES" | grep "$MODULES_NAME" &>/dev/null
        if [ $? -eq 0 ];then
            if [ -f $NODE_DIST_CFG_DIR/deploy.properties ];then
                cat $NODE_DIST_CFG_DIR/deploy.properties | grep -w "^${MODULES_NAME}" | grep "true" &>/dev/null
                return $?
            fi
            return 0
        else
            return 1
        fi
    fi

    if [ ! -f $NODE_DIST_CFG_DIR/deploy.properties ];then
        return 0
    fi

    cat $NODE_DIST_CFG_DIR/deploy.properties | grep -w "^${MODULES_NAME}" | grep "true" &>/dev/null
    return $?
}
needDeploy
