#!/bin/bash
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh

SOFTWARE_DIR="`cd $curwkdir/../pm2_monit; pwd`"
INSTALL_DIR="$SOFTWARE_DIR/install"
mkdir -p $INSTALL_DIR

NODEJS_VER="v10.16.0"
NODEJS_PACKNAME="node-${NODEJS_VER}-linux-x64"
PM2_PACKNAME="pm2"
function install_pm2()
{
    local packName="$PM2_PACKNAME"
    if [ ! -f $SOFTWARE_DIR/${packName}.tar.gz ];then
        logger_error "$SOFTWARE_DIR/${packName}.tar.gz not exist"
        return 1
    fi

    logger_info "unpack pm2."
    rm -rf $INSTALL_DIR/$packName 2>/dev/null
    tar -zxf $SOFTWARE_DIR/${packName}.tar.gz -C $INSTALL_DIR
    if [ $? -ne 0 ];then
        logger_error "unpack $packName failed"
        return 1
    fi

    logger_info "install pm2."
    rm -rf $INSTALL_DIR/$NODEJS_PACKNAME/lib/node_modules/pm2 2>/dev/null
    mv $INSTALL_DIR/pm2 $INSTALL_DIR/$NODEJS_PACKNAME/lib/node_modules/pm2
    if [ $? -ne 0 ];then
        logger_error "cp $packName to $INSTALL_DIR/$NODEJS_PACKNAME/lib/node_modules/pm2 failed"
        return 1
    fi

    logger_info "link pm2 in node JS."
    cd $INSTALL_DIR/$NODEJS_PACKNAME/bin
    rm pm2 2>/dev/null
    ln -s ../lib/node_modules/pm2/bin/pm2 pm2

    rm pm2-dev 2>/dev/null
    ln -s ../lib/node_modules/pm2/bin/pm2-dev pm2-dev

    rm pm2-docker 2>/dev/null
    ln -s ../lib/node_modules/pm2/bin/pm2-docker pm2-docker

    rm pm2-runtime 2>/dev/null
    ln -s ../lib/node_modules/pm2/bin/pm2-runtime pm2-runtime
}


function install_nodeJs()
{
    local packName="$NODEJS_PACKNAME"
    if [ ! -f $SOFTWARE_DIR/${packName}.tar.xz ];then
        logger_info "$SOFTWARE_DIR/${packName}.tar.xz not exist, no need to install"
        return 0
    fi

    logger_info "unpack node js."
    rm -rf $INSTALL_DIR/$packName 2>/dev/null
    tar -xJf $SOFTWARE_DIR/${packName}.tar.xz -C $INSTALL_DIR
    if [ $? -ne 0 ];then
        logger_error "unpack $packName failed"
        return 1
    fi

    logger_info "install node js."
    install_pm2
    if [ $? -ne 0 ];then
        logger_error "install pm2 failed."
        return 1
    fi

    nodejshome="$INSTALL_DIR/$packName/bin"
    cat $HOME/.bashrc | grep "NODEJS_HOME="
    if [ $? -ne 0 ];then
        echo "export NODEJS_HOME=$nodejshome" >> $HOME/.bashrc
        echo "PATH=\$NODEJS_HOME:$PATH" >> $HOME/.bashrc
        logger_info "refresh PATH=$PATH"
    fi
}


function main()
{
    if [ "$NODEJS_HOME" != "" ];then
        return 0
    fi

    logger_info "install pm2 tools begin."
    install_nodeJs
    if [ $? -ne 0 ];then
        logger_error "install node js failed."
        return 1
    fi
    logger_info "install pm2 tools ok."
}
main
