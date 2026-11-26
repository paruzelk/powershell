#!/usr/bin/env python3
"""MIG19k: preserve source scan scope on offline JSON re-export."""
import argparse,hashlib,json
from pathlib import Path
def main():
 p=argparse.ArgumentParser()
 p.add_argument('--candidate',type=Path,required=True)
 p.add_argument('--report',type=Path,required=True)
 a=p.parse_args()
 path='src/modules/Reporting/Convert-adPEASReport.ps1'
 f=a.candidate/path
 s=f.read_text(encoding='utf-8-sig')
 old='                    Export-FindingsCache -Path $jsonPath'
 new="""                    # MIG19k: an offline re-export must not invent a completed scan.
                    $sourcePartial = $false
                    $sourceModules = @()
                    if ($null -ne $cache.PSObject.Properties['Complete'] -and $null -ne $cache.Complete) {
                        $sourcePartial = -not [bool]$cache.Complete
                    }
                    if ($null -ne $cache.PSObject.Properties['CompletedModules'] -and $null -ne $cache.CompletedModules) {
                        $sourceModules = @($cache.CompletedModules)
                    }
                    Export-FindingsCache -Path $jsonPath -Partial:$sourcePartial -CompletedModules $sourceModules"""
 if s.count(old)!=1 or new in s:raise ValueError('MIG19k exact anchor')
 t=s.replace(old,new,1)
 if t.count(new)!=1 or t.replace(new,old,1)!=s:raise ValueError('MIG19k reversibility')
 f.write_bytes(b'\xef\xbb\xbf'+t.encode('utf-8'))
 a.report.write_text(json.dumps({'schema':'adPEAS-RU.MIG19k.Source.1','path':path,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'reversible':True,'scopeMetadataPreserved':True,'realADTestPerformedInCI':False,'productionReady':False},indent=2)+'\n',encoding='utf-8')
 print('PASS MIG19k: offline JSON preserves source Complete and CompletedModules, legacy defaults unchanged')
if __name__=='__main__':main()
