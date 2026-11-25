#!/usr/bin/env python3
"""MIG19a3: isolated Windows PowerShell processes; never invokes an AD scan."""
import argparse, json, os, subprocess, sys, tempfile, time
from pathlib import Path

VARIANTS = ('adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1','adPEAS.exe')
COMMANDS = {'Invoke-adPEAS','Connect-adPEAS','Disconnect-adPEAS','Get-adPEASHelp'}
HERE = Path(__file__).resolve().parent

def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def run_process(argv, cwd, out, err, timeout=120):
    start=time.monotonic()
    with out.open('wb') as o, err.open('wb') as e:
        try:
            proc=subprocess.run(argv,cwd=cwd,stdin=subprocess.DEVNULL,stdout=o,stderr=e,timeout=timeout,check=False)
            return {'exitCode':proc.returncode,'timedOut':False,'seconds':round(time.monotonic()-start,3)}
        except subprocess.TimeoutExpired:
            return {'exitCode':None,'timedOut':True,'seconds':round(time.monotonic()-start,3)}
        except OSError as exc:
            return {'exitCode':None,'timedOut':False,'launchError':str(exc),'seconds':round(time.monotonic()-start,3)}

def validate_process(result, evidence, stderr, variant, trace):
    errors=[]
    if result.get('timedOut'):errors.append('timeout')
    if result.get('launchError'):errors.append('launch_error')
    if result.get('exitCode') != 0:errors.append('exit_code')
    if stderr.stat().st_size:errors.append('stderr_not_empty')
    obj=None
    if not evidence.is_file():errors.append('missing_evidence')
    else:
        try:
            obj=json.loads(evidence.read_text(encoding='utf-8-sig'))
            if not isinstance(obj,dict):raise ValueError('not object')
            if obj.get('Variant')!=variant or obj.get('Status')!='PASS' or obj.get('RussianQuickStart') is not True:errors.append('bad_evidence')
            commands=obj.get('Commands',{})
            if set(commands)!=COMMANDS or any(not isinstance(v,list) or not all(isinstance(x,str) for x in v) for v in commands.values()):errors.append('bad_commands')
        except (ValueError,TypeError,AttributeError) as exc:
            errors.append('invalid_evidence:'+str(exc));obj=None
    stages=trace.read_text(encoding='utf-8-sig').splitlines() if trace.is_file() else []
    if not stages or not stages[-1].endswith(' EVIDENCE_WRITTEN'):errors.append('incomplete_trace')
    return errors,obj,stages

def quote_ps(s):
    return "'"+str(s).replace("'","''")+"'"

def selftest():
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp);out=p/'out';err=p/'err';ev=p/'evidence';trace=p/'trace'
        result=run_process([sys.executable,'-c','print("hello")'],p,out,err)
        assert result['exitCode']==0 and out.read_bytes().strip()==b'hello'
        errors,_,_=validate_process(result,ev,err,'adPEAS.ps1',trace)
        assert 'missing_evidence' in errors and 'incomplete_trace' in errors
        write_json(ev,{'Variant':'adPEAS.ps1','Status':'PASS','RussianQuickStart':True,'Commands':{n:['Verbose'] for n in COMMANDS}})
        trace.write_text('test EVIDENCE_WRITTEN\n',encoding='utf-8')
        assert not validate_process(result,ev,err,'adPEAS.ps1',trace)[0]
        result=run_process([sys.executable,'-c','import sys; print("failure",file=sys.stderr); sys.exit(7)'],p,out,err)
        assert result['exitCode']==7 and set(validate_process(result,ev,err,'adPEAS.ps1',trace)[0])=={'exit_code','stderr_not_empty'}
        result=run_process([sys.executable,'-c','import time; time.sleep(5)'],p,out,err,timeout=0.2)
        assert result['timedOut'] and result['exitCode'] is None
        ev.write_text('not json',encoding='utf-8')
        assert any(x.startswith('invalid_evidence:') for x in validate_process(result,ev,err,'adPEAS.ps1',trace)[0])
    print('PASS: subprocess exit codes, timeout, stderr, mandatory JSON and trace gates')

def main():
    p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path);p.add_argument('--report',type=Path);p.add_argument('--diagnostics',type=Path);p.add_argument('--selftest',action='store_true');a=p.parse_args()
    if a.selftest:selftest();return 0
    if not (a.candidate and a.report and a.diagnostics):p.error('candidate, report and diagnostics are required')
    root=a.candidate.resolve(strict=True);report=a.report.resolve();diag=a.diagnostics.resolve()
    diag.mkdir(parents=True,exist_ok=False)
    ps=Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
    probe=HERE/'Probe-MIG19a3.ps1'
    results=[]
    for v in VARIANTS:
        out=diag/(v+'.stdout.txt');err=diag/(v+'.stderr.txt');ev=diag/(v+'.json');trace=diag/(v+'.trace.txt')
        if v=='adPEAS.exe':
            command='& '+quote_ps(probe)+' -Candidate '+quote_ps(root)+' -Variant '+quote_ps(v)+' -Evidence '+quote_ps(ev)+' -Trace '+quote_ps(trace)
            argv=[str(root/v),'-Command',command]
        else:
            argv=[str(ps),'-NoLogo','-NoProfile','-NonInteractive','-File',str(probe),'-Candidate',str(root),'-Variant',v,'-Evidence',str(ev),'-Trace',str(trace)]
        result=run_process(argv,root,out,err)
        errors,obj,stages=validate_process(result,ev,err,v,trace)
        row={'variant':v,**result,'errors':errors,'stages':stages,'evidence':obj,'stdoutBytes':out.stat().st_size,'stderrBytes':err.stat().st_size}
        results.append(row)
        write_json(diag/(v+'.process.json'),row)
        print(f"{v}: exit={result['exitCode']} stages={len(stages)} errors={errors}",flush=True)
    reference=results[0]['evidence']
    for row in results:
        if not reference or not row['evidence'] or row['evidence'].get('Commands')!=reference.get('Commands'):
            row['errors'].append('parameter_parity_unverified_or_mismatch')
    passed=all(not r['errors'] for r in results) and len(results)==5
    summary={'schema':'adPEAS-RU.MIG19a3.Runtime.1','status':'PASS' if passed else 'FAIL','results':results,'realADTestPerformed':False}
    write_json(report,summary);write_json(diag/'summary.json',summary)
    print('PASS all five variants' if passed else 'FAIL runtime smoke; see diagnostic artifact')
    return 0 if passed else 1

if __name__=='__main__':sys.exit(main())
