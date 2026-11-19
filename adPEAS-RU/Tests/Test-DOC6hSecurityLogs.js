// DOC6h security-check messages: exact source, lexical tokens, UTF-8 BOM.
'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const specs=[
 ['src/modules/Checks/Application/Get-ExchangeInfrastructure.ps1',27],
 ['src/modules/Checks/Creds/Get-CredentialExposure.ps1',27],
 ['src/modules/Checks/GPO/Get-GPOPermissions.ps1',22],
 ['src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1',22],
 ['src/modules/Checks/ADCS/Get-WeakCertificateMapping.ps1',17]
];
const vars=s=>[...s.matchAll(/\$(?:\{[^}]+\}|\([^)]*\)|[A-Za-z_][\w:]*)/g)].map(m=>m[0]).join('|');
const nonStrings=s=>s.replace(/"[^"]*"/g,'""');
let total=0;
for(let i=0;i<specs.length;i++){
 const [p,count]=specs[i];
 const manifest=JSON.parse(fs.readFileSync(path.join(root,'Localization','DOC6h-Check'+(i+1)+'.json'),'utf8'));
 assert.equal(manifest.schema,'adPEAS-RU.DOC6h.SecurityLog.1');
 assert.equal(manifest.path,p);
 assert.equal(manifest.entries.length,count);
 const bytes=fs.readFileSync(path.join(root,p)),lines=bytes.toString('utf8').split(/\r?\n/);
 assert.equal(bytes.subarray(0,3).toString('hex'),'efbbbf','missing PowerShell BOM '+p);
 const visited=new Set();
 for(const row of manifest.entries){
  assert(row.line>=1 && Number.isInteger(row.line) && row.line<=lines.length);
  assert(!visited.has(row.line),'duplicate line '+p+':'+row.line);
  visited.add(row.line);
  assert(row.original.includes('Write-Log "')&&row.target.includes('Write-Log "'),'only log output allowed');
  assert(/[А-ЯЁа-яё]/.test(row.target),'Russian text missing '+p+':'+row.line);
  assert.equal(vars(row.original),vars(row.target),'interpolations changed '+p+':'+row.line);
  assert.equal(nonStrings(row.original),nonStrings(row.target),'executable code changed '+p+':'+row.line);
  assert.equal(lines[row.line-1],row.target,'unexpected localized line '+p+':'+row.line);
  total++;
 }
}
assert.equal(total,115);
const gpo=fs.readFileSync(path.join(root,specs[2][0]),'utf8');
const msa=fs.readFileSync(path.join(root,specs[3][0]),'utf8');
const esc=fs.readFileSync(path.join(root,specs[4][0]),'utf8');
assert(gpo.includes('PropagationFlags')&&gpo.includes('SYSVOL')&&gpo.includes('IncludePrivileged'),'GPO technical keys changed');
assert(msa.includes('msDS-ManagedPassword')&&msa.includes('msDS-GroupMSAMembership'),'gMSA technical keys changed');
assert(esc.includes('altSecurityIdentities'),'ESC14 attribute changed');
console.log('PASS DOC6h: 115 translated logs, 5 checks, source lines, code and PowerShell tokens preserved');
