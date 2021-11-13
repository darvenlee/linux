#!/bin/bash
# 安装前置检查
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh

SOFTWARE_ROOT_DIR="`cd $curwkdir/../software; pwd`"
function unpack_runtimePkg()
{
    local runtimePkg="index-runtime"

    if [ -d $SOFTWARE_ROOT_DIR/${runtimePkg} ];then
        logger_info "$SOFTWARE_ROOT_DIR/${runtimePkg} already exist"
        return 0
    fi


    if [ `ls -d $SOFTWARE_ROOT_DIR/${runtimePkg}*tar.gz 2>/dev/null | wc -l` -ne 1 ];then
        logger_error "please prepare ${runtimePkg} package in $SOFTWARE_ROOT_DIR"
        return 1
    fi

    tar -zxf $SOFTWARE_ROOT_DIR/${runtimePkg}*tar.gz -C $SOFTWARE_ROOT_DIR
    if [ $? -ne 0 ]; then
        logger_error "unpack ${runtimePkg} failed"
        return 1
    fi
    logger_info "unpack ${runtimePkg} ok"
    return 0
}

function main()
{
    unpack_runtimePkg
    if [ $? -ne 0 ];then
        logger_error "preDealPackage failed!!"
        return 1
    fi

    logger_info "preDealPackage ok"
}
main "$@"
