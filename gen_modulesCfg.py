#!/usr/bin/env python
# encoding: utf-8
import argparse
import os
import sys
import json
import traceback

import pathtool


def parse_config():
    parser = argparse.ArgumentParser(description="generate deploy configurations for modules")
    supportModules = ','.join(pathtool.getModulesList())
    parser.add_argument('--module', type=str, default='query-rewriter,reranker',
                        help='specify modules in support modules: ' + supportModules)
    return parser.parse_args()


def getSurpportModule():
    modules = ['query-rewriter', 'reranker', 'rankserver']
    return modules


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


class CGenModulescfg:
    def __init__(self):
        self.jsonfile = os.path.join(pathtool.getConfigPath(), 'rewriter-reranker_nodes_cfg_template.json')
        self.jsondatas = self.readJsonfile()

    def rewriteJsonfile(self):
        configfile = os.path.join(pathtool.getConfigPath(), 'rewriter-reranker_nodes_cfg.json')
        fp = open(configfile, 'w')
        try:
            fp.write(json.dumps(self.jsondatas, sort_keys=True, indent=4))
        except Exception:
            print("rewrite data into json file failed")
            raise 
        finally:
            fp.close()

    def readJsonfile(self):
        fp = open(self.jsonfile, 'r')
        try:
            return json.load(fp)
        except Exception:
            print("read data from json file failed")
            raise
        finally:
            fp.close()

    def refresh(self):
        self.rewriteJsonfile()


if len(sys.argv) >= 0:
    try:
        params = parse_config()
        specifyMods = getSpecifyModule(params)
        surpportMods = getSurpportModule()
        for modules in specifyMods:
            if modules in surpportMods:
                dbins = CGenModulescfg()
                dbins.refresh()
            print('generate config for: ' + modules + ' ok')
    except Exception as e:
        print((repr(e)))
        traceback.print_tb(e.__traceback__)
        sys.exit(1)
else:
    print('argv num error')
    sys.exit(1)
