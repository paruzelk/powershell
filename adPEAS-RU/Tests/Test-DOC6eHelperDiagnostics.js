'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const data=JSON.parse(fs.readFileSync(path.join(root,'Localization','DOC6e-HelperDiagnostics.ru-RU.json'),'utf8'));
assert.equal(data.schema,'adPEAS-RU.DOC6e.HelperDiagnostics.1');
const expected=new Map([['src/modules/Helpers/Resolve-adPEASName.ps1',62],['src/modules/Helpers/Test-IsPrivileged.ps1',47],['src/modules/Helpers/Get-adPEASSession.ps1',1]]);
assert.equal(data.files.length,3);
const vars=s=>Array.from(s.matchAll(/\$(?:\{[^}]+\}|\([^)]*\)|[A-Za-z_][\w:]*)/g),x=>x[0]).join('|');
let count=0;
for(const e of data.files){
 assert(expected.has(e.path),'unexpected translation file '+e.path);
 assert.equal(e.messages.length,expected.get(e.path));
 const bytes=fs.readFileSync(path.join(root,e.path)),s=bytes.toString('utf8');
 assert.equal(bytes.subarray(0,3).toString('hex'),'efbbbf','missing PowerShell BOM: '+e.path);
 const seen=new Set();
 for(const m of e.messages){
  assert(m.line>=1&&m.occurrences>=1&&m.from&&m.to&&m.from!==m.to);
  assert(/[А-ЯЁа-яё]/.test(m.to),'expected Russian: '+m.line);
  assert.equal(vars(m.from),vars(m.to),'PowerShell interpolation altered: '+e.path+':'+m.line);
  assert(!seen.has(m.from),'duplicate source text');
  seen.add(m.from);
  assert(s.includes('"'+m.to+'"'),'translated literal missing: '+e.path+':'+m.line);
  assert(!s.includes('"'+m.from+'"'),'English literal remains: '+e.path+':'+m.line);
  count++;
 }
}
assert.equal(count,110);
assert(fs.readFileSync(path.join(root,'src/modules/Helpers/Get-adPEASSession.ps1'),'utf8').includes('Write-Host "Connection is healthy"'),'do not translate help example');
console.log('PASS DOC6e: 110 scoped translations, preserved PowerShell variables, UTF-8 BOM and help example');
