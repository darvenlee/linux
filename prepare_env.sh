#!/bin/bash
CURRENT_PATH="`readlink -f $(dirname $BASH_SOURCE)`"
SOFTWARE_PATH="$CURRENT_PATH/../software"
INSTALL_PATH="$SOFTWARE_PATH/temp"
mkdir -p $INSTALL_PATH

function install_PyYAML()
{
    tar -zxvf $SOFTWARE_PATH/PyYAML-5.1.tar.gz -C $INSTALL_PATH
    pushd $INSTALL_PATH/PyYAML-5.1
    python setup.py install
    if [ $? -ne 0 ];then
        return 1
    fi
    
    popd
    return 0
}

function main()
{
    install_PyYAML
    if [ $? -ne 0 ];then
        echo "install PyYAML failed"
        return 1
    fi
}
main $@
