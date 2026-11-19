// DOC6i security-check messages: exact source, lexical tokens, UTF-8 BOM.
'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const specs=[
 ['src/modules/Checks/Creds/Get-BitLockerRecoveryKeyAccess.ps1',17],
 ['src/modules/Checks/Rights/Get-AddComputerRights.ps1',17],
 ['src/modules/Checks/Creds/Get-LAPSCredentialAccess.ps1',16],
 ['src/modules/Checks/Computer/Get-InfrastructureServers.ps1',15],
 ['src/modules/Checks/GPO/Get-GPOLocalGroupMembership.ps1',15]
];
const vars=s=>[...s.matchAll(/\$(?:\{[^}]+\}|\([^)]*\)|[A-Za-z_][\w:]*)/g)].map(m=>m[0]).join('|');
const nonStrings=s=>s.replace(/"[^"]*"/g,'""');
let total=0;
for(let i=0;i<specs.length;i++){
 const [p,count]=specs[i];
 const manifest=JSON.parse(fs.readFileSync(path.join(root,'Localization','DOC6i-Check'+(i+1)+'.json'),'utf8'));
 assert.equal(manifest.schema,'adPEAS-RU.DOC6i.SecurityLogs.1');
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
assert.equal(total,80);
const bitlocker=fs.readFileSync(path.join(root,specs[0][0]),'utf8');
const rights=fs.readFileSync(path.join(root,specs[1][0]),'utf8');
const laps=fs.readFileSync(path.join(root,specs[2][0]),'utf8');
const infra=fs.readFileSync(path.join(root,specs[3][0]),'utf8');
const gpo=fs.readFileSync(path.join(root,specs[4][0]),'utf8');
assert(bitlocker.includes('msFVE-RecoveryPassword')&&bitlocker.includes('msFVE-RecoveryInformation'),'BitLocker LDAP attributes changed');
assert(rights.includes('wellKnownObjects')&&rights.includes('IncludePrivileged'),'computer creation rights keys changed');
assert(laps.includes('encryptedComputers')&&laps.includes('distinguishedName'),'LAPS query identifiers changed');
assert(infra.includes('Entra ID Connect')&&infra.includes('SPN'),'infrastructure provider markers changed');
assert(gpo.includes('BUILTIN')&&gpo.includes('SYSVOL'),'GPO local groups identifiers changed');
console.log('PASS DOC6i: 80 localized security diagnostics (17 BitLocker, 17 add computer rights, 16 LAPS, 15 infra, 15 local GPO), source and variables preserved');
