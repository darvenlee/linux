#!/usr/bin/env python
# -*- coding:utf-8 -*-
# 根据cfg.json配置,在临时db中升级AC数据并导出
# 其中数据的导出会使用多进程并发
import argparse
import os
import time
import traceback
import subprocess
import json

import esCfgs
import pathtool
import logging
import signal
import sys
import yamlTool
import taskExecutor

FORMAT = '%(asctime)-15s %(message)s'
LOGFILEPATH = pathtool.getLogPath()
logging.basicConfig(filename=LOGFILEPATH, format=FORMAT)
logger = logging.getLogger('deploy')
logger.setLevel(logging.INFO)
LOCAL_LOOPBACK_IP = '127.0.0.1'


def parse_config():
    parser = argparse.ArgumentParser(description="deploy indexer cluster automatic")
    parser.add_argument('--action', type=str, default='default',
                        help='specify an action step to execute in indexer cluster, default choose actions default')
    parser.add_argument('--node', type=str, default='all',
                        help='specify indexer node names to execute action you wanted. eg:--node node1,node2 '
                             ';default value is all, means choose all nodes. all-master means choose all master nodes; '
                             'all-data means choose all data nodes. all-coordinator means choose all coordinator nodes')
    return parser.parse_args()


def printNodesList():
    escfgIns = esCfgs.CClusterNodeCfg()
    print("\r\n=========All nodes===========")
    print(','.join(escfgIns.getAllNodes()))
    print("\r\n=========master nodes===========")
    print(','.join(escfgIns.getAllMasterNodes()))
    print("\r\n=========data nodes===========")
    print(','.join(escfgIns.getAllDataNodes()))
    print("\r\n=========coordinator nodes===========")
    print(','.join(escfgIns.getAllCoordinatorNodes()))

def checkUninstall(nodes):
    escfgIns = esCfgs.CClusterNodeCfg()
    if escfgIns.isDebug() != "yes":
        print("\r\nUninstall both the indexer software And indexer data of these nodes:")
    else:
        print("\r\nUninstall only the indexer software of these nodes, remaining indexer data:")

    print(','.join(nodes))
    inputstr = input("\r\nplease check carefully, Then make sure you want to continue? YES/NO:")
    inputstr = str(inputstr).strip().upper()
    if inputstr == "YES":
        print('\r\ncontinue to uninstall...')
        return True
    else:
        print('\r\ngive up to uninstall...')
        return False


def getActions(params):
    supprotActions = ["precheck", "prepare", "setenv", "refresh", "refresh_recall", "install", "uninstall", "start", "stop", "plugin",
                      "restart", "index", "default", "help", "expand", "nodeInfo"]
    defaultList = ["precheck", "prepare", "setenv", "install", "plugin", "start"]
    specifyActions = []
    actionStr = str(params.action).strip()
    if actionStr not in supprotActions:
        print(("arg error, please specify action in: " + ','.join(supprotActions)))
        sys.exit(1)
    elif actionStr == "nodeInfo":
        printNodesList()
        sys.exit(0)
    elif actionStr == "default":
        specifyActions = defaultList.copy()
    elif actionStr == "expand":
        checkExpandPara(params)
        # expand action is similar to execute default actions to new expand nodes
        specifyActions = defaultList.copy()
    elif actionStr == "uninstall":
        if not checkUninstall(getActionNodes(params)):
            sys.exit(0)
        else:
            specifyActions.append(actionStr)
    elif actionStr == "help":
        print("====================USAGE INFO========================")
        print(("The default actions are: " + ','.join(defaultList)))
        print(("OR choose a single action in: " + ','.join(supprotActions)))
        print("[precheck]: pre check system configurations on indexer cluster nodes, eg: sudo permission. "
              "Support for specifying --node at the same time")
        print("[prepare]: auto generate indexer configurations and indexer packages, then deliver to all indexer cluster nodes. "
              "Support for specifying --node at the same time")
        print("[setenv]: set system env on indexer cluster nodes, eg: sysctl.conf. "
              "Support for specifying --node at the same time")
        print("[refresh]: refresh indexer jars or plugin or es-configurations(jvm.options/yaml) to all indexer cluster nodes,"
              " include restart. Support for specifying --node at the same time")
        print("[install]: install indexer and depend software on indexer cluster nodes. "
              "Support for specifying --node at the same time")
        print("[plugin]: install indexer plugins on indexer cluster nodes."
              " Support for specifying --node at the same time")
        print("[refresh_recall]: refresh poisson recall plugin to all indexer cluster nodes, without any restart. "
              "Support for specifying --node at the same time")
        print("[start]: start indexer on all indexer cluster nodes."
              " Support for specifying --node at the same time")
        print("[stop]: stop indexer on all indexer cluster nodes.(Please use 'python3 deployModules --module optools --action stop' to stop the monitor first)"
              " Support for specifying --node at the same time")
        print("[restart]: restart indexer on all indexer cluster nodes."
              " Support for specifying --node at the same time")
        print("[uninstall]: uninstall indexer on all indexer cluster nodes, remaining data and logs dir."
              " Support for specifying --node at the same time")
        print("[default]: deploy indexer by default actions:" + ','.join(defaultList) +
              ". Support for specifying --node at the same time")
        print("[expand]: expand and deploy indexer new data-node by default actions:" + ','.join(defaultList) +
              ". Must specifying --node at the same time")
        print("[nodeInfo]: print detail infos about all cluster nodes.")
        print("[index]: create index in indexer cluster.")
        print("[help]: show detail help info")
        print("====================USAGE INFO========================")
        sys.exit(0)
    else:
        specifyActions.append(actionStr)
    return specifyActions


def checkExpandPara(params):
    nodename = str(params.node).strip()
    actionName = str(params.action).strip()
    if actionName == "expand":
        if nodename == "all" or len(nodename) == 0:
            print("must specify valid nodes name to be expanded")
            sys.exit(1)


def getActionNodes(params):
    nodes = []
    escfgIns = esCfgs.CClusterNodeCfg()
    nodename = str(params.node).strip()
    specifynodes = nodename.split(",")
    if nodename == "all":
        nodes = escfgIns.getAllNodes().copy()
    elif nodename == "all-master":
        nodes = escfgIns.getAllMasterNodes().copy()
    elif nodename == "all-data":
        nodes = escfgIns.getAllDataNodes().copy()
    elif nodename == "all-coordinator":
        nodes = escfgIns.getAllCoordinatorNodes().copy()
    else:
        for speficy in specifynodes:
            if speficy not in escfgIns.getAllNodes():
                print(("please specify valid node in: " + ','.join(escfgIns.getAllNodes())))
                sys.exit(1)
            else:
                nodes.append(speficy)
    return nodes

def force_clear_process():
    args = [os.path.basename(__file__)]
    shellfile = os.path.join(pathtool.getShellscriptPath(), 'clearToolProcess.sh ')
    shellcmd = '/bin/bash ' + shellfile + ' '.join(args)
    subprocess.call(shellcmd, shell=True)


def graceful_quit(signal_num, frame):
    print("graceful stop tool by CTRL+C, please waiting for few seconds....")
    print(("signal_num %s %s " % (signal_num, frame)))
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    force_clear_process()
    sys.exit(1)


class CDeployES:
    def __init__(self):
        self.nodeCfg = esCfgs.CClusterNodeCfg()

    def timestamp(self):
        return time.asctime(time.localtime(time.time()))

    def getZenUnicastHosts(self):
        nodeList = []
        for node in self.nodeCfg.getAllNodes():
            if self.nodeCfg.isNodeMaster(node):
                nodeList.append(self.nodeCfg.getIp(node) + ":" + str(self.nodeCfg.getTransportTcpPort(node)))

        return nodeList

    def getInitMasterHosts(self):
        nodeList = []
        for node in self.nodeCfg.getAllNodes():
            if self.nodeCfg.isNodeMaster(node):
                nodeList.append(node)

        return nodeList

    def refreshEsCfg(self, node, action, cluster_type):
        distInst = esCfgs.CdeployDistCfg(node)
        if action == 'refresh':
            pathtool.genEsNodeRefreshConfig(node)
            distInst.refreshMoudle('es')
            if not os.path.exists(yamlTool.getTemplateYAML(node, self.nodeCfg.getBuildType())):
                print(("refresh indexer yml no specified in %s " % pathtool.getESRefreshConfigPath()))
                return
        else:
            if self.nodeCfg.isNodeData(node):
                node_role = "invert_data"
            elif self.nodeCfg.isNodeMaster(node):
                node_role = "invert_master"
            else:
                node_role = "invert_coordinator"

            pathtool.genEsNodeConfig(node, node_role, cluster_type)
            distInst.refreshMoudle('es')

        templatefile = yamlTool.chooseTemplateYAML(node, self.nodeCfg.getBuildType())
        dstfile = os.path.join(pathtool.getESNodeConfigPath(node), 'elasticsearch.yml')
        yamldatas = yamlTool.readYamlfile(templatefile)
        yamldatas['cluster.name'] = self.nodeCfg.getClusterName()
        yamldatas['path.data'] = self.nodeCfg.getNodePathData(node)
        yamldatas['path.logs'] = self.nodeCfg.getNodePathLogs(node)

        if 'offline' == self.nodeCfg.getBuildType():
            # only poisson indexer supported these options in elasticsearch.yml
            yamldatas['load.path'] = self.nodeCfg.getNodePathLoad(node)

            if self.nodeCfg.getClusterType() == 'vector':
                yamldatas['vector.block.d'] = self.nodeCfg.getVectorBlockD()
                yamldatas['vector.grpc.port'] = self.nodeCfg.getTransportTcpPort(
                    node) + self.nodeCfg.getVectorGrpcPortOffset()
                yamldatas['vector.grpc.serve_mode'] = self.nodeCfg.getVectorServeMode()
                yamldatas['vector.grpc.num_workers'] = self.nodeCfg.getVectorNumWorkers()
                yamldatas['vector.dist_ratio'] = self.nodeCfg.getVectorDistRatio()
                yamldatas['node.realtime'] = self.nodeCfg.isNodeRealTime(node)

            yamldatas['poisson.search.service.start.port'] = self.nodeCfg.getTransportTcpPort(
                node) + self.nodeCfg.getPoissonSearchServerGrpcPortOffset()

            auth_infos = self.nodeCfg.getAuthInfo()
            if auth_infos is not None:
                for auth_key in auth_infos:
                    yamldatas[auth_key] = auth_infos[auth_key]

        yamldatas['transport.tcp.port'] = self.nodeCfg.getTransportTcpPort(node)
        yamldatas['http.port'] = self.nodeCfg.getHttpPort(node)
        yamldatas['network.host'] = self.nodeCfg.getIp(node)
        yamldatas['network.bind_host'] = self.nodeCfg.getIp(node) + "," + LOCAL_LOOPBACK_IP
        yamldatas['node.name'] = node
        yamldatas['node.data'] = self.nodeCfg.isNodeData(node)
        yamldatas['node.master'] = self.nodeCfg.isNodeMaster(node)
        yamldatas['node.ingest'] = self.nodeCfg.isNodeIngest(node)
        yamldatas['discovery.zen.ping.unicast.hosts'] = self.getZenUnicastHosts()
        yamldatas['cluster.initial_master_nodes'] = self.getInitMasterHosts()
        yamlTool.writeYamlfile(yamldatas, dstfile)

    def genEsScriptEnv(self, node):
        envmap = dict()
        envmap['ENV_SYSTEMUSER'] = self.nodeCfg.getSystemUser()
        envmap['ENV_SYSTEMGROUP'] = self.nodeCfg.getSystemGroup()
        envmap['ENV_PASSWORD'] = self.nodeCfg.getPassword(node)
        envmap['ENV_NODENAME'] = node
        envmap['ENV_ISDEBUG'] = self.nodeCfg.isDebug()
        envmap['ENV_JDK'] = self.nodeCfg.getEsJdkPkg()
        envmap['ENV_LOGS_PATH'] = self.nodeCfg.getNodePathLogs(node)
        return envmap

    def getDatafilelist(self):
        indexRanges = self.nodeCfg.getImportRange()
        filelist = []
        for datafile in os.listdir(self.nodeCfg.getImportDataDir()):
            filepath = os.path.join(self.nodeCfg.getImportDataDir(), datafile)
            if os.path.isdir(filepath):
                continue

            pos = datafile.find(self.nodeCfg.getEsDataSuffix())
            if pos == -1:
                continue
            # all data file should named likes: [num][fileSuffix]
            # eg: 1kafka_data 2kafka_data
            dataindex = int(datafile[:pos])
            if dataindex < indexRanges[0] or dataindex > indexRanges[1]:
                continue
            filelist.append(filepath)
        return filelist

    def importData(self, nodes):
        filelists = self.getDatafilelist()
        taskmap = dict()
        for i in range(0, len(filelists)):
            nodeName = nodes[i % len(nodes)]
            argmap = dict()
            filepath = filelists[i]
            argmap['filePath'] = filepath
            argmap['node'] = nodeName
            argmap['ip'] = self.nodeCfg.getIp(nodeName)
            argmap['httpPort'] = self.nodeCfg.getHttpPort(nodeName)
            argmap['indexName'] = self.nodeCfg.getIndexName()
            argmap['sendPerLines'] = self.nodeCfg.getSendPerline()
            print(("add process importData task for %s " % os.path.basename(filepath)))
            logger.info("add process importData task for %s of file %s", nodeName, os.path.basename(filepath))
            taskmap[os.path.basename(filepath)] = argmap

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.sendRequst)

    def deployNode(self, action, nodes):
        logger.info("start to do %s in Nodes", action)
        print(("%s start to deployNode, please waitting for 15-30 minutes patiently.." % (self.timestamp())))
        shellfile = os.path.join(pathtool.getShellscriptPath(), 'deployNode.sh ')
        taskmap = dict()
        for node in nodes:
            hostinfo = self.nodeCfg.getIp(node) + '@' + str(self.nodeCfg.getPort(node))
            args = [self.nodeCfg.getEsPackage(), self.nodeCfg.getNodeSoftwareDir(node),
                    self.nodeCfg.getNodeInstallDir(node), self.nodeCfg.getNodePathData(node), hostinfo, action,
                    self.nodeCfg.getEsLogSecModule(), self.nodeCfg.getNodeType(node),
                    self.nodeCfg.getIsMultipleSoftLinkMode(), str(self.nodeCfg.getInstanceNumber(node))]
            cmdstr = shellfile + ' '.join(args)
            argmap = dict()
            argmap['cmdstr'] = cmdstr
            argmap['sysuser'] = self.nodeCfg.getSystemUser()
            argmap['envmap'] = self.genEsScriptEnv(node)
            print(("add process %s deployNode task for node %s: %s " % (action, node, hostinfo)))
            logger.info("add process deployNode task for %s", node)
            taskmap[node] = argmap

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.executeCmd)

    def activeRecallPlugin(self, action, nodes):
        logger.info("start to active recall plugins")
        shellfile = os.path.join(pathtool.getShellscriptPath(), 'activeRecallPlugins.sh ')
        taskmap = dict()

        for node in self.nodeCfg.getAllNodes():
            if self.nodeCfg.isNodeMaster(node):
                # choose an coordinator node and execute active plugins

                nodes_json = {'nodes': nodes}
                args = [self.nodeCfg.getIp(node), str(self.nodeCfg.getHttpPort(node)), action, '\'' + json.dumps(nodes_json) + '\'']
                cmdstr = shellfile + ' '.join(args)
                argmap = dict()
                argmap['cmdstr'] = cmdstr
                argmap['sysuser'] = self.nodeCfg.getSystemUser()
                argmap['envmap'] = self.genEsScriptEnv(node)
                print(("add process active recall plugin task for %s " % node))
                logger.info("add process active recall plugin task for %s", node)
                taskmap[node] = argmap
                break

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.executeCmd)

    def createIndex(self):
        logger.info("start to do createIndex in Nodes")
        print(("%s start to createIndex, please waitting for 3-5 minutes patiently.." % (self.timestamp())))
        shellfile = os.path.join(pathtool.getShellscriptPath(), 'createIndex.sh ')
        taskmap = dict()

        settingPath = os.path.join(pathtool.getConfigPath(), self.nodeCfg.getIndexSetting())
        if not os.path.exists(settingPath):
            raise RuntimeError("setting map not exist:" + settingPath)

        for node in self.nodeCfg.getAllNodes():
            if self.nodeCfg.isNodeMaster(node):
                # choose an master node and execute create index
                args = [self.nodeCfg.getIndexName(), self.nodeCfg.getIp(node),
                        str(self.nodeCfg.getHttpPort(node)), settingPath]
                cmdstr = shellfile + ' '.join(args)
                argmap = dict()
                argmap['cmdstr'] = cmdstr
                argmap['sysuser'] = self.nodeCfg.getSystemUser()
                argmap['envmap'] = self.genEsScriptEnv(node)
                print(("add process createIndex task for %s " % node))
                logger.info("add process createIndex task for %s", node)
                taskmap[node] = argmap
                break

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.executeCmd)

    def preparePackage(self, action, nodes, cluster_type):
        logger.info("start to do %s Package", action)
        print(("%s start to %s Package, please waitting for 15-30 minutes patiently.." % (action, self.timestamp())))
        shellfile = os.path.join(pathtool.getShellscriptPath(), 'preparePackage.sh ')
        taskmap = dict()
        for node in nodes:
            self.refreshEsCfg(node, action, cluster_type)
            instinfo = self.nodeCfg.getIp(node) + '@' + str(self.nodeCfg.getPort(node))
            args = [self.nodeCfg.getEsPackage(), self.nodeCfg.getNodeSoftwareDir(node), instinfo, action, cluster_type]
            cmdstr = shellfile + ' '.join(args)
            argmap = dict()
            argmap['cmdstr'] = cmdstr
            argmap['sysuser'] = self.nodeCfg.getSystemUser()
            argmap['envmap'] = self.genEsScriptEnv(node)
            print(("add process %s Package task for node %s: %s " % (action, node, instinfo)))
            logger.info("add process %s Package task for %s", action, node)
            taskmap[node] = argmap

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.executeCmd)

    def preDealCommonPackage(self, nodes):
        logger.info("start to do preDealCommonPackage")
        print(("%s start to preDealCommonPackage, please waitting for 5-10 minutes patiently.." % (self.timestamp())))
        shellfile = os.path.join(pathtool.getShellscriptPath(), 'preDealPackage.sh ')
        taskmap = dict()
        node = nodes[0]
        args = []
        cmdstr = shellfile + ' '.join(args)
        argmap = dict()
        argmap['cmdstr'] = cmdstr
        argmap['sysuser'] = self.nodeCfg.getSystemUser()
        argmap['envmap'] = self.genEsScriptEnv(node)
        print("add process preDealCommonPackage task for all node")
        logger.info("add process preDealCommonPackage task for all node")
        taskmap[node] = argmap

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.executeCmd)

    def checkNodeRoleValid(self, nodes):
        for node in nodes:
            if self.nodeCfg.isNodeMaster(node) and self.nodeCfg.isNodeData(node):
                logger.info("can't have both master and data role on a es instance, node is %s, ip is %s.", node, self.nodeCfg.getIp(node))
                raise RuntimeError("can't have both master and data role on a es instance, node is " + node + ", ip is " + self.nodeCfg.getIp(node))

    def preInstallCheck(self, nodes, cluster_type):
        self.checkNodeRoleValid(nodes)
        self.preDealCommonPackage(nodes)

        logger.info("start to do preInstallCheck")
        print(("%s start to preInstallCheck, please waitting for 15-30 minutes patiently.." % (self.timestamp())))
        shellfile = os.path.join(pathtool.getShellscriptPath(), 'preInstallCheck.sh ')
        taskmap = dict()
        for node in nodes:
            instinfo = self.nodeCfg.getIp(node) + '@' + str(self.nodeCfg.getPort(node))
            args = [instinfo, self.nodeCfg.getNodeSoftwareDir(node), self.nodeCfg.getPathData(),
                    self.nodeCfg.isSudoSupport(), cluster_type]
            cmdstr = shellfile + ' '.join(args)
            argmap = dict()
            argmap['cmdstr'] = cmdstr
            argmap['sysuser'] = self.nodeCfg.getSystemUser()
            argmap['envmap'] = self.genEsScriptEnv(node)
            print(("add process preInstallCheck task for node %s: %s " % (node, instinfo)))
            logger.info("add process preInstallCheck task for %s", node)
            taskmap[node] = argmap

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.executeCmd)

    @staticmethod
    def logAndPrint(msg):
        logger.info(msg)
        print(msg)

    def deploy(self, actions, nodes, cluster_type):
        self.logAndPrint("#####################Deploy Indexer BEGIN#####################")
        self.logAndPrint("start to deploy with actions: " + ','.join(actions))
        for action in actions:
            self.logAndPrint("-------------------STEP " + action + "-------------------")
            if deployIns.nodeCfg.isSudoSupport() != "yes":
                if action == "setenv":
                    self.logAndPrint("sudo operation not permit to do on indexer nodes. Ignore action:" + action)
                    continue
            if action == "prepare":
                self.preparePackage(action, nodes, cluster_type)
            elif action == "index":
                self.createIndex()
            elif action == "precheck":
                self.preInstallCheck(nodes, cluster_type)
            elif action == "refresh" or action == "refresh_recall":
                self.preparePackage(action, nodes, cluster_type)
                self.deployNode(action, nodes)
                self.activeRecallPlugin(action, nodes)
            else:
                self.deployNode(action, nodes)
        self.logAndPrint("#####################Deploy Indexer SUCCESSFULLY#####################")

if len(sys.argv) >= 0:
    # 响应键盘的CTRL+C让工具中的多进程优雅退出
    signal.signal(signal.SIGINT, graceful_quit)
    try:
        params = parse_config()
        deployIns = CDeployES()
        # 生成日志文件并改好权限
        logfd = os.open(LOGFILEPATH, os.O_RDWR | os.O_CREAT)
        os.close(logfd)
        subprocess.call("chown " + deployIns.nodeCfg.getSystemUser() + ":" + deployIns.nodeCfg.getSystemGroup()
                        + " " + LOGFILEPATH, shell=True)

        deployIns.deploy(getActions(params), getActionNodes(params), esCfgs.CClusterNodeCfg().getClusterType())
    except Exception as e:
        print((repr(e)))
        traceback.print_tb(e.__traceback__)
        sys.exit(1)
else:
    print("argv num error")
    sys.exit(1)
