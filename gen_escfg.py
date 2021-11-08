#!/usr/bin/env python
# encoding: utf-8
import os
import sys
import json
import traceback

import pathtool


class CGenEscfg:
    def __init__(self):
        self.jsonfile = os.path.join(pathtool.getConfigPath(), 'cluster_nodes_cfg_template.json')
        self.jsondatas = self.readJsonfile()

    def rewriteJsonfile(self):
        configfile = os.path.join(pathtool.getConfigPath(), 'cluster_nodes_cfg.json')
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
        dbins = CGenEscfg()
        dbins.refresh()
        print('generate cluster nodes config %s ok' % os.path.join(pathtool.getConfigPath(), 'cluster_nodes_cfg.json'))
    except Exception as e:
        print((repr(e)))
        traceback.print_tb(e.__traceback__)
        sys.exit(1)
else:
    print('argv num error')
    sys.exit(1)
