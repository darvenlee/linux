#!/bin/bash
curwkdir="$(readlink -f "$(dirname "$BASH_SOURCE")")"
source $curwkdir/deployLogger.sh
if [ $# -lt 2 ]; then
    echo "usage: $0 COORDINATE_HOST COORDINATE_PORT NODES"
    logger_fatal "invalid param, coordinate host and port is required. node list is optional"
    exit 1
fi

#a coordinate ip
COORDINATE_HOST=$1
#a coordinate port
COORDINATE_PORT=$2
#action that call this script.
ACTION=$3
#list of the nodes
NODES=$4

REFRESH_DIR="$curwkdir/../software/refresh/es"
PLUGIN_INSTALL_DIR="$curwkdir/../software/plugin"
PLUGIN_REFRESH_DIR="$REFRESH_DIR/esPlugin"


if [ -z "$NODES" ];then
    NODES='{ "nodes":["data:true"] }'
    logger_info "use default nodes config data:true"
fi

if [ ! -d "${REFRESH_DIR}" ]; then
    logger_error "refresh dir ${REFRESH_DIR} not exist"
    exit 1
fi

if [ "$ACTION" == "refresh" ]; then
    if [ "$(find ${REFRESH_DIR} -type f | grep -v ".txt" | grep -E -v "poisson_recall_*" | wc -l)" -ne 0 ]; then
        # no need to restart, because refresh
        logger_info "No need to active after refresh because there are files [$(find ${REFRESH_DIR} -type f | grep -v \".txt\" | grep -v "poisson_recall_*.zip")] in $REFRESH_DIR, the plugin is already restored when es is restart."
        exit 0
    fi
fi

if [ ! -d "${PLUGIN_REFRESH_DIR}" ]; then
    logger_error "plugin pkg dir ${PLUGIN_REFRESH_DIR} not exist"
    exit 1
fi

for packageName in $(
    cd "${PLUGIN_REFRESH_DIR}"
    ls poisson_recall_*.zip 2>/dev/null
); do
    plugin_id=$(echo ${packageName} | sed -e "s/^poisson_recall_//" -e "s/.zip//")
    retinfo=$(curl -s -XPOST -H Content-Type:application/json http://"${COORDINATE_HOST}":"${COORDINATE_PORT}"/_plugin/install?plugin_id="${plugin_id}" --data-binary "${NODES}")
    echo "${retinfo}" | grep "exception" &>/dev/null
    if [ $? -eq 0 ]; then
        logger_error "Exception during recall plugin ${plugin_id} installation, details: ${retinfo}"
        exit 1
    fi
    logger_info "Successfully active recall plugin ${plugin_id} on ${NODES} through ${COORDINATE_HOST}:${COORDINATE_PORT}"
    mv "${PLUGIN_REFRESH_DIR}/$packageName" "$PLUGIN_INSTALL_DIR"
    logger_info "move plugin $packageName into $PLUGIN_INSTALL_DIR"
done
