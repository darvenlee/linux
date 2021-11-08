#!/bin/bash
# 1. 远程执行agent目前只支持如下动作ACTION_NAME:
# install/uninstall/start/stop/restart/plugin/refresh/setenv
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [[ $# -lt 7 ]];then
    logger_error "specify ES_INSTALL_DIR ES_INSTANCE_NAME ES_PKG_NAME ACTION_NAME DEBUG_FLAG JDK_PKG not valid!!"
    exit 1
fi

ES_INSTALL_DIR="$1"
ES_DATA_DIR="$2"
ES_INSTANCE_NAME="$3"
ES_PKG_NAME="$4"
ACTION_NAME="$5"
DEBUG_FLAG="$6"
JDK_PKG="$7"
MODULE="$8"
NODE_TYPE="$9"
ENV_LOGS_PATH="${10}"
MULTI_NODE_SOFT_LINK_MODE="${11}"
INSTANCE_NUMBER="${12}"

NEED_RESTART="no"

SOFTWARE_DIR="`cd $curwkdir/..; pwd`"
NODE_DIST_CFG_DIR="$curwkdir/../config"
mkdir -p $ES_DATA_DIR
mkdir -p $ENV_LOGS_PATH
function tryClearEsData()
{
    if [[ "$DEBUG_FLAG" == "yes" ]];then
        logger_info "debug mode, no need to clear $ES_DATA_DIR"
        return 0
    fi

    if [ -d $ES_DATA_DIR ];then
        rm -rf $ES_DATA_DIR
        logger_info "$ES_DATA_DIR clear ok"
    fi
}

function stop_es()
{
    if [ ! -f "$ES_INSTALL_DIR/bin/stop.sh" ];then
        logger_warn "skip stop elasticsearch, no such file: $ES_INSTALL_DIR/bin/stop.sh"
        return 0
    fi
    
    stop_output=$(/bin/bash $ES_INSTALL_DIR/bin/stop.sh 2>&1)
    stop_status=$?
    if [ ${stop_status} -eq 0 ];then
        logger_info "stop $ES_INSTANCE_NAME ok"
    else
        logger_error "stop $ES_INSTANCE_NAME return ${stop_status}, output details: ${stop_output}"
    fi
}

function change_permission()
{
    if [ ! -d $ES_INSTALL_DIR ];then
        return 0
    fi

    chmod -Rf 500 $ES_INSTALL_DIR/bin
    chmod -Rf 500 $ES_INSTALL_DIR/jre/bin 2>/dev/null
    add_read_execute_permission_for_group $ENV_LOGS_PATH
    
    find $ENV_LOGS_PATH -type f -name "*.dat"  | xargs chmod 640 2>/dev/null
    find $ES_INSTALL_DIR/config -type f  | xargs chmod 600 2>/dev/null
    find $ES_INSTALL_DIR/config -type d  | xargs chmod 700 2>/dev/null
    logger_info "refresh permission in $ES_INSTALL_DIR ok"
}

function add_read_execute_permission_for_group()
{
    if [ ! -d $1 ];then
        logger_warn "path $1 to add permission not exist"
        return 0
    fi
    
    local curDir=`cd $1;pwd`
    while [ "$curDir" != "/" ]
    do
        chmod -f g+rx $curDir
        curDir=`dirname $curDir`
    done
}

function check_es_ok()
{
    local loopNum=1
    local maxtime=10

    logger_info "waitting for es working ok...."
    # 最大循环等待10 * 10 s
    while [[ ${loopNum} -lt ${maxtime} ]]; do
        sleep 5
        if [ `ps axf | grep "org.elasticsearch.bootstrap.Elasticsearch" | grep "$ES_INSTALL_DIR" | grep "/bin/java" |  grep -v grep | wc -l` -ne 0 ];then
            logger_info "$ES_INSTALL_DIR for $ES_INSTANCE_NAME started ok."
            return 0
        fi
        logger_info "waitting ${loopNum} times for es starting"
        loopNum=$(( loopNum + 1 ))
        sleep 5
    done

    if [[ ${loopNum} -ge ${maxtime} ]];then
        logger_error "ES instance $ES_INSTALL_DIR not starting yet, perhaps something error!!!!!!"
        return 1
    fi

    return 0
}

function start_es()
{
    if [ ! -d $ES_INSTALL_DIR ];then
        logger_error "dir $ES_INSTALL_DIR not exist"
        return 1
    fi

    if [ `ps axf | grep "org.elasticsearch.bootstrap.Elasticsearch" | grep "$ES_INSTALL_DIR" | grep "/bin/java" |  grep -v grep | wc -l` -ne 0 ];then
        logger_info "$ES_INSTALL_DIR for $ES_INSTANCE_NAME started already"
        return 0
    fi

    cd $ES_INSTALL_DIR
    dos2unix  -q  $ES_INSTALL_DIR/bin/elasticsearch* 2>/dev/null
    dos2unix  -q  $ES_INSTALL_DIR/bin/*.sh 2>/dev/null
    /bin/bash $ES_INSTALL_DIR/bin/start.sh
    if [  $? -ne 0 ];then
        logger_error "$ES_INSTANCE_NAME start failed"
        return 1
    fi

    check_es_ok
    if [  $? -ne 0 ];then
        logger_error "check $ES_INSTANCE_NAME start failed"
        return 1
    fi

    change_permission
    logger_info "start es $ES_INSTANCE_NAME ok"
}

function restart_es()
{
    stop_es
    start_es
    if [  $? -ne 0 ];then
        logger_error "$ES_INSTANCE_NAME restart failed"
        return 1
    fi
    logger_info "$ES_INSTANCE_NAME restart ok"
}

function create_softlink()
{
    local cut_3level=${ES_INSTALL_DIR#/*/*/*/}
    if [ "${cut_3level}" == "${ES_INSTALL_DIR}" ]; then
        return 0
    fi
    local softlink_dir=${ES_INSTALL_DIR%${cut_3level}}
    if [ "${softlink_dir}" == ${ES_INSTALL_DIR} ]; then
        return 0
    fi
    local cluster_dir=`dirname ${ES_INSTALL_DIR}`
    local cluster_dir_name=`basename ${cluster_dir}`

    local softlink_path=${softlink_dir}${cluster_dir_name}
    if [ -d "${softlink_path}" -a ! -L "${softlink_path}" ]; then
        logger_info "${softlink_path} is exists as a directory, cannot create softlink."
        return 0
    fi

    rm -f ${softlink_path}
    ln -s ${cluster_dir} ${softlink_path}
    if [ $? -ne 0 ]; then
        logger_error "create softlink failed: ln -s ${cluster_dir} ${softlink_path}"
        return 1
    fi

    return 0
}

function delete_softlink() {
    local cut_3level=${ES_INSTALL_DIR#/*/*/*/}
    if [ "${cut_3level}" == "${ES_INSTALL_DIR}" ]; then
        return 0
    fi
    local softlink_dir=${ES_INSTALL_DIR%${cut_3level}}
    if [ "${softlink_dir}" == ${ES_INSTALL_DIR} ]; then
        return 0
    fi

    local cluster_dir=`dirname ${ES_INSTALL_DIR}`
    local cluster_dir_name=`basename ${cluster_dir}`

    local softlink_path=${softlink_dir}${cluster_dir_name}
    if [ ! -L "${softlink_path}" ]; then
        return 0
    fi

    local link_path=`readlink ${softlink_path}`
    if [ "${link_path}" == "${cluster_dir}" ]; then
        rm -f ${softlink_path}
    fi

    return 0
}

function create_df_link()
{
    if [ -z "${NODE_TYPE}" ]; then
        logger_error "missing argument [NODE_TYPE]"
        return 1
    fi
    
    local cluster_dir=$(dirname ${ES_INSTALL_DIR})

    # example of data node role soft link conversion:
    # instance_name =  es-data-1_1_1_1-1,  es-1_1_1_1-2,   es-1_1_1_1,   es_1.1.1.1
    #    df_link    =    es-datanode-1,    es-datanode-2,  es-datanode.  es-datanode
    local instance_name=$(basename ${ES_INSTALL_DIR})

    if [ "${MULTI_NODE_SOFT_LINK_MODE}" == "yes"  ]; then
        local df_link_path="${cluster_dir}/es-${NODE_TYPE}-${INSTANCE_NUMBER}"
    else
        local df_link_path="${cluster_dir}/es-${NODE_TYPE}"
    fi
    
    if [ -d "${df_link_path}" -a ! -L "${df_link_path}" ]; then
        logger_warn "${df_link_path} exists as a directory, cannot create df link."
        return 0
    fi
    
    rm -f ${df_link_path}
    ln -s ${ES_INSTALL_DIR} ${df_link_path}
    if [ $? -ne 0 ]; then
        logger_info "df link ${df_link_path} already exists when doing ln -s ${ES_INSTALL_DIR} ${df_link_path}"
        return 0
    fi    
}

function delete_df_link()
{
    if [ -z "${NODE_TYPE}" ]; then
        logger_error "missing argument [NODE_TYPE]"
        return 1
    fi
    
    local cluster_dir=$(dirname ${ES_INSTALL_DIR})

    local instance_name=$(basename ${ES_INSTALL_DIR})

    if [ "${MULTI_NODE_SOFT_LINK_MODE}" == "yes"  ]; then
        local df_link_path="${cluster_dir}/es-${NODE_TYPE}-${INSTANCE_NUMBER}"
    else
        local df_link_path="${cluster_dir}/es-${NODE_TYPE}"
    fi

    if [ ! -L "${df_link_path}" ]; then
        return 0
    fi
    
    local link_path=$(readlink ${df_link_path})
    if [ "${link_path}" == "${ES_INSTALL_DIR}" ]; then
        rm -f ${df_link_path}
    fi

    return 0
}


function create_logs_soflink()
{
    if [ -z "${NODE_TYPE}" ]; then
        logger_error "missing argument [NODE_TYPE]"
        return 1
    fi
    
    local logs_dir=$(dirname ${ENV_LOGS_PATH})
    local instance_name=$(basename ${ENV_LOGS_PATH})
    if [ "${MULTI_NODE_SOFT_LINK_MODE}" == "yes"  ]; then
        local logs_link_path="${logs_dir}/es-${NODE_TYPE}-${INSTANCE_NUMBER}"
    else
        local logs_link_path="${logs_dir}/es-${NODE_TYPE}"
    fi
    
    if [ -d "${logs_link_path}" -a ! -L "${logs_link_path}" ]; then
        logger_warn "${logs_link_path} exists as a directory, cannot create logs link."
        return 0
    fi
    
    rm -f ${logs_link_path}
    ln -s ${ENV_LOGS_PATH} ${logs_link_path}
    if [ $? -ne 0 ]; then
        logger_info "logs softlink ${logs_link_path} already exists when doing ln -s ${ENV_LOGS_PATH} ${logs_link_path}"
        return 0
    fi    
}

function delete_logs_soflink()
{
    if [ -z "${NODE_TYPE}" ]; then
        logger_error "missing argument [NODE_TYPE]"
        return 1
    fi
    
    local logs_dir=$(dirname ${ENV_LOGS_PATH})
    local instance_name=$(basename ${ENV_LOGS_PATH})
    if [ "${MULTI_NODE_SOFT_LINK_MODE}" == "yes"  ]; then
        local logs_link_path="${logs_dir}/es-${NODE_TYPE}-${INSTANCE_NUMBER}"
    else
        local logs_link_path="${logs_dir}/es-${NODE_TYPE}"
    fi

    if [ ! -L "${logs_link_path}" ]; then
        return 0
    fi
    
    local link_path=$(readlink ${logs_link_path})
    if [ "${link_path}" == "${ENV_LOGS_PATH}" ]; then
        rm -f ${logs_link_path}
    fi

    return 0
}

function uninstall_es()
{
    stop_es
    # 不提高权限删除不掉
    chmod +wx -Rf $ES_INSTALL_DIR 2>/dev/null
    rm -rf $ES_INSTALL_DIR 2>/dev/null

    chmod +wx -Rf ${ES_INSTALL_DIR}_LastVersion 2>/dev/null
    rm -rf ${ES_INSTALL_DIR}_LastVersion 2>/dev/null
    
    chmod +wx -Rf $SOFTWARE_DIR
    rm -rf $SOFTWARE_DIR/plugin/*  2>/dev/null
    rm -rf $SOFTWARE_DIR/config/es  2>/dev/null
    rm -rf ${SOFTWARE_DIR}/refresh/* 2>/dev/null
    delete_softlink
    delete_df_link
    delete_logs_soflink
    tryClearEsData
    logger_info "$ES_INSTALL_DIR uninstall ok"
}

function plugin_es()
{
    pluginDir="$1"
    if [ -z "$pluginDir" ];then
        pluginDir="$SOFTWARE_DIR/plugin"
        logger_info "use default es plugin $SOFTWARE_DIR/plugin"
    fi

    if [ ! -d $pluginDir ];then
        logger_error "es package $pluginDir not exist"
        return 1
    fi

    for packageName in `cd "$pluginDir"; ls *.zip 2>/dev/null`
    do
        logger_info "begin install plugin $packageName"

        tempUnpackDir=$pluginDir/unpack_plugin
        rm -rf $tempUnpackDir 2>/dev/null
        mkdir -p $tempUnpackDir
        unzip -qo $pluginDir/$packageName -d $tempUnpackDir
        if [ $? -ne 0 ];then
            logger_error "unzip package $pluginDir/$packageName failed"
            return 1
        fi

        if [ ! -f $tempUnpackDir/plugin-descriptor.properties ];then
            logger_error "invalid plugin package $packageName"
            return 1
        fi

        dos2unix -q $tempUnpackDir/*.properties 2>/dev/null

        # 根据配置文件读取plugin的包名字
        # 识别recall_plugin或plugin，进行不同处理
        echo "$packageName" | grep -E "^poisson_recall_.+"
        if [ $? -eq 0 ]
        then
            is_recall_plugin="yes"
            targetPluginDir="recall_plugins"

            pluginName=`cat $tempUnpackDir/plugin-descriptor.properties | grep "^name=" | awk -F "=" '{print $2}'`
            pluginVersion=`cat $tempUnpackDir/plugin-descriptor.properties | grep "^version=" | awk -F "=" '{print $2}'`
            if [ "$pluginName" == "" ] || [ "$pluginVersion" == "" ];then
                logger_error "invalid plugin-descriptor.properties in package $packageName"
                return 1
            fi

            if [[ $packageName != poisson_recall_${pluginName}_${pluginVersion}.zip ]]; then
                logger_error "plugin ${packageName} is recognized as a poisson recall plugin, but name of zip should be poisson_recall_<plugin_name>_<pluginVersion>.zip where name is $pluginName and version is $pluginVersion in plugin-descriptor"
                return 1
            fi

            plugin_dir_name="poisson_recall_${pluginName}_${pluginVersion}"
            logger_info "plugin ${packageName} is recognized as a poisson recall plugin, will be moved to dir recall_plugins"
        else
            is_recall_plugin="no"
            targetPluginDir="plugins"
            pluginName=`cat $tempUnpackDir/plugin-descriptor.properties | grep "^name=" | awk -F "=" '{print $2}'`
            if [ "$pluginName" == "" ];then
                logger_error "invalid plugin-descriptor.properties in package ${packageName}"
                return 1
            fi
            plugin_dir_name="$pluginName"
            logger_info "plugin ${packageName} is recognized as a normal es plugin, will be moved to dir plugins"

            NEED_RESTART="yes"
            logger_info "need to restart after refresh because refreshed a normal es plugin"
        fi

        # 准备plugin目的安装文件夹
        if [ -d  $ES_INSTALL_DIR/config/$plugin_dir_name ];then
            logger_info "plugin ${plugin_dir_name} already installed in $ES_INSTALL_DIR, clear first."
            rm -rf "${ES_INSTALL_DIR}/${targetPluginDir}/${plugin_dir_name}"
            rm -rf "${ES_INSTALL_DIR}/config/${plugin_dir_name}"
        fi

        mkdir -p ${ES_INSTALL_DIR}/${targetPluginDir}/${plugin_dir_name}
        mkdir -p ${ES_INSTALL_DIR}/config/${plugin_dir_name}

        # 拷贝插件到es目标位置
        mv ${tempUnpackDir}/config/* ${ES_INSTALL_DIR}/config/${plugin_dir_name} 2>/dev/null
        mv ${tempUnpackDir}/* ${ES_INSTALL_DIR}/${targetPluginDir}/${plugin_dir_name} 2>/dev/null
        rm -rf ${tempUnpackDir}
        logger_info "install plugin ${plugin_dir_name} of ${packageName} ok"
    done

    logger_info "install all plugin ok"
}

function refresh_esCfg()
{
    if [ ! -d $ES_INSTALL_DIR ];then
        logger_info "dir $ES_INSTALL_DIR not exist"
        return 0
    fi

    if [ ! -d ${SOFTWARE_DIR}/refresh/esConfig ];then
        logger_info "dir ${SOFTWARE_DIR}/refresh/esConfig not exist, no need to refresh"
        return 0
    fi

    if [ `find ${SOFTWARE_DIR}/refresh/esConfig -type f | grep -v ".txt" | wc -l` -ne 0 ]
    then
        mv ${SOFTWARE_DIR}/refresh/esConfig/* $ES_INSTALL_DIR/config 2>/dev/null
        logger_info "refresh jar to ${ES_INSTALL_DIR}/config ok"

        NEED_RESTART="yes"
        logger_info "need to restart after refresh because refreshed a es config"
    fi
}

function refresh_esJar()
{
    if [ ! -d $ES_INSTALL_DIR ];then
        logger_info "dir $ES_INSTALL_DIR not exist"
        return 0
    fi

    if [ ! -d ${SOFTWARE_DIR}/refresh/esJar ];then
        logger_info "dir ${SOFTWARE_DIR}/refresh/esJar not exist, no need to refresh"
        return 0
    fi

    if [ `find ${SOFTWARE_DIR}/refresh/esJar -type f | grep -v ".txt" | wc -l` -ne 0 ]
    then
        mv ${SOFTWARE_DIR}/refresh/esJar/*.jar $ES_INSTALL_DIR/lib 2>/dev/null
        logger_info "refresh jar to $ES_INSTALL_DIR/lib ok"

        NEED_RESTART="yes"
        logger_info "need to restart after refresh because refreshed a es jar"
    fi
}

function refresh_plugin()
{
    if [ ! -d $ES_INSTALL_DIR ];then
        logger_error "dir $ES_INSTALL_DIR not exist"
        return 1
    fi

    if [ ! -d ${SOFTWARE_DIR}/refresh/esPlugin ];then
        logger_info "dir ${SOFTWARE_DIR}/refresh/esPlugin not exist, no need to refresh"
        return 0
    fi

    plugin_es "${SOFTWARE_DIR}/refresh/esPlugin"
    if [ $? -ne 0 ];then
        logger_error "refresh plugin failed because plugin_es failed"
        return 1
    fi

    logger_info "refresh plugin to $ES_INSTALL_DIR/lib ok"
}

function refresh_es()
{
    local refresh_pkg_name="es-refresh.tar.gz"
    if [ ! -f ${SOFTWARE_DIR}/$refresh_pkg_name ];then
        logger_info "dir ${SOFTWARE_DIR}/$refresh_pkg_name not exist, not need refresh"
        return 0
    fi

    rm -rf ${SOFTWARE_DIR}/refresh 2>/dev/null
    tar -zxf ${SOFTWARE_DIR}/$refresh_pkg_name -C ${SOFTWARE_DIR}
    if [  $? -ne 0 ];then
        logger_error "unpack package ${SOFTWARE_DIR}/$refresh_pkg_name for $ES_INSTANCE_NAME failed"
        return 1
    fi

    refresh_esCfg
    if [ $? -ne 0 ];then
        return 1
    fi

    refresh_esJar
    if [ $? -ne 0 ];then
        return 1
    fi

    refresh_plugin
    if [ $? -ne 0 ];then
        return 1
    fi

    logger_info "refresh es to $ES_INSTALL_DIR ok."

    if [ "$NEED_RESTART" == "yes" ]; then
        restart_es
        if [ $? -ne 0 ];then
            return 1
        fi
        logger_info "restart es ok after refresh es pkgs..."
    fi

    rm -rf ${SOFTWARE_DIR}/$refresh_pkg_name
}

function refresh_recall_es()
{
    local install_pkg_name="es-recall-install.tar.gz"

    if [ ! -d "$ES_INSTALL_DIR" ];then
        logger_error "dir $ES_INSTALL_DIR not exist"
        return 1
    fi

    if [ ! -f "$SOFTWARE_DIR/$install_pkg_name" ];then
        logger_info "dir $SOFTWARE_DIR/$install_pkg_name not exist, not need refresh recall plugins"
        return 0
    fi

    rm -rf "$SOFTWARE_DIR/recall_install" 2>/dev/null
    tar -zxf "$SOFTWARE_DIR/$install_pkg_name" -C "$SOFTWARE_DIR"
    if [  $? -ne 0 ];then
        logger_error "unpack package $SOFTWARE_DIR/$install_pkg_name for $ES_INSTANCE_NAME failed"
        return 1
    fi

    rm -rf "${SOFTWARE_DIR:?}/$install_pkg_name" 2>/dev/null

    if [ ! -d "$SOFTWARE_DIR/recall_install" ];then
        logger_error "install dir $SOFTWARE_DIR/recall_install not exist"
        return 1
    fi

    plugin_es "$SOFTWARE_DIR/recall_install"
    if [ $? -ne 0 ];then
        logger_error "refresh recall plugin failed because plugin_es failed"
        return 1
    fi

    logger_info "install recall plugin to $ES_INSTALL_DIR/recall_plugins ok"
}

function grant_jdk_security_policy_for_snippet() {
    if [ "$MODULE" = "snippet" ]; then
        hostIp=`cd $ES_INSTALL_DIR; cat config/elasticsearch.yml | grep -E '^network.host' | awk '{print $2}'`
        httpPort=`cd $ES_INSTALL_DIR; cat config/elasticsearch.yml | grep -E '^http.port' | awk '{print $2}'`
        defaultPolicyFile="$ES_INSTALL_DIR/jre/lib/security/default.policy"

        sed -i '/grant {/a\\permission java.lang.RuntimePermission "loadLibrary.*";' "$defaultPolicyFile"
        sed -i '/grant {/a\\permission java.net.SocketPermission "'"$hostIp:$httpPort"'", "connect,resolve";' "$defaultPolicyFile"
    fi
}

function install_es()
{
    local config_pkg_name="esconfig.tar.gz"
    if [ ! -f $SOFTWARE_DIR/$ES_PKG_NAME ];then
        logger_error "es package $SOFTWARE_DIR/$ES_PKG_NAME not exist"
        return 1
    fi

    if [ ! -f ${SOFTWARE_DIR}/config/$config_pkg_name ];then
        logger_error "es config ${SOFTWARE_DIR}/config/$config_pkg_name not exist"
        return 1
    fi

    tar -zxf $SOFTWARE_DIR/$ES_PKG_NAME -C $SOFTWARE_DIR
    if [  $? -ne 0 ];then
        logger_error "unpack $SOFTWARE_DIR/$ES_PKG_NAME failed"
        return 1
    fi
    logger_info "unpack $ES_PKG_NAME into $SOFTWARE_DIR ok"

    # 动态获取下解压后的目录名
    unpackdir=`cd $SOFTWARE_DIR; ls -d index-server* | egrep -v "tar.gz"`
    if [ $? -ne 0 ];then
        unpackdir=`cd $SOFTWARE_DIR; ls -d elasticsearch-* | egrep -v "tar.gz"`
        if [ $? -ne 0 ];then
            logger_error "unpack package to $SOFTWARE_DIR/$unpackdir failed, can not find valid indexer-server or elasticsearch dir"
            return 1
        fi
    fi
    logger_info "current package version is $unpackdir"

    if [ ! -d $SOFTWARE_DIR/$unpackdir ];then
        logger_error "unpackdir ${unpackdir} not exists"
        return 1
    fi

    if [ ! -f $SOFTWARE_DIR/$unpackdir/jre/bin/java ];then
        logger_info "$ES_PKG_NAME do not contains java, use $SOFTWARE_DIR/$JDK_PKG"
        tar -zxf $SOFTWARE_DIR/$JDK_PKG -C $SOFTWARE_DIR/$unpackdir
        if [  $? -ne 0 ];then
            logger_error "unpack $SOFTWARE_DIR/$JDK_PKG into $SOFTWARE_DIR/$unpackdir failed"
            return 1
        fi
        logger_info "unpack $JDK_PKG into $SOFTWARE_DIR/$unpackdir ok"

        jdkname=`cd $SOFTWARE_DIR/$unpackdir; ls -d jre* | egrep -v "tar.gz"`
        mv $SOFTWARE_DIR/$unpackdir/$jdkname $SOFTWARE_DIR/$unpackdir/jre
    fi

    # 先尝试停止旧版本
    if [ -d $ES_INSTALL_DIR ];then
        stop_es
        # 后面这里改成软连接;可以方便回滚操作
        rm -rf ${ES_INSTALL_DIR}_LastVersion 2>/dev/null
        mv $ES_INSTALL_DIR  ${ES_INSTALL_DIR}_LastVersion 2>/dev/null
        logger_info "stop and backup last version into ${ES_INSTALL_DIR}_LastVersion ok"
    fi

    mkdir -p $ES_INSTALL_DIR
    error=$(mv $SOFTWARE_DIR/$unpackdir/*  $ES_INSTALL_DIR/ 2>&1)
    if [  $? -ne 0 ];then
        logger_error "$ES_INSTANCE_NAME deploy package $ES_PKG_NAME failed, error msg ${error}"
        return 1
    fi
    logger_info "mv $SOFTWARE_DIR/$unpackdir to $ES_INSTALL_DIR ok"
    rm -rf $SOFTWARE_DIR/$unpackdir 2>/dev/null

    # es配置文件直接解压覆盖到es工作目录
    tar -zxf ${SOFTWARE_DIR}/config/$config_pkg_name -C $ES_INSTALL_DIR
    if [  $? -ne 0 ];then
        logger_error "$ES_INSTANCE_NAME refresh config files failed"
        return 1
    fi

    grant_jdk_security_policy_for_snippet

    create_softlink
    if [ $? -ne 0 ]; then
        logger_error "create softlink of $ES_INSTANCE_NAME failed!!"
    fi
    
    create_df_link
    if [ $? -ne 0 ]; then
        logger_warn"create df link of $ES_INSTANCE_NAME failed!!"
    fi
    
    create_logs_soflink
    if [ $? -ne 0 ]; then
        logger_warn "create logs softlink of $ES_INSTANCE_NAME failed!!"
    fi

    tryClearEsData
    logger_info "install $ES_INSTANCE_NAME package ok"
}

function setenv_es()
{
    if [ `ps axf | grep prepareNodeEnv.sh | grep -v grep | wc -l` -eq 0 ];then
        bash $curwkdir/prepareNodeEnv.sh $ES_DATA_DIR
        return $?
    else
        logger_info "execute prepare node env already."
    fi
}

# 返回 0表示权限正常
function check_path_permission
{
    local chekbakpath="$1"
    if [ ! -d $chekbakpath ];then
        logger_error " backup path $chekbakpath not exist"
        return 1
    fi

    if [ ! -r $chekbakpath ];then
        logger_error "  backup path $chekbakpath,  read permission deny"
        return 1
    fi

    if [ ! -w $chekbakpath ];then
        logger_error "  backup path $chekbakpath, write permission deny"
        return 1
    fi

    return 0
}

function main()
{
    logger_info "begin to ${ACTION_NAME} $ES_INSTANCE_NAME...."
    check_path_permission "$SOFTWARE_DIR"
    if [ $? -ne 0 ];then
        exit 1
    fi

    if [ "${NODEJS_HOME}" == "" ];then
        bash $curwkdir/installPm2.sh
        if [ $? -ne 0 ];then
            logger_error "install pm2 failed"
        fi
    fi

    bash $curwkdir/isNeedDeploy.sh $NODE_DIST_CFG_DIR "es"
    if [ $? -eq 0 ];then
        # 防止各种环境问题;直接就使用版本中自带的jre
        export JAVA_HOME="$ES_INSTALL_DIR/jre"
        ${ACTION_NAME}_es
        if [ $? -ne 0 ];then
            logger_error "$ES_INSTANCE_NAME $ACTION_NAME failed"
            exit 1
        fi
    else
        logger_info "no need to execute action $ACTION_NAME on $ES_INSTANCE_NAME according to deploy.properties under software/config"
    fi

    logger_info "end to ${ACTION_NAME} $ES_INSTANCE_NAME...."
}
main $@
