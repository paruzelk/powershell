// DOC6f: enforce scoped line-only UI translations and unchanged PowerShell semantics.
'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const map=JSON.parse(fs.readFileSync(path.join(root,'Localization','DOC6f-VisibleOutputsAndHelp.ru-RU.json'),'utf8'));
assert.equal(map.schema,'adPEAS-RU.DOC6f.VisibleOutputsAndHelp.1');
const expected=new Map([
 ['src/modules/Helpers/Get-adPEASSession.ps1',51],
 ['src/modules/Core/adPEAS-Messages.ps1',62]
]);
assert.equal(map.files.length,2);
const vars=s=>Array.from(s.matchAll(/\$(?:\{[^}]+\}|\([^)]*\)|[A-Za-z_][\w:]*)/g),m=>m[0]).join('|');
const maskStrings=s=>s.replace(/"(?:[^"\\]|\\.)*"/g,'""');
let count=0;
for(const f of map.files){
 assert(expected.has(f.path),'file outside UI allowlist: '+f.path);
 assert.equal(f.entries.length,expected.get(f.path));
 const b=fs.readFileSync(path.join(root,f.path)),text=b.toString('utf8'),lines=text.split(/\r?\n/);
 assert.equal(b.subarray(0,3).toString('hex'),'efbbbf','PowerShell UTF8 BOM missing: '+f.path);
 const seen=new Map();
 for(const e of f.entries){
  assert(e.line>=1&&e.original&&e.target&&e.original!==e.target);
  assert(!seen.has(e.original)||seen.get(e.original)===e.target,'contradictory translation for duplicate line '+f.path+':'+e.line);
  seen.set(e.original,e.target);
  assert(/[А-ЯЁа-яё]/.test(e.target),'untranslated target '+e.line);
  assert.equal(vars(e.original),vars(e.target),'PowerShell interpolation altered '+f.path+':'+e.line);
  assert.equal(maskStrings(e.original),maskStrings(e.target),'non-string code altered '+f.path+':'+e.line);
  assert.equal(lines[e.line-1],e.target,'expected exact localized line '+f.path+':'+e.line);
  assert(!text.split(/\r?\n/).includes(e.original),'English source line still present: '+f.path+':'+e.line);
  count++;
 }
}
assert.equal(count,113);
const session=fs.readFileSync(path.join(root,'src/modules/Helpers/Get-adPEASSession.ps1'),'utf8');
const msg=fs.readFileSync(path.join(root,'src/modules/Core/adPEAS-Messages.ps1'),'utf8');
assert(session.includes('HealthStatus = "Healthy"'),'do not translate internal status');
assert(session.includes('return $true')&&session.includes('return $false'),'preserve -Quiet return semantics');
assert(msg.includes("[ValidateSet('Permission', 'NotFound', 'Operation', 'Connection', 'HealthCheck')]"),'preserve Show-Error enum');
assert(msg.includes('Show-Line "Get-Help Connect-adPEAS -Examples"'),'preserve runnable help command');
assert(msg.includes('Show-KeyValue "Connect-adPEAS"'),'preserve command identifiers');
console.log('PASS DOC6f: 113 localized lines (51 session + 62 messages/help); command semantics, interpolation and BOM unchanged');
