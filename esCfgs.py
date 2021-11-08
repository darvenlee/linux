#!/usr/bin/env python
# encoding: utf-8
import os

import jsonTool
import pathtool
import propertiesTool
import xmlTool
import yamlTool


class CMapSetting(object):
    def __init__(self, setting):
        self.jsondatas = jsonTool.readJsonfile(setting)

    def __getSettingsInfo(self):
        return self.jsondatas.get('settings')

    def __getIndexInfo(self):
        return self.jsondatas.get('settings')

    def getShardsNum(self):
        return self.__getIndexInfo()['number_of_shards']

    def getReplicasNum(self):
        return self.__getIndexInfo()['number_of_replicas']


class CClusterNodeCfg(object):
    def __init__(self):
        self.__jsonfile = os.path.join(pathtool.getConfigPath(), 'cluster_nodes_cfg.json')
        self.__jsondatas = jsonTool.readJsonfile(self.__jsonfile)
        self.__hostMap = self.buildHostsInfo()
        self.__nodeInstanceNumMap = self.buildHostInstanceNumberMap()

    def getClusterType(self):
        cluster_type = 'default'
        if 'clusterType' in self.__jsondatas:
            cluster_type = str(self.__jsondatas.get('clusterType')).strip()
        support_types = CClusterType().getTypes()

        if cluster_type not in support_types:
            raise Exception("Don't support cluster_type " + cluster_type + ", please specify cluster_type in: " +
                ','.join(support_types))
        return cluster_type

    def getIsMultipleSoftLinkMode(self):
        multi_node_soft_link = 'yes'
        if 'multi_node_soft_link' in self.__jsondatas:
            multi_node_soft_link = str(self.__jsondatas.get('multi_node_soft_link')).strip()

        return multi_node_soft_link

    def getInstanceNumber(self, node):
        return self.__nodeInstanceNumMap[node]

    def getEsPackage(self):
        return str(self.__jsondatas.get('esPackage')).strip()

    def getEsSoftwareDir(self):
        return os.path.normpath(str(self.__jsondatas.get('esSoftwareDir')).strip())

    def getEsInstallDir(self):
        return os.path.normpath(str(self.__jsondatas.get('esInstallDir')).strip())

    def getNodeSoftwareDir(self, node):
        return os.path.join(self.getEsSoftwareDir(), node)

    def getNodeInstallDir(self, node):
        return os.path.join(self.getEsInstallDir(), node)

    def getSystemUser(self):
        return str(self.__jsondatas.get('systemUser')).strip()

    def getSystemGroup(self):
        return str(self.__jsondatas.get('systemGroup')).strip()

    def isDebug(self):
        return str(self.__jsondatas.get('debug')).strip()

    def getEsJdkPkg(self):
        return str(self.__jsondatas.get('esJDK')).strip()

    def getModulesJdkPkg(self):
        return str(self.__jsondatas.get('modulesJDK')).strip()

    def getMultiCpuNum(self):
        if 'multiCpuNum' in self.__jsondatas:
            return self.__jsondatas.get('multiCpuNum')
        else:
            return 4

    def isSudoSupport(self):
        return str(self.__jsondatas.get('sudoSupport')).strip()

    def isOnline(self):
        if 'isOnline' in self.__jsondatas:
            return str(self.__jsondatas.get('isOnline')).strip()
        else:
            return "no"

    def getBuildType(self):
        if self.isOnline() == "yes":
            return "online"
        else:
            return "offline"

    def getHosts(self):
        return self.__jsondatas.get('hosts')

    def getOmHosts(self):
        return self.__jsondatas.get('om_hosts')

    def getVectorInfo(self):
        return self.__jsondatas.get('vectorInfo')

    def getPoissonSearchServerInfo(self):
        return self.__jsondatas.get('poissonSearchServerInfo')

    def getEsCommonInfo(self):
        return self.__jsondatas.get('esCommonInfo')

    def getEsImportInfo(self):
        return self.__jsondatas.get('esImportInfo')

    def getEsOptimize(self):
        if 'es.optimize' in self.getEsCommonInfo():
            return self.getEsCommonInfo()['es.optimize']
        else:
            return False

    def getQueryAndFetchOptimize(self):
        if 'query_and_fetch.optimize' in self.getEsCommonInfo():
            return self.getEsCommonInfo()['query_and_fetch.optimize']
        else:
            return True

    def getDisableIdsOptimize(self):
        if 'disable.ids.optimize' in self.getEsCommonInfo():
            return self.getEsCommonInfo()['disable.ids.optimize']
        else:
            return False

    def getEsLogFirModule(self):
        if 'log.fir_module' in self.getEsCommonInfo():
            return str(self.getEsCommonInfo()['log.fir_module'].strip())
        else:
            return "web_search"

    def getEsLogSecModule(self):
        if 'log.sec_module' in self.getEsCommonInfo():
            return str(self.getEsCommonInfo()['log.sec_module'].strip())
        else:
            return "indexservice"

    def getEsAlarmScope(self):
        if 'alarm.scope' in self.getEsCommonInfo():
            return str(self.getEsCommonInfo()['alarm.scope'].strip())
        else:
            return "tysearch"

    def getIndexSetting(self):
        return str(self.getEsImportInfo()['indexSetting']).strip()

    def getIndexName(self):
        return str(self.getEsImportInfo()['indexName']).strip()

    def getSendPerline(self):
        return self.getEsImportInfo()['sendPerLines']

    def getImportDataDir(self):
        return os.path.normpath(str(self.getEsImportInfo()['esSrcDataDir']).strip())

    def getEsDataSuffix(self):
        return str(self.getEsImportInfo()['esDataSuffix']).strip()

    def getImportRange(self):
        ranges = self.getEsImportInfo()['dataRange']
        if len(ranges) != 2:
            raise RuntimeError("value of dataRange option not valid")
        if ranges[0] > ranges[1]:
            raise RuntimeError("the first range index should less than the second range index")
        return ranges

    def getHostInfo(self, node):
        return self.__hostMap[node]

    def buildHostsInfo(self):
        hostInfoMap = dict()
        for hostInfo in self.getHosts():
            node = hostInfo['node.name']
            hostInfoMap[node] = hostInfo

        return hostInfoMap

    def getIp(self, node):
        return str(self.getHostInfo(node)['ip']).strip()

    def getPort(self, node):
        return self.getHostInfo(node)['port']

    def getNodeName(self, node):
        return str(self.getHostInfo(node)['node.name']).strip()

    def getUser(self, node):
        return str(self.getHostInfo(node)['user']).strip()

    def getPassword(self, node):
        return str(self.getHostInfo(node)['password']).strip()

    def getPathData(self):
        path_datas = self.getEsCommonInfo()['path.data']
        if not isinstance(path_datas, list):
            raise RuntimeError('ERROR: path.data in esCommonInfo must be a list')
        norm_path_data_list = [os.path.normpath(path_data) for path_data in path_datas]
        if len(norm_path_data_list) == 0:
            raise RuntimeError("ERROR: path.data in esCommonInfo must not be empty!")
        return ','.join(norm_path_data_list)

    def getPathLogs(self):
        return os.path.normpath(str(self.getEsCommonInfo()['path.logs']).strip())

    def getNodePathData(self, node):
        path_data_list = self.getPathData().split(',')
        node_path_data_list = [os.path.join(path_data, node) for path_data in path_data_list]
        return ','.join(node_path_data_list)

    def getNodePathLoad(self, node):
        path_data_list = self.getNodePathData(node).split(',')
        return os.path.join(path_data_list[0], 'receive')

    def getNodePathLogs(self, node):
        return os.path.join(self.getPathLogs(), node)

    def getClusterName(self):
        return str(self.getEsCommonInfo()['cluster.name']).strip()

    def getHttpPort(self, node):
        return self.getHostInfo(node)['http.port']

    def getTransportTcpPort(self, node):
        return self.getHostInfo(node)['transport.tcp.port']

    def isNodeMaster(self, node):
        if 'node.master' in self.getHostInfo(node):
            return self.getHostInfo(node)['node.master']
        else:
            return True

    def getReservedPortOffset(self):
        if 'reservedPortOffset' in self.__jsondatas:
            return self.__jsondatas['reservedPortOffset']
        else:
            return 50

    def getPoissonSearchServerGrpcPortOffset(self):
        if self.getPoissonSearchServerInfo() and 'grpcPortOffset' in self.getPoissonSearchServerInfo():
            return self.getPoissonSearchServerInfo()['grpcPortOffset']
        else:
            return 100

    def getVectorGrpcPortOffset(self):
        if self.getVectorInfo() and 'grpcPortOffset' in self.getVectorInfo():
            return self.getVectorInfo()['grpcPortOffset']
        else:
            return 51

    def getVectorIdlen(self):
        if self.getVectorInfo() and 'idLen' in self.getVectorInfo():
            return self.getVectorInfo()['idLen']
        else:
            return 16

    def getVectorBlockD(self):
        if self.getVectorInfo() and 'block.d' in self.getVectorInfo():
            return self.getVectorInfo()['block.d']
        else:
            return 512

    def getVectorServeMode(self):
        if self.getVectorInfo() and 'serve_mode' in self.getVectorInfo():
            return self.getVectorInfo()['serve_mode']
        else:
            return True

    def getVectorNumWorkers(self):
        if self.getVectorInfo() and 'num_workers' in self.getVectorInfo():
            return self.getVectorInfo()['num_workers']
        else:
            return -1

    def getVectorIndexNprobe(self):
        if self.getVectorInfo() and 'index_nprobe' in self.getVectorInfo():
            return self.getVectorInfo()['index_nprobe']
        else:
            return 64

    def getVectorDistRatio(self):
        if self.getVectorInfo() and 'dist_ratio' in self.getVectorInfo():
            return self.getVectorInfo()['dist_ratio']
        else:
            return 1.0

    def isNodeData(self, node):
        if 'node.data' in self.getHostInfo(node):
            return self.getHostInfo(node)['node.data']
        else:
            return True

    def isNodeCoordinator(self, node):
        if not self.isNodeData(node) and not self.isNodeMaster(node):
            return True
        else:
            return False

    def isNodeIngest(self, node):
        if 'node.ingest' in self.getHostInfo(node):
            return self.getHostInfo(node)['node.ingest']
        else:
            return True

    def getNodeType(self, node):
        if self.isNodeMaster(node):
            return "master"
        elif self.isNodeData(node):
            return "datanode"
        else:
            return "coordinator"

    
    def buildHostInstanceNumberMap(self):
        hostNumMap = dict()
        ipMap = dict()
        for hostInfo in self.getHosts():
            node = hostInfo['node.name']
            ip = hostInfo['ip']
            role = self.getNodeType(node)
            if ip not in ipMap.keys():
                ipMap[ip] = {}
                ipMap[ip]['master'] = 0
                ipMap[ip]['datanode'] = 0
                ipMap[ip]['coordinator'] = 0 

            ipMap[ip][role] += 1
            instanceNum = ipMap[ip][role]
            hostNumMap[node] = instanceNum
        
        return hostNumMap

    def getAllNodes(self):
        nodelist = []
        for info in self.getHosts():
            nodelist.append(info['node.name'])

        return nodelist

    def isNodeExist(self, node):
        if node in self.getAllNodes():
            return True
        return False

    def getAllMasterNodes(self):
        nodelist = []
        for node in self.getAllNodes():
            if self.isNodeMaster(node):
                nodelist.append(node)

        return nodelist

    def getAllDataNodes(self):
        nodelist = []
        for node in self.getAllNodes():
            if self.isNodeData(node):
                nodelist.append(node)

        return nodelist

    def getAllCoordinatorNodes(self):
        nodelist = []
        for node in self.getAllNodes():
            if self.isNodeCoordinator(node):
                nodelist.append(node)

        return nodelist

    def isNodeRealTime(self, node):
        if 'node.realtime' in self.getHostInfo(node):
            return self.getHostInfo(node)['node.realtime']
        else:
            return False

    def getAuthInfo(self):
        return self.__jsondatas.get('authInfo')

    def getHmacSwitch(self, node):
        authInfo = self.getAuthInfo()
        if authInfo is not None:
            if 'hmac.enabled' in authInfo:
                return authInfo['hmac.enabled']

        templateFile = yamlTool.chooseTemplateYAML(node, self.getBuildType())
        yamlDatas = yamlTool.readYamlfile(templateFile)
        if 'hmac.enabled' in yamlDatas:
            return yamlDatas['hmac.enabled']

        return False


class CDispatchCfg(object):
    def __init__(self):
        self.__modulename = "dispatcher"
        self.__cfgfiles = ['fetcher.properties', 'consumer.properties']
        self.__properIns = dict()
        self.__property = dict()
        self.__loadProperties()

    def getModuleName(self):
        return self.__modulename

    def getIpInfo(self):
        esInstCfg = CClusterNodeCfg()
        infoMap = dict()
        for node in esInstCfg.getAllDataNodes():
            ip = esInstCfg.getIp(node)
            port = esInstCfg.getPort(node)
            pwd = esInstCfg.getPassword(node)
            hostinfo = dict()
            hostinfo['ip'] = ip
            hostinfo['port'] = port
            hostinfo['pwd'] = pwd
            infoMap[node] = hostinfo
        return infoMap

    def getNodes(self):
        esInstCfg = CClusterNodeCfg()
        infoMap = dict()
        infoMap[self.__modulename] = esInstCfg.getAllDataNodes()

        return infoMap

    def __getProperIns(self, cfgname):
        return self.__properIns[cfgname]

    def __getProperty(self, cfgname):
        return self.__property[cfgname]

    def __loadProperties(self):
        for filename in self.__cfgfiles:
            filepath = os.path.join(pathtool.getTemplateCfgPath(self.__modulename), filename)
            self.__properIns[filename] = propertiesTool.Properties(filepath)
            self.__property[filename] = self.__properIns[filename].readProperties()

    def __cpProperties(self, node):
        # clear exist properties, and re-copy from origin template
        pathtool.genMoudleNodeConfig(node, self.__modulename)

    def __refreshXMLByKVs(self, filename, KVs):
        domTree = xmlTool.readXML(filename)
        rootNode = domTree.documentElement
        propertys = rootNode.getElementsByTagName("property")
        for property in propertys:
            name = property.getElementsByTagName("name")[0]
            value = property.getElementsByTagName("value")[0]
            if name.childNodes[0].data in KVs:
                value.childNodes[0].data = KVs[name.childNodes[0].data]
        xmlTool.writeXML(filename, domTree)

    def __refreshHdfsCfg(self, node, fiInfoIns):
        filename = 'core-site.xml'
        filepath = os.path.join(pathtool.getNodeConfigPath(node, self.__modulename), filename)
        if os.path.exists(filepath):
            keyMap = dict()
            keyMap['oi.dfs.colocation.zookeeper.quorum'] = fiInfoIns.getZkClusterInfo()
            keyMap['ha.zookeeper.quorum'] = fiInfoIns.getZkClusterInfo()
            self.__refreshXMLByKVs(filepath, keyMap)

        filename = 'hdfs-site.xml'
        filepath = os.path.join(pathtool.getNodeConfigPath(node, self.__modulename), filename)
        if os.path.exists(filepath):
            keyMap = dict()
            keyMap['oi.dfs.colocation.zookeeper.quorum'] = fiInfoIns.getZkClusterInfo()
            keyMap['ha.zookeeper.quorum'] = fiInfoIns.getZkClusterInfo()
            self.__refreshXMLByKVs(filepath, keyMap)

    def genDispatherCfg(self):
        nodeCfg = CClusterNodeCfg()
        for node in nodeCfg.getAllDataNodes():
            self.__cpProperties(node)
            distInst = CdeployDistCfg(node)
            distInst.refreshMoudle(self.__modulename)
            # start to generate fetcher.properties for node
            filename = 'fetcher.properties'
            filepath = os.path.join(pathtool.getNodeConfigPath(node, self.__modulename), filename)
            if os.path.exists(filepath):
                property = self.__getProperty(filename)
                property['es.port'] = nodeCfg.getHttpPort(node)
                property['es.ip'] = nodeCfg.getIp(node)
                property['local.file.path'] = nodeCfg.getNodePathLoad(node)
                self.__getProperIns(filename).writeProperties(filepath)


class CFileFetcherCfg(object):
    def __init__(self):
        self.__modulename = "file-fetcher"
        self.__cfgfiles = ['fetcher.properties']
        self.__properIns = dict()
        self.__property = dict()
        self.__loadProperties()

    def getModuleName(self):
        return self.__modulename

    def getIpInfo(self):
        esInstCfg = CClusterNodeCfg()
        infoMap = dict()
        for node in esInstCfg.getAllDataNodes():
            ip = esInstCfg.getIp(node)
            port = esInstCfg.getPort(node)
            pwd = esInstCfg.getPassword(node)
            hostinfo = dict()
            hostinfo['ip'] = ip
            hostinfo['port'] = port
            hostinfo['pwd'] = pwd
            infoMap[node] = hostinfo
        return infoMap

    def getNodes(self):
        esInstCfg = CClusterNodeCfg()
        infoMap = dict()
        infoMap[self.__modulename] = esInstCfg.getAllDataNodes()
        return infoMap

    def __getProperIns(self, cfgname):
        return self.__properIns[cfgname]

    def __getProperty(self, cfgname):
        return self.__property[cfgname]

    def __loadProperties(self):
        for filename in self.__cfgfiles:
            filepath = os.path.join(pathtool.getTemplateCfgPath(self.__modulename), filename)
            self.__properIns[filename] = propertiesTool.Properties(filepath)
            self.__property[filename] = self.__properIns[filename].readProperties()

    def __cpProperties(self, node):
        # clear exist properties, and re-copy from origin template
        pathtool.genMoudleNodeConfig(node, self.__modulename)

    def genFileFetcherCfg(self):
        nodeCfg = CClusterNodeCfg()
        for node in nodeCfg.getAllDataNodes():
            self.__cpProperties(node)
            distInst = CdeployDistCfg(node)
            distInst.refreshMoudle(self.__modulename)
            # start to generate fetcher.properties for node
            filename = 'fetcher.properties'
            filepath = os.path.join(pathtool.getNodeConfigPath(node, self.__modulename), filename)
            if os.path.exists(filepath):
                property = self.__getProperty(filename)
                property['ip'] = nodeCfg.getIp(node)
                property['port'] = nodeCfg.getHttpPort(node)
                property['local.file.path'] = nodeCfg.getNodePathLoad(node)
                property['node.type'] = "index"
                property['file.type'] = "index,weight,blacklist,vector,snippet,poisson_index"
                property['file.fetcher.server.port'] = nodeCfg.getHttpPort(node) + nodeCfg.getReservedPortOffset()
                self.__getProperIns(filename).writeProperties(filepath)


class CRewriterFetcherCfg(object):
    def __init__(self):
        self.__modulename = "rewriter-fetcher"
        self.__cfgfiles = ['fetcher.properties']
        self.__properIns = dict()
        self.__property = dict()
        self.__loadProperties()

    def getModuleName(self):
        return self.__modulename

    def getIpInfo(self):
        rewriterCfg = CRewriterCfg()
        infoMap = dict()
        for node in rewriterCfg.getAllNodes():
            ip = rewriterCfg.getRewriterIp(node)
            port = rewriterCfg.getPort(node)
            pwd = rewriterCfg.getPassword(node)
            hostinfo = dict()
            hostinfo['ip'] = ip
            hostinfo['port'] = port
            hostinfo['pwd'] = pwd
            infoMap[node] = hostinfo
        return infoMap

    def getNodes(self):
        rewriterCfg = CRewriterCfg()
        infoMap = dict()
        infoMap[self.__modulename] = rewriterCfg.getAllNodes()
        return infoMap

    def __getProperIns(self, cfgname):
        return self.__properIns[cfgname]

    def __getProperty(self, cfgname):
        return self.__property[cfgname]

    def __loadProperties(self):
        for filename in self.__cfgfiles:
            filepath = os.path.join(pathtool.getTemplateCfgPath(self.__modulename), filename)
            self.__properIns[filename] = propertiesTool.Properties(filepath)
            self.__property[filename] = self.__properIns[filename].readProperties()

    def __cpProperties(self, node):
        # clear exist properties, and re-copy from origin template
        pathtool.genMoudleNodeConfig(node, self.__modulename)

    def genRewriterFetcherCfg(self):
        rewriterCfg = CRewriterCfg()
        nodeCfg = CClusterNodeCfg()

        for node in rewriterCfg.getAllNodes():
            self.__cpProperties(node)
            distInst = CdeployDistCfg(node)
            distInst.refreshMoudle(self.__modulename)
            # start to generate fetcher.properties for node
            filename = 'fetcher.properties'
            filepath = os.path.join(pathtool.getNodeConfigPath(node, self.__modulename), filename)
            scriptpath = os.path.join(rewriterCfg.getRewriterHomePath(node), 'bin', 'dict_process.sh')
            if os.path.exists(filepath):
                property = self.__getProperty(filename)
                property['ip'] = rewriterCfg.getRewriterIp(node)
                property['port'] = rewriterCfg.getRewriterPort(node)
                property['local.file.path'] = rewriterCfg.getNodePathLoad(node)
                property['node.type'] = "file"
                property['script.location'] = scriptpath
                property['file.fetcher.server.port'] = rewriterCfg.getRewriterPort(
                    node) + nodeCfg.getReservedPortOffset()
                self.__getProperIns(filename).writeProperties(filepath)


class COptoolsCfg(object):
    def __init__(self):
        self.__modulename = "optools"
        self.__cfgfiles = ['common.cfg']
        self.__properIns = dict()
        self.__property = dict()
        self.__loadProperties()
        self.__omHosts = dict()
        self.__nodes = []
        self.__getNodes()

    def getModuleName(self):
        return self.__modulename

    def __getNodes(self):
        esInstCfg = CClusterNodeCfg()

        self.__nodes = esInstCfg.getAllNodes()
        self.__nodes.extend(self.__omHosts.keys())

    def getIpInfo(self):
        esInstCfg = CClusterNodeCfg()

        infoMap = dict()
        for node in self.__nodes:
            if node in self.__omHosts:
                ip = self.__omHosts.get(node)['ip']
                port = self.__omHosts.get(node)['port']
                pwd = self.__omHosts.get(node)['password']
            else:
                ip = esInstCfg.getIp(node)
                port = esInstCfg.getPort(node)
                pwd = esInstCfg.getPassword(node)
            hostinfo = dict()
            hostinfo['ip'] = ip
            hostinfo['port'] = port
            hostinfo['pwd'] = pwd
            infoMap[node] = hostinfo
        return infoMap

    def getNodes(self):
        infoMap = dict()
        infoMap[self.__modulename] = self.__nodes

        return infoMap

    def __getProperIns(self, cfgname):
        return self.__properIns[cfgname]

    def __getProperty(self, cfgname):
        return self.__property[cfgname]

    def __loadProperties(self):
        for filename in self.__cfgfiles:
            filepath = os.path.join(pathtool.getTemplateCfgPath(self.__modulename), filename)
            self.__properIns[filename] = propertiesTool.Properties(filepath)
            self.__property[filename] = self.__properIns[filename].readProperties()

    def __cpProperties(self, node):
        # clear exist properties, and re-copy from origin template
        pathtool.genMoudleNodeConfig(node, self.__modulename)

    def genOptoolsCfg(self):
        nodeCfg = CClusterNodeCfg()
        for node in self.__nodes:
            self.__cpProperties(node)
            distInst = CdeployDistCfg(node)
            distInst.refreshMoudle(self.__modulename)
            # start to generate fetcher.properties for node
            filename = 'common.cfg'
            filepath = os.path.join(pathtool.getNodeConfigPath(node, self.__modulename), filename)
            if os.path.exists(filepath):
                property = self.__getProperty(filename)
                property['es_home'] = nodeCfg.getNodeInstallDir(node)
                property['alarm_scope'] = nodeCfg.getEsAlarmScope()
                if node in self.__omHosts:
                    property['es_ip'] = self.__omHosts.get(node)['ip']
                    property['es_http_port'] = '80'
                    property['node_type'] = 'om'
                else:
                    property['es_ip'] = nodeCfg.getIp(node)
                    if nodeCfg.getHmacSwitch(node):
                        property['es_ip'] = '127.0.0.1'
                    property['es_http_port'] = nodeCfg.getHttpPort(node)
                    property['node_type'] = 'es'

                masterAddrs = ''
                for master in nodeCfg.getAllMasterNodes():
                    masterAddrs += nodeCfg.getIp(master) + ':' + str(nodeCfg.getHttpPort(master)) + ','
                property['master_http_addrs'] = masterAddrs
                self.__getProperIns(filename).writeProperties(filepath)


class CdeployDistCfg(object):
    def __init__(self, node):
        self.__cfgfile = os.path.join(pathtool.getDistConfigPath(node), 'deploy.properties')
        pathtool.mkdirPath(pathtool.getDistConfigPath(node))

    def initDistCfg(self):
        if not os.path.exists(self.__cfgfile):
            inst = propertiesTool.Properties(self.__cfgfile)
            inst.writeProperties(self.__cfgfile)

    def refreshMoudle(self, moduleName):
        properIns = propertiesTool.Properties(self.__cfgfile)
        property = properIns.readProperties()
        property[moduleName] = 'true'
        properIns.writeProperties(self.__cfgfile)

    def refreshInstMoudle(self, moduleName):
        properIns = propertiesTool.Properties(self.__cfgfile)
        property = properIns.readProperties()
        property[moduleName] = 'true,multi'
        properIns.writeProperties(self.__cfgfile)


class CPVSearchCfg(object):
    def __init__(self):
        self.__modulename = "pvsearch"
        self.__cfgfiles = ['server.yaml']
        self.__properIns = dict()
        self.__property = dict()
        self.__loadProperties()

    def getModuleName(self):
        return self.__modulename

    def getIpInfo(self):
        esInstCfg = CClusterNodeCfg()
        infoMap = dict()
        for node in esInstCfg.getAllDataNodes():
            ip = esInstCfg.getIp(node)
            port = esInstCfg.getPort(node)
            pwd = esInstCfg.getPassword(node)
            hostinfo = dict()
            hostinfo['ip'] = ip
            hostinfo['port'] = port
            hostinfo['pwd'] = pwd
            infoMap[node] = hostinfo
        return infoMap

    def getNodes(self):
        esInstCfg = CClusterNodeCfg()
        infoMap = dict()
        infoMap[self.__modulename] = esInstCfg.getAllDataNodes()
        return infoMap

    def __getProperIns(self, cfgname):
        return self.__properIns[cfgname]

    def __getProperty(self, cfgname):
        return self.__property[cfgname]

    def __loadProperties(self):
        for filename in self.__cfgfiles:
            file_path = os.path.join(pathtool.getTemplateCfgPath(self.__modulename), filename)
            self.__properIns[filename] = file_path
            self.__property[filename] = yamlTool.readYamlfile(file_path)

    def __cpProperties(self, node):
        # clear exist config file, and re-copy from origin template
        pathtool.genMoudleNodeConfig(node, self.__modulename)

    def genPVSearchCfg(self):
        nodeCfg = CClusterNodeCfg()
        for node in nodeCfg.getAllDataNodes():
            self.__cpProperties(node)
            distInst = CdeployDistCfg(node)
            distInst.refreshMoudle(self.__modulename)
            # start to generate server.yaml for node
            filename = 'server.yaml'
            filepath = os.path.join(pathtool.getNodeConfigPath(node, self.__modulename), filename)
            if os.path.exists(filepath):
                yamldatas = self.__getProperty(filename)
                yamldatas['grpc']['port'] = nodeCfg.getTransportTcpPort(node) + nodeCfg.getVectorGrpcPortOffset()
                yamldatas['grpc']['serve_mode'] = nodeCfg.getVectorServeMode()
                yamldatas['grpc']['num_workers'] = nodeCfg.getVectorNumWorkers()
                yamldatas['common']['id_len'] = nodeCfg.getVectorIdlen()
                yamldatas['index']['nprobe'] = nodeCfg.getVectorIndexNprobe()
                yamlTool.writeYamlfile(yamldatas, filepath)


class CRewriterCfg(object):
    def __init__(self):
        self.__jsonfile = os.path.join(pathtool.getConfigPath(), 'rewriter-reranker_nodes_cfg.json')
        self.__jsondatas = jsonTool.readJsonfile(self.__jsonfile)
        self.__rewriterjson = self.__getRewriterjson()
        self.__nodeMap = self.__buildNodeInfoMap()
        self.__modulename = "query-rewriter"
        self.__cfgfiles = ['address.properties']
        self.__properIns = dict()
        self.__property = dict()
        self.__loadProperties()

    def getModuleName(self):
        return self.__modulename

    def __getRewriterjson(self):
        return self.__jsondatas.get('query-rewriter')

    def __getRewriters(self):
        return self.__rewriterjson['hosts']

    def __getPathData(self):
        return str(self.__rewriterjson['path.data']).strip()

    def __getRewriter(self, nodeName):
        return self.__nodeMap[nodeName]

    def getAllNodes(self):
        nodes = []
        for rewriterinfo in self.__getRewriters():
            nodes.append(rewriterinfo['node.name'])

        return nodes

    def getIpInfo(self):
        infoMap = dict()
        for nodename in self.getAllNodes():
            hostinfo = dict()
            hostinfo['ip'] = self.getRewriterIp(nodename)
            hostinfo['port'] = self.getPort(nodename)
            hostinfo['pwd'] = self.getPassword(nodename)
            infoMap[nodename] = hostinfo
        return infoMap

    def getNodes(self):
        infoMap = dict()
        infoMap[self.__modulename] = self.getAllNodes()
        return infoMap

    def __buildNodeInfoMap(self):
        nodeMap = dict()
        for rewriterinfo in self.__getRewriters():
            nodeMap[rewriterinfo['node.name']] = rewriterinfo

        return nodeMap

    def getRewriterIp(self, nodeName):
        return str(self.__getRewriter(nodeName)['ip']).strip()

    def getPort(self, nodeName):
        return self.__getRewriter(nodeName)['port']

    def getUser(self, nodeName):
        return str(self.__getRewriter(nodeName)['user']).strip()

    def getPassword(self, nodeName):
        return str(self.__getRewriter(nodeName)['password']).strip()

    def getRewriterPort(self, nodeName):
        return self.__getRewriter(nodeName)['server.port']

    def getRewriterCategory(self, nodeName):
        return str(self.__getRewriter(nodeName)['server.category']).strip()

    def getRewriterNlpAnalyzerUrl(self, nodeName):
        return str(self.__getRewriter(nodeName)['nlp.analyzer.url']).strip()

    def getRewriterForgottenHDFSPath(self, nodeName):
        if 'forgotten_file_hdfs_path' in self.__getRewriter(nodeName):
            return str(self.__getRewriter(nodeName)['forgotten_file_hdfs_path']).strip()
        else:
            return 'hdfs://hacluster/tenant/SparkleSearchExpsIntervene/queryUrls/all/forgotten_rights.txt'

    def getNodePathLoad(self, node):
        return os.path.join(self.__getPathData(), node, 'receive')

    def getRewriterHomePath(self, node):
        clustNodeCfg = CClusterNodeCfg()
        return os.path.join(clustNodeCfg.getEsInstallDir(), 'modules', node, 'query-rewriter')

    def __getProperIns(self, cfgname):
        return self.__properIns[cfgname]

    def __getProperty(self, cfgname):
        return self.__property[cfgname]

    def getRewriterTemplateCfg(self, filename):
        return os.path.join(pathtool.getModulesConfigPath(), self.__modulename, filename)

    def __loadProperties(self):
        for filename in self.__cfgfiles:
            filepath = os.path.join(pathtool.getTemplateCfgPath(self.__modulename), filename)
            self.__properIns[filename] = propertiesTool.Properties(filepath)
            self.__property[filename] = self.__properIns[filename].readProperties()

    def __cpProperties(self, node):
        # clear exist properties, and re-copy from origin template
        pathtool.genMoudleNodeConfig(node, self.__modulename)

    def genRewriterCfg(self):
        for node in self.getAllNodes():
            self.__cpProperties(node)
            distInst = CdeployDistCfg(node)
            distInst.refreshMoudle(self.__modulename)
            # start to generate address.properties for node
            filename = 'address.properties'
            filepath = os.path.join(pathtool.getNodeConfigPath(node, self.__modulename), filename)
            if os.path.exists(filepath):
                property = self.__getProperty(filename)
                property['server.address'] = self.getRewriterIp(node)
                property['server.port'] = self.getRewriterPort(node)
                property['category'] = self.getRewriterCategory(node)
                property['nlp.analyzer.url'] = self.getRewriterNlpAnalyzerUrl(node)
                property['forgotten_file_hdfs_path'] = self.getRewriterForgottenHDFSPath(node)
                self.__getProperIns(filename).writeProperties(filepath)


class CRerankerCfg(object):
    def __init__(self):
        self.__jsonfile = os.path.join(pathtool.getConfigPath(), 'rewriter-reranker_nodes_cfg.json')
        self.__jsondatas = jsonTool.readJsonfile(self.__jsonfile)
        self.__rerankerjson = self.__getRerankerjson()
        self.__nodeMap = self.__buildNodeInfoMap()
        self.__modulename = "reranker"
        self.__cfgfiles = []
        self.__properIns = dict()
        self.__property = dict()
        self.__loadProperties()

    def getModuleName(self):
        return self.__modulename

    def __getRerankerjson(self):
        return self.__jsondatas.get('reranker')

    def __getRerankers(self):
        return self.__rerankerjson['hosts']

    def __getReranker(self, nodeName):
        return self.__nodeMap[nodeName]

    def getAllNodes(self):
        nodes = []
        for rerankerinfo in self.__getRerankers():
            nodes.append(rerankerinfo['node.name'])

        return nodes

    def getIpInfo(self):
        infoMap = dict()
        for nodename in self.getAllNodes():
            hostinfo = dict()
            hostinfo['ip'] = self.getRerankerIp(nodename)
            hostinfo['port'] = self.getPort(nodename)
            hostinfo['pwd'] = self.getPassword(nodename)
            infoMap[nodename] = hostinfo
        return infoMap

    def getNodes(self):
        infoMap = dict()
        infoMap[self.__modulename] = self.getAllNodes()
        return infoMap

    def __buildNodeInfoMap(self):
        nodeMap = dict()
        for rerankerinfo in self.__getRerankers():
            nodeMap[rerankerinfo['node.name']] = rerankerinfo

        return nodeMap

    def getRerankerIp(self, nodeName):
        return str(self.__getReranker(nodeName)['ip']).strip()

    def getPort(self, nodeName):
        return self.__getReranker(nodeName)['port']

    def getUser(self, nodeName):
        return str(self.__getReranker(nodeName)['user']).strip()

    def getPassword(self, nodeName):
        return str(self.__getReranker(nodeName)['password']).strip()

    def getRerankerPort(self, nodeName):
        return self.__getReranker(nodeName)['server.port']

    def getRerankerHomePath(self, node):
        clustNodeCfg = CClusterNodeCfg()
        return os.path.join(clustNodeCfg.getEsInstallDir(), 'modules', node, 'reranker')

    def __getProperIns(self, cfgname):
        return self.__properIns[cfgname]

    def __getProperty(self, cfgname):
        return self.__property[cfgname]

    def __loadProperties(self):
        for filename in self.__cfgfiles:
            filepath = os.path.join(pathtool.getTemplateCfgPath(self.__modulename), filename)
            self.__properIns[filename] = propertiesTool.Properties(filepath)
            self.__property[filename] = self.__properIns[filename].readProperties()

    def __cpProperties(self, node):
        # clear exist properties, and re-copy from origin template
        pathtool.genMoudleNodeConfig(node, self.__modulename)

    def getRerenkerTemplateCfg(self, filename):
        return os.path.join(pathtool.getModulesConfigPath(), self.__modulename, filename)

    def genRerankerCfg(self):
        for node in self.getAllNodes():
            self.__cpProperties(node)
            distInst = CdeployDistCfg(node)
            distInst.refreshMoudle(self.__modulename)
            # start to generate address.properties for node
            filename = 'server_config.xml'
            instancePath = os.path.join(pathtool.getNodeConfigPath(node, self.__modulename), '.')

            pathtool.mkdirPath(instancePath)

            KVmap = {
                "rank_server_config": {
                    "ip": self.getRerankerIp(node),
                    "port": self.getRerankerPort(node)
                }
            }

            self.__refreshXML(self.getRerenkerTemplateCfg(filename),
                              os.path.join(instancePath, filename), KVmap)

    def __refreshXML(self, srcfile, dstfile, KVs):
        domTree = xmlTool.readXML(srcfile)
        rootNode = domTree.documentElement
        # refresh <rank_server_config> </rank_server_config>
        tagName = 'rank_server_config'
        propertys = rootNode.getElementsByTagName(tagName)
        for property in propertys:
            key = 'ip'
            rankInfo = KVs[tagName]
            element = property.getElementsByTagName(key)[0]

            if key in rankInfo:
                if element.firstChild:
                    element.firstChild.data = rankInfo[key]
                else:
                    element.appendChild(domTree.createTextNode(str(rankInfo[key])))

            key = 'port'
            rankInfo = KVs[tagName]
            element = property.getElementsByTagName(key)[0]
            if key in rankInfo:
                if element.firstChild:
                    element.firstChild.data = rankInfo[key]
                else:
                    element.appendChild(domTree.createTextNode(str(rankInfo[key])))
        xmlTool.writeXML(dstfile, domTree)


class CRankServerCfg(object):
    def __init__(self):
        self.__jsonfile = os.path.join(pathtool.getConfigPath(), 'rewriter-reranker_nodes_cfg.json')
        self.__jsondatas = jsonTool.readJsonfile(self.__jsonfile)
        self.__rankserverjson = self.__getRankServerjson()
        self.__nodeMap = self.__buildNodeInfoMap()
        self.__modulename = "rankserver"
        self.__cfgfiles = []
        self.__properIns = dict()
        self.__property = dict()
        self.__loadProperties()

    def getModuleName(self):
        return self.__modulename

    def __getRankServerjson(self):
        return self.__jsondatas.get('rankserver')

    def __getRankServers(self):
        return self.__rankserverjson['hosts']

    def __getRankServer(self, nodeName):
        return self.__nodeMap[nodeName]

    def getAllNodes(self):
        nodes = []
        for rankserverinfo in self.__getRankServers():
            nodes.append(rankserverinfo['node.name'])

        return nodes

    def getIpInfo(self):
        infoMap = dict()
        for nodename in self.getAllNodes():
            hostinfo = dict()
            hostinfo['ip'] = self.getRankServerIp(nodename)
            hostinfo['port'] = self.getPort(nodename)
            hostinfo['pwd'] = self.getPassword(nodename)
            infoMap[nodename] = hostinfo
        return infoMap

    def getNodes(self):
        infoMap = dict()
        infoMap[self.__modulename] = self.getAllNodes()
        return infoMap

    def __buildNodeInfoMap(self):
        nodeMap = dict()
        for rankserverinfo in self.__getRankServers():
            nodeMap[rankserverinfo['node.name']] = rankserverinfo

        return nodeMap

    def getRankServerIp(self, nodeName):
        return str(self.__getRankServer(nodeName)['ip']).strip()

    def getRankServerMonitorIp(self, nodeName):
        return self.getRankServerIp(nodeName)

    def getPort(self, nodeName):
        return self.__getRankServer(nodeName)['port']

    def getUser(self, nodeName):
        return str(self.__getRankServer(nodeName)['user']).strip()

    def getPassword(self, nodeName):
        return str(self.__getRankServer(nodeName)['password']).strip()

    def getRankServerPort(self, nodeName):
        return self.__getRankServer(nodeName)['server.port']

    def getRankServerMoniterPort(self, nodeName):
        node = self.__getRankServer(nodeName)
        return node.get('server.monitor.port', node['server.port'] + 1)

    def getRankServerHomePath(self, node):
        clustNodeCfg = CClusterNodeCfg()
        return os.path.join(clustNodeCfg.getEsInstallDir(), 'modules', node, 'rankserver')

    def __getProperIns(self, cfgname):
        return self.__properIns[cfgname]

    def __getProperty(self, cfgname):
        return self.__property[cfgname]

    def __loadProperties(self):
        for filename in self.__cfgfiles:
            filepath = os.path.join(pathtool.getTemplateCfgPath(self.__modulename), filename)
            self.__properIns[filename] = propertiesTool.Properties(filepath)
            self.__property[filename] = self.__properIns[filename].readProperties()

    def __cpProperties(self, node):
        # clear exist properties, and re-copy from origin template
        pathtool.genMoudleNodeConfig(node, self.__modulename)

    def getRankServerTemplateCfg(self, filename):
        return os.path.join(pathtool.getModulesConfigPath(), self.__modulename, filename)

    def genRankServerCfg(self):
        for node in self.getAllNodes():
            self.__cpProperties(node)
            distInst = CdeployDistCfg(node)
            distInst.refreshMoudle(self.__modulename)
            # start to generate address.properties for node
            filename = 'ucs.conf'
            instancePath = os.path.join(pathtool.getNodeConfigPath(node, self.__modulename), '.')

            pathtool.mkdirPath(instancePath)

            KVmap = {
                "ip": self.getRankServerIp(node),
                "port": self.getRankServerPort(node),
                "monitor.port": self.getRankServerMoniterPort(node),
                "monitor.ip": self.getRankServerMonitorIp(node)
            }

            self.__refreshUcsConf(self.getRankServerTemplateCfg(filename),
                                  os.path.join(instancePath, filename), KVmap)

    def __refreshUcsConf(self, srcfile, dstfile, KVs):
        with open(srcfile, 'r', encoding='utf-8') as fdSrc, open(dstfile, 'w', encoding='utf-8') as fdDst:
            for line in fdSrc:
                if 'http_ip' in line:
                    fdDst.write('-http_ip={}\n'.format(KVs.get('ip')))
                    continue
                if 'http_port' in line:
                    fdDst.write('-http_port={}\n'.format(KVs.get('port')))
                    continue
                if 'monitor_ip' in line:
                    fdDst.write('-monitor_ip={}\n'.format(KVs.get('monitor.ip')))
                    continue
                if 'monitor_port' in line:
                    fdDst.write('-monitor_port={}\n'.format(KVs.get('monitor.port')))
                    continue
                fdDst.write(line)


class CNodesMap(object):
    def __init__(self):
        self.__nodeMap = self.buildNodesMap()

    def merge2dicts(self, x, y):
        z = x.copy()
        z.update(y)
        return z

    def buildNodesMap(self):
        rewriterIns = CRewriterCfg()
        nodeMap = rewriterIns.getIpInfo()
        rerankerIns = CRerankerCfg()
        nodeMap = self.merge2dicts(nodeMap, rerankerIns.getIpInfo())
        rankserverIns = CRankServerCfg()
        nodeMap = self.merge2dicts(nodeMap, rankserverIns.getIpInfo())
        dispatchIns = CDispatchCfg()
        nodeMap = self.merge2dicts(nodeMap, dispatchIns.getIpInfo())
        optoolsIns = COptoolsCfg()
        nodeMap = self.merge2dicts(nodeMap, optoolsIns.getIpInfo())
        pvSearchIns = CPVSearchCfg()
        nodeMap = self.merge2dicts(nodeMap, pvSearchIns.getIpInfo())
        fileFetcherIns = CFileFetcherCfg()
        nodeMap = self.merge2dicts(nodeMap, fileFetcherIns.getIpInfo())
        rewriterFetcherIns = CRewriterFetcherCfg()
        nodeMap = self.merge2dicts(nodeMap, rewriterFetcherIns.getIpInfo())
        return nodeMap

    def getNodeListOfModule(self, module_name):
        if module_name == CRewriterCfg().getModuleName():
            return list(CRewriterCfg().getIpInfo().keys())
        if module_name == CRerankerCfg().getModuleName():
            return list(CRerankerCfg().getIpInfo().keys())
        if module_name == CDispatchCfg().getModuleName():
            return list(CDispatchCfg().getIpInfo().keys())
        if module_name == COptoolsCfg().getModuleName():
            return list(COptoolsCfg().getIpInfo().keys())
        if module_name == CPVSearchCfg().getModuleName():
            return list(CPVSearchCfg().getIpInfo().keys())
        if module_name == CFileFetcherCfg().getModuleName():
            return list(CFileFetcherCfg().getIpInfo().keys())
        if module_name == CRewriterFetcherCfg().getModuleName():
            return list(CRewriterFetcherCfg().getIpInfo().keys())
        if module_name == CRankServerCfg().getModuleName():
            return list(CRankServerCfg().getIpInfo().keys())

    def getNodeInfo(self, node):
        return self.__nodeMap[node]

    def getIp(self, node):
        return self.getNodeInfo(node)['ip']

    def getPort(self, node):
        return self.getNodeInfo(node)['port']

    def getPassword(self, node):
        return self.getNodeInfo(node)['pwd']

    def getAllSurpportNodes(self):
        return list(self.__nodeMap.keys())


class CModuleNodesMap(object):
    def __init__(self):
        self.__modulesMap = self.buildModulesMap()

    def merge2dicts(self, x, y):
        z = x.copy()
        z.update(y)
        return z

    def buildModulesMap(self):
        rewriterIns = CRewriterCfg()
        modulesMap = rewriterIns.getNodes()

        rerankerIns = CRerankerCfg()
        modulesMap = self.merge2dicts(modulesMap, rerankerIns.getNodes())

        rankserverIns = CRankServerCfg()
        modulesMap = self.merge2dicts(modulesMap, rankserverIns.getNodes())

        dispatchIns = CDispatchCfg()
        modulesMap = self.merge2dicts(modulesMap, dispatchIns.getNodes())

        optoolsIns = COptoolsCfg()
        modulesMap = self.merge2dicts(modulesMap, optoolsIns.getNodes())

        pvSearchIns = CPVSearchCfg()
        modulesMap = self.merge2dicts(modulesMap, pvSearchIns.getNodes())

        fileFetcherIns = CFileFetcherCfg()
        modulesMap = self.merge2dicts(modulesMap, fileFetcherIns.getNodes())

        rewriterFetcherIns = CRewriterFetcherCfg()
        modulesMap = self.merge2dicts(modulesMap, rewriterFetcherIns.getNodes())

        return modulesMap

    def getModuleNodes(self, moduleName):
        return self.__modulesMap[moduleName]

    def getAllSurpportModules(self):
        return list(self.__modulesMap.keys())


class CClusterType(object):
    def __init__(self):
        self.cluster_types = ["default"]

        type_file_path = os.path.join(pathtool.getConfigPath(), 'cluster_types')
        if not os.path.exists(type_file_path):
            return

        with open(type_file_path, 'r', encoding='utf-8') as f:
            cluster_types = f.readlines()

        for type_str in cluster_types:
            type_str = str(type_str).strip()
            if len(type_str) == 0 or type_str.startswith("#"):
                continue
            elif type_str.find("#") != -1:
                type_str = (type_str[:type_str.find("#")]).strip()

            self.cluster_types.append(type_str)

    def getTypes(self):
        return self.cluster_types
