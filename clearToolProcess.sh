#!/bin/bash
# 清理python进程
if [[ $# -lt 1 ]];then
    echo "specify PYTHON_PROCESSNAME not valid!!"
    exit 1
fi

PYTHON_PROCESSNAME="$1"
function main()
{

    if [ `ps axf | egrep "${PYTHON_PROCESSNAME}" | egrep -v "grep" | wc -l` -gt 1 ];then
        ps axf | egrep "${PYTHON_PROCESSNAME}" | egrep -v "grep" | awk '{print $1}' | xargs kill -9 2>/dev/null
        echo "force kill all ${PYTHON_PROCESSNAME} python process ok."
    fi

    return 0
}
main
