#!/bin/bash
curwkdir="`readlink -f $(dirname $BASH_SOURCE)`"
source $curwkdir/deployLogger.sh
if [ $# -lt 4 ]; then
  echo "usage: $0 INDEX_NAME COORDINATE_HOST COORDINATE_PORT SETTINGS";
  echo "warning:we will delete the same indexName first,so first check before do this";
  logger_fatal "invalid ES_USER param. please specify ENV_SYSTEMUSER"
  exit 1
fi

INDEX_NAME=$1
#a coordinate ip
COORDINATE_HOST=$2
#a coordinate port
COORDINATE_PORT=$3
#index mapping
SETTINGS=$4

if [ ! -f $SETTINGS ];then
    logger_fatal "specify $SETTINGS not exists."
    exit 1
fi

logger_info "clear index ${INDEX_NAME} first."
curl -XDELETE -H "Content-Type:application/json" "http://${COORDINATE_HOST}:${COORDINATE_PORT}/${INDEX_NAME}?pretty"

curl -XPUT -H "Content-Type:application/json" "http://${COORDINATE_HOST}:${COORDINATE_PORT}/${INDEX_NAME}?pretty" -d @${SETTINGS}
if [ $? -ne 0 ];then
    logger_error "reCreate index ${INDEX_NAME} failed."
    exit 1
fi

logger_info "reCreate index ${INDEX_NAME} ok."

curl -XGET -H "Content-Type:application/json" "http://${COORDINATE_HOST}:${COORDINATE_PORT}/${INDEX_NAME}/_mapping?pretty"
