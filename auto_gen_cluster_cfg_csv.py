# !/usr/bin/env python
# encoding: utf-8
import os
import sys
import traceback

from csvTool import readCsv
from jsonTool import readJsonfile, writeJsonfile
from pathtool import getConfigPath


def judgeOneLayerKeyValue(key, clusterNodesCfgArray, lineNo):
    if clusterNodesCfgArray[lineNo][0] != key:
        raise RuntimeError(f'item [{clusterNodesCfgArray[lineNo][0]}] need to modify is not equal {key}')
    return clusterNodesCfgArray[lineNo][1]


def judgeSecondLayerKeyValue(key_1, key_2, clusterNodesCfgArray, lineNo):
    itemsArary = clusterNodesCfgArray[lineNo][0].split('#')
    if len(itemsArary) != 2:
        raise RuntimeError(f'{clusterNodesCfgArray[lineNo][0]} layer nums are not equal 2')
    if itemsArary[0] != key_1 or itemsArary[1] != key_2:
        raise RuntimeError(f'items[{itemsArary[0]},{itemsArary[1]}] need to modify are not equal not equal [{key_1},{key_2}]')
    return clusterNodesCfgArray[lineNo][1]


def genVectorCfg(clusterNodesCfgArray, lineNo):
    vectorInfo = dict()
    vectorInfo['idLen'] = int(judgeSecondLayerKeyValue('vectorInfo', 'idLen', clusterNodesCfgArray, lineNo))
    vectorInfo['block.d'] = int(judgeSecondLayerKeyValue('vectorInfo', 'block.d', clusterNodesCfgArray, lineNo + 1))
    vectorInfo['grpcPortOffset'] = int(judgeSecondLayerKeyValue('vectorInfo', 'grpcPortOffset', clusterNodesCfgArray, lineNo + 2))
    vectorInfo['serve_mode'] = 'true' == judgeSecondLayerKeyValue('vectorInfo', 'serve_mode', clusterNodesCfgArray, lineNo + 3).lower()
    vectorInfo['num_workers'] = int(judgeSecondLayerKeyValue('vectorInfo', 'num_workers', clusterNodesCfgArray, lineNo + 4))
    vectorInfo['index_nprobe'] = int(judgeSecondLayerKeyValue('vectorInfo', 'index_nprobe', clusterNodesCfgArray, lineNo + 5))
    vectorInfo['dist_ratio'] = float(judgeSecondLayerKeyValue('vectorInfo', 'dist_ratio', clusterNodesCfgArray, lineNo + 6))
    return vectorInfo


def genPoissonSearchServerInfo(clusterNodesCfgArray, lineNo):
    poissonSearchServerInfo = dict()
    poissonSearchServerInfo['grpcPortOffset'] = int(judgeSecondLayerKeyValue('poissonSearchServerInfo', 'grpcPortOffset', clusterNodesCfgArray, lineNo))
    return poissonSearchServerInfo


def genCommonCfg(clusterNodesCfgArray, lineNo):
    esCommonInfo = dict()
    esCommonInfo['cluster.name'] = judgeSecondLayerKeyValue('esCommonInfo', 'cluster.name', clusterNodesCfgArray, lineNo)
    judgeSecondLayerKeyValue('esCommonInfo', 'path.data', clusterNodesCfgArray, lineNo + 1)
    path_data = []
    for index in range(1, len(clusterNodesCfgArray[lineNo + 1])):
        if len(clusterNodesCfgArray[lineNo + 1][index]) > 0:
            path_data.append(clusterNodesCfgArray[lineNo + 1][index])
    esCommonInfo['path.data'] = path_data
    esCommonInfo['path.logs'] = judgeSecondLayerKeyValue('esCommonInfo', 'path.logs', clusterNodesCfgArray, lineNo + 2)
    return esCommonInfo


def genImportInfo(clusterNodesCfgArray, lineNo):
    esImportInfo = dict()
    esImportInfo['indexName'] = judgeSecondLayerKeyValue('esImportInfo', 'indexName', clusterNodesCfgArray, lineNo)
    esImportInfo['indexSetting'] = judgeSecondLayerKeyValue('esImportInfo', 'indexSetting', clusterNodesCfgArray, lineNo + 1)
    return esImportInfo


def genAuthInfo(clusterNodesCfgArray, lineNo):
    authInfo = dict()
    authInfo['hmac.enabled'] = 'true' == judgeSecondLayerKeyValue('authInfo', 'hmac.enabled', clusterNodesCfgArray, lineNo).lower()
    authInfo['hmac.timeout'] = int(judgeSecondLayerKeyValue('authInfo', 'hmac.timeout', clusterNodesCfgArray, lineNo + 1))
    hmac_me = judgeSecondLayerKeyValue('authInfo', 'hmac.me', clusterNodesCfgArray, lineNo + 2)
    hmac_yu = judgeSecondLayerKeyValue('authInfo', 'hmac.yu', clusterNodesCfgArray, lineNo + 3)
    hmac_he = judgeSecondLayerKeyValue('authInfo', 'hmac.he', clusterNodesCfgArray, lineNo + 4)
    hmac_se = judgeSecondLayerKeyValue('authInfo', 'hmac.se', clusterNodesCfgArray, lineNo + 5)
    hmac_it = judgeSecondLayerKeyValue('authInfo', 'hmac.it', clusterNodesCfgArray, lineNo + 6)

    authInfo['hmac.me'] = hmac_me if len(hmac_me) else '{}'
    authInfo['hmac.yu'] = hmac_yu if len(hmac_yu) else '{}'
    authInfo['hmac.he'] = hmac_he if len(hmac_me) else '{}'
    authInfo['hmac.se'] = hmac_se if len(hmac_se) else '{}'
    authInfo['hmac.it'] = hmac_it if len(hmac_it) else '{}'
    return authInfo


def genHostsCfg(clusterNodesCfgArray, lineNo):
    initHttpPort = int(judgeSecondLayerKeyValue('hosts', 'initHttpPort', clusterNodesCfgArray, lineNo))
    httpPortOffset = int(judgeSecondLayerKeyValue('hosts', 'httpPortOffset', clusterNodesCfgArray, lineNo + 1))
    httpTcpPortOffset = int(judgeSecondLayerKeyValue('hosts', 'httpTcpPortOffset', clusterNodesCfgArray, lineNo + 2))
    loginUser = judgeSecondLayerKeyValue('hosts', 'loginUser', clusterNodesCfgArray, lineNo + 3)
    loginPwd = judgeSecondLayerKeyValue('hosts', 'loginPwd', clusterNodesCfgArray, lineNo + 4)

    roleList = []
    for index in range(1, 4):
        if clusterNodesCfgArray[lineNo + 5][index] == 'master':
            roleList.append('master')
        elif clusterNodesCfgArray[lineNo + 5][index] == 'coordinator':
            roleList.append('coordinator')
        else:
            roleList.append('data')

    hostsInfos = []
    for index in range(lineNo + 6, len(clusterNodesCfgArray)):
        if len(clusterNodesCfgArray[index]) < 4:
            print(f'lineNo[{index}] data format is error, ignore this record')
            continue
        httpPort = initHttpPort - httpPortOffset
        ip = clusterNodesCfgArray[index][0]

        hostinfo = dict()
        hostinfo['ip'] = ip
        hostinfo['port'] = 22
        hostinfo['user'] = loginUser
        hostinfo['password'] = loginPwd
        hostinfo['node.ingest'] = True

        for num in range(3):
            if roleList[num] == 'master':
                hostinfo['node.master'] = True
                hostinfo['node.data'] = False
            elif roleList[num] == 'coordinator':
                hostinfo['node.master'] = False
                hostinfo['node.data'] = False
            else:
                hostinfo['node.master'] = False
                hostinfo['node.data'] = True
            for instanceNum in range(0, int(clusterNodesCfgArray[index][num + 1])):
                httpPort += httpPortOffset
                hostinfo['http.port'] = httpPort
                hostinfo['transport.tcp.port'] = httpPort + httpTcpPortOffset
                hostinfo['node.name'] = 'es-' + roleList[num] + '-' + ip.replace('.', '_') + '-' + str(instanceNum + 1)
                hostsInfos.append(hostinfo.copy())
    return hostsInfos


if len(sys.argv) >= 0:
    try:
        clusterNodesCfgCsvFileName = "cluster_nodes_cfg.csv"
        clusterNodesCfgCsvFile = os.path.join(getConfigPath(), clusterNodesCfgCsvFileName)
        # just for test
        if len(sys.argv) == 2:
            outputfile = sys.argv[1]
        else:
            outputfileName = "cluster_nodes_cfg_template.json"
            outputfile = os.path.join(getConfigPath(), outputfileName)
        clusterNodesCfgArray = readCsv(clusterNodesCfgCsvFile)
        jsondatas = {}
        jsondatas['clusterType'] = judgeOneLayerKeyValue('clusterType', clusterNodesCfgArray, 0)
        jsondatas['esPackage'] = judgeOneLayerKeyValue('esPackage', clusterNodesCfgArray, 1)
        jsondatas['esJDK'] = judgeOneLayerKeyValue('esJDK', clusterNodesCfgArray, 2)
        jsondatas['modulesJDK'] = judgeOneLayerKeyValue('modulesJDK', clusterNodesCfgArray, 3)
        jsondatas['esInstallDir'] = judgeOneLayerKeyValue('esInstallDir', clusterNodesCfgArray, 4)
        jsondatas['esSoftwareDir'] = judgeOneLayerKeyValue('esSoftwareDir', clusterNodesCfgArray, 5)
        jsondatas['systemUser'] = judgeOneLayerKeyValue('systemUser', clusterNodesCfgArray, 6)
        jsondatas['systemGroup'] = judgeOneLayerKeyValue('systemGroup', clusterNodesCfgArray, 7)
        jsondatas['debug'] = judgeOneLayerKeyValue('debug', clusterNodesCfgArray, 8)
        jsondatas['sudoSupport'] = judgeOneLayerKeyValue('sudoSupport', clusterNodesCfgArray, 9)
        jsondatas['multiCpuNum'] = int(judgeOneLayerKeyValue('multiCpuNum', clusterNodesCfgArray, 10))
        jsondatas['reservedPortOffset'] = int(judgeOneLayerKeyValue('reservedPortOffset', clusterNodesCfgArray, 11))

        vectorInfo = genVectorCfg(clusterNodesCfgArray, 12)
        poissonSearchServerInfo = genPoissonSearchServerInfo(clusterNodesCfgArray, 19)
        esCommonInfo = genCommonCfg(clusterNodesCfgArray, 20)
        authInfo = genAuthInfo(clusterNodesCfgArray, 23)
        esImportInfo = genImportInfo(clusterNodesCfgArray, 30)
        jsondatas['multi_node_soft_link'] = judgeOneLayerKeyValue('multi_node_soft_link', clusterNodesCfgArray, 32)
        hosts = genHostsCfg(clusterNodesCfgArray, 33)

        jsondatas['vectorInfo'] = vectorInfo
        jsondatas['poissonSearchServerInfo'] = poissonSearchServerInfo
        jsondatas['esCommonInfo'] = esCommonInfo
        jsondatas['authInfo'] = authInfo
        jsondatas['esImportInfo'] = esImportInfo
        jsondatas['hosts'] = hosts

        writeJsonfile(jsondatas, outputfile)
        print('auto generate default config into %s ok ' % outputfile)
    except Exception as e:
        print((repr(e)))
        traceback.print_tb(e.__traceback__)
        sys.exit(1)
else:
    print('argv num error')
    sys.exit(1)
