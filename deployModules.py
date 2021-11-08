#!/usr/bin/env python
# -*- coding:utf-8 -*-
# 根据cfg.json配置,在临时db中升级AC数据并导出
# 其中数据的导出会使用多进程并发
import argparse
import os
import time
import traceback
import subprocess

import esCfgs
import pathtool
import logging
import signal
import sys
import taskExecutor

FORMAT = '%(asctime)-15s %(message)s'
LOGFILEPATH = pathtool.getLogPath()
logging.basicConfig(filename=LOGFILEPATH, format=FORMAT)
logger = logging.getLogger('deploy')
logger.setLevel(logging.INFO)


def parse_config():
    parser = argparse.ArgumentParser(description="deploy cluster modules automatic")
    parser.add_argument('--action', type=str, default='default',
                        help='specify an action step to execute in cluster, default choose actions default')
    parser.add_argument('--node', type=str, default='all',
                        help='specify node names to execute action you wanted. eg:--node node1,node2 '
                             ';default value is all, means choose all nodes to deploy modules.')
    parser.add_argument('--module', type=str, default='all',
                        help='specify module names to execute action you wanted. eg:--module file-fetcher '
                             ';default value is all, means choose all modules to deploy.')
    return parser.parse_args()


def printNodesList():
    nodeInst = esCfgs.CNodesMap()
    modulesInst = esCfgs.CModuleNodesMap()
    print("\r\n=========All nodes===========")
    print(','.join(nodeInst.getAllSurpportNodes()))

    for module in modulesInst.getAllSurpportModules():
        print("\r\n=========module: %s===========" % module)
        print(','.join(modulesInst.getModuleNodes(module)))


def checkUninstall(nodes, modules):
    print("\r\nUninstall the modules [" + ','.join(modules) + "] on these nodes:")
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
    supprotActions = ["precheck", "prepare", "setenv", "refresh", "install", "uninstall", "start", "stop",
                      "restart", "default", "help", "nodeInfo"]
    defaultList = ["precheck", "prepare", "setenv", "install", "start"]
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
    elif actionStr == "uninstall":
        if not checkUninstall(getActionNodes(params), getSpecifyModule(params)):
            sys.exit(0)
        else:
            specifyActions.append(actionStr)
    elif actionStr == "help":
        print("====================USAGE INFO========================")
        print(("The default actions are: " + ','.join(defaultList)))
        print(("OR choose a single action in: " + ','.join(supprotActions)))
        print("[precheck]: pre check system configurations on cluster nodes, eg: sudo permission. "
              "Support for specifying --node at the same time")
        print("[prepare]: auto generate modules configurations and packages, then deliver to all cluster nodes. "
              "Support for specifying --node at the same time")
        print("[setenv]: set system env on modules cluster nodes, eg: sysctl.conf. "
              "Support for specifying --node at the same time")
        print("[refresh]: refresh modules software to all cluster nodes,"
              " include restart. Support for specifying --node at the same time")
        print("[install]: install ES/module and depend software on target cluster nodes. "
              "Support for specifying --node at the same time")
        print("[start]: start modules on all cluster nodes."
              " Support for specifying --node at the same time")
        print("[stop]: stop modules on all cluster nodes."
              " Support for specifying --node at the same time")
        print("[restart]: restart modules on all cluster nodes."
              " Support for specifying --node at the same time")
        print("[uninstall]: uninstall modules on all cluster nodes, remaining data and logs dir."
              " Support for specifying --node at the same time")
        print("[default]: deploy ES/module by default actions:" + ','.join(defaultList) +
              ". Support for specifying --node at the same time")
        print("[nodeInfo]: print detail infos about all cluster nodes.")
        print("[help]: show detail help info")
        print("====================USAGE INFO========================")
        sys.exit(0)
    else:
        specifyActions.append(actionStr)
    return specifyActions


def getSpecifyModule(params):
    modules = []
    modulename = str(params.module).strip()
    specifymodulenames = modulename.split(",")
    if modulename == "all":
        modules = pathtool.getModulesList()
    else:
        for speficy in specifymodulenames:
            if speficy not in pathtool.getModulesList():
                print(("please specify valid modules in: " + ','.join(pathtool.getModulesList())))
                sys.exit(1)
            else:
                modules.append(speficy)
    return modules


def getActionNodes(params):
    nodes = []
    nodeInst = esCfgs.CNodesMap()
    nodename = str(params.node).strip()
    specifynodes = nodename.split(",")
    modulename = str(params.module).strip()
    specifymodulenames = modulename.split(",")
    if nodename == "all":
        if modulename == "all":
            nodes = nodeInst.getAllSurpportNodes()
        else:
            for module in specifymodulenames:
                if module not in pathtool.getModulesList():
                    print(("[getting action nodes] please specify valid modules in: " + ','.join(pathtool.getModulesList())))
                    sys.exit(1)
                else:
                    nodes.extend(nodeInst.getNodeListOfModule(module))
    else:
        for speficy in specifynodes:
            if speficy not in nodeInst.getAllSurpportNodes():
                print(("please specify valid node in: " + ','.join(nodeInst.getAllSurpportNodes())))
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


class CDeployMoudles:
    def __init__(self):
        self.nodeCfg = esCfgs.CClusterNodeCfg()
        self.nodeMapInst = esCfgs.CNodesMap()

    def getIp(self, node):
        return self.nodeMapInst.getIp(node)

    def getPort(self, node):
        return self.nodeMapInst.getPort(node)

    def getSystemUser(self):
        return self.nodeCfg.getSystemUser()

    def getSystemGroup(self):
        return self.nodeCfg.getSystemGroup()

    def getJdkPkg(self):
        return self.nodeCfg.getModulesJdkPkg()

    def getNodeSoftwareDir(self, node):
        return self.nodeCfg.getNodeSoftwareDir(node)

    def getModuleInstallDir(self, node):
        return os.path.join(self.nodeCfg.getEsInstallDir(), 'modules', node)

    def isSudoSupport(self):
        return self.nodeCfg.isSudoSupport()

    def genDispatherCfg(self):
        logger.info("start to do generate dispatch cfg for nodes")
        print(("%s start to do generate dispatch cfg for nodes" % (self.timestamp())))
        fiIns = esCfgs.CDispatchCfg()
        fiIns.genDispatherCfg()

    def genFileFetcherCfg(self):
        logger.info("start to do generate file-fetcher cfg for nodes")
        print(("%s start to do generate file-fetcher cfg for nodes" % (self.timestamp())))
        fiIns = esCfgs.CFileFetcherCfg()
        fiIns.genFileFetcherCfg()

    def genReWriterFetcherCfg(self):
        logger.info("start to do generate rewriter-fetcher cfg for nodes")
        print(("%s start to do generate rewriter-fetcher cfg for nodes" % (self.timestamp())))
        wfIns = esCfgs.CRewriterFetcherCfg()
        wfIns.genRewriterFetcherCfg()

    def genOptoolsCfg(self):
        logger.info("start to do generate optools cfg for nodes")
        print(("%s start to do generate optools cfg for nodes" % (self.timestamp())))
        fiIns = esCfgs.COptoolsCfg()
        fiIns.genOptoolsCfg()

    def genRewriterCfg(self):
        logger.info("start to do generate query-rewriter cfg for nodes")
        print(("%s start to do generate query-rewriter cfg for nodes" % (self.timestamp())))
        rewriterIns = esCfgs.CRewriterCfg()
        rewriterIns.genRewriterCfg()

    def genRerankerCfg(self):
        logger.info("start to do generate reranker cfg for nodes")
        print(("%s start to do generate reranker cfg for nodes" % (self.timestamp())))
        rerankerIns = esCfgs.CRerankerCfg()
        rerankerIns.genRerankerCfg()

    def genRankserverCfg(self):
        logger.info("start to do generate rankserver cfg for nodes")
        print(("%s start to do generate rankserver cfg for nodes" % (self.timestamp())))
        rankerserverIns = esCfgs.CRankServerCfg()
        rankerserverIns.genRankServerCfg();
       

    def genPVSearchCfg(self):
        logger.info("start to do generate pvsearch cfg for nodes")
        print(("%s start to do generate pvsearch cfg for nodes" % (self.timestamp())))
        pvsearchIns = esCfgs.CPVSearchCfg()
        pvsearchIns.genPVSearchCfg()

    def getActionMoudules(self, modules):
        return ','.join(modules)

    def genModulesCfg(self, nodes, modules):
        for node in nodes:
            distInst = esCfgs.CdeployDistCfg(node)
            distInst.initDistCfg()

        logger.info("start to do generate cfg for modules[ %s ]" % (','.join(modules)))
        print(("%s start to do generate cfg for modules[ %s ]" % (self.timestamp(), ','.join(modules))))
        if 'dispatcher' in modules:
            self.genDispatherCfg()
        if 'file-fetcher' in modules:
            self.genFileFetcherCfg()
        if 'rewriter-fetcher' in modules:
            self.genReWriterFetcherCfg()
        if 'query-rewriter' in modules:
            self.genRewriterCfg()
        if 'reranker' in modules:
            self.genRerankerCfg()
        if 'rankserver' in modules:
            self.genRankserverCfg()
        if 'pvsearch' in modules:
            self.genPVSearchCfg()
        if 'optools' in modules:
            self.genOptoolsCfg()

    def timestamp(self):
        return time.asctime(time.localtime(time.time()))

    def genScriptEnv(self, node, modules):
        envmap = dict()
        envmap['ENV_SYSTEMUSER'] = self.getSystemUser()
        envmap['ENV_SYSTEMGROUP'] = self.getSystemGroup()
        envmap['ENV_PASSWORD'] = "******"
        envmap['ENV_NODENAME'] = node
        envmap['ENV_SPCIFYMODULES'] = self.getActionMoudules(modules)
        envmap['ENV_JDK'] = self.getJdkPkg()
        return envmap

    def deployNode(self, action, nodes, modules):
        logger.info("start to do %s in Nodes", action)
        print(("%s start to deployModulesNode of modules[ %s ], please waitting for 15-30 minutes patiently.."
               % (self.timestamp(), ','.join(modules))))
        shellfile = os.path.join(pathtool.getShellscriptPath(), 'deployModulesNode.sh ')
        taskmap = dict()
        for node in nodes:
            hostinfo = self.getIp(node) + '@' + str(self.getPort(node))
            args = [self.getNodeSoftwareDir(node),
                    self.getModuleInstallDir(node), hostinfo, action]
            cmdstr = shellfile + ' '.join(args)
            argmap = dict()
            argmap['cmdstr'] = cmdstr
            argmap['envmap'] = self.genScriptEnv(node, modules)
            print(("add process %s deployModulesNode task for node %s: %s " % (action, node, hostinfo)))
            logger.info("add process deployModulesNode task for %s", node)
            taskmap[node] = argmap

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.executeCmd)

    def preparePackage(self, action, nodes, modules, cluster_type):
        logger.info("start to do %s Package", action)
        print(("%s start to %s Package, please waitting for 15-30 minutes patiently.." % (action, self.timestamp())))
        self.genModulesCfg(nodes, modules)
        shellfile = os.path.join(pathtool.getShellscriptPath(), 'prepareModulesPkg.sh ')
        taskmap = dict()
        for node in nodes:
            instinfo = self.getIp(node) + '@' + str(self.getPort(node))
            args = [self.getNodeSoftwareDir(node), instinfo, action, cluster_type]
            cmdstr = shellfile + ' '.join(args)
            argmap = dict()
            argmap['cmdstr'] = cmdstr
            argmap['envmap'] = self.genScriptEnv(node, modules)
            print(("add process %s Package task for node %s: %s " % (action, node, instinfo)))
            logger.info("add process %s Package task for node %s", action, node)
            taskmap[node] = argmap

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.executeCmd)

    def preDealCommonPackage(self, nodes, modules):
        logger.info("start to do preDealCommonPackage")
        print(("%s start to preDealCommonPackage, please waitting for 5-10 minutes patiently.." % (self.timestamp())))
        shellfile = os.path.join(pathtool.getShellscriptPath(), 'preDealPackage.sh ')
        taskmap = dict()
        node = nodes[0]
        args = []
        cmdstr = shellfile + ' '.join(args)
        argmap = dict()
        argmap['cmdstr'] = cmdstr
        argmap['envmap'] = self.genScriptEnv(node, modules)
        print("add process preDealCommonPackage task for all node")
        logger.info("add process preDealCommonPackage task for all node")
        taskmap[node] = argmap

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.executeCmd)

    def preInstallCheck(self, nodes, modules, cluster_type):
        self.preDealCommonPackage(nodes, modules)

        logger.info("start to do preInstallCheck")
        print(("%s start to preInstallCheck, please waitting for 15-30 minutes patiently.." % (self.timestamp())))
        shellfile = os.path.join(pathtool.getShellscriptPath(), 'preInstallCheck.sh ')
        taskmap = dict()
        for node in nodes:
            instinfo = self.getIp(node) + '@' + str(self.getPort(node))
            args = [instinfo, self.getNodeSoftwareDir(node), self.getModuleInstallDir(node),
                    self.isSudoSupport(), cluster_type]
            cmdstr = shellfile + ' '.join(args)
            argmap = dict()
            argmap['cmdstr'] = cmdstr
            argmap['envmap'] = self.genScriptEnv(node, modules)
            print(("add process preInstallCheck task for %s: %s " % (node, instinfo)))
            logger.info("add process preInstallCheck task for %s", node)
            taskmap[node] = argmap

        taskExecutor.multiProcess_task(multiCpu=self.nodeCfg.getMultiCpuNum(), taskmap=taskmap,
                                       func=taskExecutor.executeCmd)

    @staticmethod
    def logAndPrint(msg):
        logger.info(msg)
        print(msg)

    def deploy(self, actions, nodes, modules, cluster_type):
        self.logAndPrint("#####################Deploy ES BEGIN#####################")
        self.logAndPrint("start to deploy with actions: " + ','.join(actions))
        for action in actions:
            self.logAndPrint("-------------------STEP " + action + "-------------------")
            if deployIns.nodeCfg.isSudoSupport() != "yes":
                if action == "setenv":
                    self.logAndPrint("sudo operation not permit to do on ES nodes. Ignore action:" + action)
                    continue
            if action == "prepare":
                self.preparePackage(action, nodes, modules, cluster_type)
            elif action == "precheck":
                self.preInstallCheck(nodes, modules, cluster_type)
            elif action == "refresh":
                self.preparePackage(action, nodes, modules, cluster_type)
                self.deployNode(action, nodes, modules)
            else:
                self.deployNode(action, nodes, modules)
        self.logAndPrint("#####################Deploy ES SUCCESSFULLY#####################")


if len(sys.argv) >= 0:
    # 响应键盘的CTRL+C让工具中的多进程优雅退出
    signal.signal(signal.SIGINT, graceful_quit)
    try:
        params = parse_config()
        deployIns = CDeployMoudles()
        # 生成日志文件
        logfd = os.open(LOGFILEPATH, os.O_RDWR | os.O_CREAT)
        os.close(logfd)
        deployIns.deploy(getActions(params), getActionNodes(params), getSpecifyModule(params), esCfgs.CClusterNodeCfg().getClusterType())
    except Exception as e:
        print((repr(e)))
        traceback.print_tb(e.__traceback__)
        sys.exit(1)
else:
    print("argv num error")
    sys.exit(1)
