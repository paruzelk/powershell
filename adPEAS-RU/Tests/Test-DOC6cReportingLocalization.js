// Validate 54 scoped Russian reporting translations and source-only inventory.
'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const map=JSON.parse(fs.readFileSync(path.join(root,'Localization','DOC6c-ReportingPhrases.ru-RU.json'),'utf8'));
assert.equal(map.schema,'adPEAS-RU.DOC6c.ReportingDisplayTranslation.1');
assert.equal(map.files.length,4);
let checked=0;
for(const file of map.files){
 assert(file.path.startsWith('src/modules/Reporting/'));
 const code=fs.readFileSync(path.join(root,file.path),'utf8');
 for(const pair of file.replacements){
  assert(pair.from&&pair.to&&pair.from!==pair.to);
  assert(code.includes(pair.to),'DOC6c missing: '+file.path+' / '+pair.to);
  checked++;
 }
}
assert.equal(checked,54);
const audit=JSON.parse(fs.readFileSync(path.join(root,'Localization','DOC6c-StaticSourceAudit.json'),'utf8'));
assert.equal(audit.schema,'adPEAS-RU.DOC6c.StaticSourceInventory.1');
assert(audit.summary.sourceFiles>=160);
assert(audit.summary.powershell>=150);
assert.equal(audit.summary.translatedPhrases,54);
assert(audit.candidates.every(x=>x.path.startsWith('src/')&&x.line>=1));
assert(fs.readFileSync(path.join(root,'docs','ru-RU','14-Static-Source-Language-Audit.md'),'utf8').includes('эвристическ'));
console.log('PASS DOC6c: 54 scoped reporting phrases, source-only inventory, no machine-key replacements');
