// DOC6g: strict source line regression, variables, security data and user-facing NTAuth text.
'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const map=JSON.parse(fs.readFileSync(path.join(root,'Localization','DOC6g-SecurityChecks.ru-RU.json'),'utf8'));
assert.equal(map.schema,'adPEAS-RU.DOC6g.SecurityChecks.1');
const expected=new Map([
 ['src/modules/Checks/Accounts/Get-PrivilegedGroupMembers.ps1',67],
 ['src/modules/Checks/Domain/Get-DomainInformation.ps1',38],
 ['src/modules/Checks/ADCS/Get-ADCSVulnerabilities.ps1',53]
]);
assert.equal(map.files.length,3);
const variables=s=>Array.from(s.matchAll(/\$(?:\{[^}]+\}|\([^)]*\)|[A-Za-z_][\w:]*)/g),m=>m[0]).join('|');
const stripStrings=s=>s.replace(/"[^"]*"/g,'""');
let count=0,ntauth=0;
for(const f of map.files){
 assert(expected.has(f.path),'unapproved security module: '+f.path);
 assert.equal(f.entries.length,expected.get(f.path));
 const b=fs.readFileSync(path.join(root,f.path)),source=b.toString('utf8'),lines=source.split(/\r?\n/);
 assert.equal(b.subarray(0,3).toString('hex'),'efbbbf','missing PowerShell BOM: '+f.path);
 const seen=new Map();
 for(const e of f.entries){
  assert(e.line>=1&&e.original&&e.target&&e.original!==e.target);
  assert(/[А-ЯЁа-яё]/.test(e.target),'missing translation '+f.path+':'+e.line);
  assert.equal(variables(e.original),variables(e.target),'changed PowerShell interpolation '+f.path+':'+e.line);
  assert.equal(stripStrings(e.original),stripStrings(e.target),'changed executable code '+f.path+':'+e.line);
  assert(!seen.has(e.original)||seen.get(e.original)===e.target,'conflicting repeated phrase '+f.path+':'+e.line);
  seen.set(e.original,e.target);
  assert.equal(lines[e.line-1],e.target,'incorrect localized line '+f.path+':'+e.line);
  if(f.path.includes('ADCS/')&&[285,286,289,290].includes(e.line))ntauth++;
  count++;
 }
}
assert.equal(count,158);
assert.equal(ntauth,4,'NTAuth report paragraphs must be translated completely');
const adcs=fs.readFileSync(path.join(root,'src/modules/Checks/ADCS/Get-ADCSVulnerabilities.ps1'),'utf8');
assert(adcs.includes("'NTAUTH_FOREIGN_ISSUER'"),'NTAuth finding ID changed');
assert(adcs.includes("'PKI_CERTIFICATE_EXPIRED'"),'PKI finding ID changed');
assert(adcs.includes('dangerousADPermissions:'),'machine attribute label changed');
const group=fs.readFileSync(path.join(root,'src/modules/Checks/Accounts/Get-PrivilegedGroupMembers.ps1'),'utf8');
assert(group.includes('AdminSDHolder')&&group.includes('IncludePrivileged'),'security identifiers changed');
console.log('PASS DOC6g: 158 scoped checks translations (67 privileged groups, 38 domain, 53 AD CS), NTAuth and machine data preserved');
