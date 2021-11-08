#!/bin/bash
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 2 ]];then
    logger_error "specify CLUSTERNAME HOST_FICLIENTWKDIR not valid!!"
    exit 1
fi
CLUSTERNAME="$1"
HOST_FICLIENTWKDIR="$2"

ES_USER=`whoami`
ES_GROUP=`whoami`

FICLIENT_COLLECTDIR="$HOST_FICLIENTWKDIR/collect"
function upload_dir()
{
    local filename="$1"
    local TIMESTMP="${filename%%.tar.gz}"

    local logsdir="$FICLIENT_COLLECTDIR/$TIMESTMP"
    rm -rf $logsdir 2>/dev/null
    tar -zxf $FICLIENT_COLLECTDIR/$filename -C $FICLIENT_COLLECTDIR &>/dev/null
    if [ $? -ne 0 ];then
        logger_error "unpack $filename failed"
        return 1
    fi

    # 将zip包解压开
    for zipfile in `cd $logsdir; ls *zip 2>/dev/null`
    do
        unzip -qo $logsdir/$zipfile -d $logsdir
        if [ $? -ne 0 ];then
            logger_error "unpack $zipfile failed"
            return 1
        fi
        rm -f $logsdir/$zipfile
    done

    # 先清空已有目录;防止报冲突
    hdfs dfs -rm -r -f /user/$CLUSTERNAME/$TIMESTMP
    logger_info "clear hdfs of /user/$CLUSTERNAME/$TIMESTMP first...."

    # 整个目录上传
    hdfs dfs -put -d $logsdir /user/$CLUSTERNAME
    if [ $? -ne 0 ];then
        logger_error "put dir $logsdir to hdfs failed"
        return 1
    fi
    rm -rf $logsdir 2>/dev/null
    logger_info "upload $logsdir to hdfs in /user/$CLUSTERNAME ok...."
}

function upload2hdfs()
{
    logger_info "start to upload to hdfs...."
    for packge in `cd $FICLIENT_COLLECTDIR; ls *tar.gz 2>/dev/null`
    do
        upload_dir $packge
        if [ $? -ne 0 ];then
            logger_error "upload $packge to hdfs failed."
            return 1
        fi

        # 上传成功清理掉压缩包
        rm -f $FICLIENT_COLLECTDIR/$packge
        logger_info "upload $packge to hdfs ok."
    done

    logger_info "finish to upload to hdfs...."
    return $?
}

function main()
{
    if [ ! -d $FICLIENT_COLLECTDIR ];then
        return 0
    fi

    source $HOST_FICLIENTWKDIR/bigdata_env
    upload2hdfs
    if [ $? -ne 0 ];then
        return 1
    fi

}
main "$@"
