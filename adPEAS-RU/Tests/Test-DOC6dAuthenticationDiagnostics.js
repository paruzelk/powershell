// DOC6d: guard 182 PowerShell diagnostic translations and lexical interpolation.
'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),manifest=JSON.parse(fs.readFileSync(path.join(root,'Localization','DOC6d-AuthenticationDiagnostics.ru-RU.json'),'utf8'));
assert.equal(manifest.schema,'adPEAS-RU.DOC6d.AuthenticationDiagnostics.1');
assert.equal(manifest.files.length,3);
const expected={'src/adPEAS.ps1':40,'src/modules/Core/Connect-adPEAS.ps1':56,'src/modules/Core/Connect-LDAP.ps1':86};
const vars=s=>Array.from(s.matchAll(/\$(?:\{[A-Za-z_][\w:]*\}|\([^)]*\)|[A-Za-z_][\w:]*)/g),m=>m[0]).join('|');
let total=0,duplicates=0;
for(const f of manifest.files){
 assert(Object.hasOwn(expected,f.path),'not an allowlisted path: '+f.path);
 assert.equal(f.messages.length,expected[f.path]);
 const filename=path.join(root,f.path),buffer=fs.readFileSync(filename),text=buffer.toString('utf8');
 assert.equal(buffer.subarray(0,3).toString('hex'),'efbbbf','UTF8 BOM missing: '+f.path);
 const seen=new Set();
 for(const item of f.messages){
  assert(item.sourceLine>0&&item.expectedOccurrences>=1);
  assert(item.from&&item.to&&item.from!==item.to,'empty or identical translation');
  assert(/[А-ЯЁа-яё]/.test(item.to),'Russian translation missing');
  assert.equal(vars(item.from),vars(item.to),'PowerShell variable interpolation changed at '+f.path+':'+item.sourceLine);
  assert(!seen.has(item.from),'duplicate source message: '+f.path+':'+item.sourceLine);
  seen.add(item.from);
  assert(text.includes('"'+item.to+'"'),'localized output missing: '+f.path+':'+item.sourceLine);
  assert(!text.includes('"'+item.from+'"'),'original English literal remains: '+f.path+':'+item.sourceLine);
  if(item.expectedOccurrences>1)duplicates++;
  total++;
 }
}
assert.equal(total,182);
assert(duplicates>0);
console.log('PASS DOC6d: 182 Russian diagnostics (40+56+86), preserved PowerShell interpolations, source BOM and idempotent source selection');
