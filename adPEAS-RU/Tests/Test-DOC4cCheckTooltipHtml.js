// DOC4c standalone, AD-free browser rendering test.
// Uses the actual generated JavaScript and its original 125 ObjectTypes.
'use strict';
const fs=require('fs');
const path=require('path');
const vm=require('vm');
const assert=require('assert');
const root=path.resolve(__dirname,'..');
const js=fs.readFileSync(path.join(root,'src/modules/Reporting/templates/report-scripts.js'),'utf8');
function getEmbeddedCatalog(name){
  const pattern=new RegExp('\\bconst\\s+'+name+'\\s*=\\s*(\\{[^\\n\\r]+\\});');
  const match=js.match(pattern);
  assert(match,'missing embedded '+name);
  return JSON.parse(match[1]);
}
assert(process.argv[2],'DOC4c: provide an offline source ObjectTypes JSON fixture from the exact pinned source');
const canonical=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const translated=getEmbeddedCatalog('ruDetailedCheckTooltips');
assert.strictEqual(Object.keys(canonical).length,125);
assert.strictEqual(Object.keys(translated).length,125);
assert.deepStrictEqual(Object.keys(canonical).sort(),Object.keys(translated).sort());
let criteria=0;
Object.keys(canonical).forEach(id=>{
  const source=canonical[id],ru=translated[id];
  assert.strictEqual(typeof source.whyItMatters,'string');
  assert(ru.whyItMatters.match(/[А-Яа-яЁё]/),id+' why is not Russian');
  assert.strictEqual(source.whatWeCheck.length,ru.whatWeCheck.length,id+' criteria count');
  criteria+=ru.whatWeCheck.length;
  ru.whatWeCheck.forEach((bullet,j)=>{
    assert(bullet.match(/[А-Яа-яЁё]/),id+' criterion '+j+' is not Russian');
    assert(!bullet.includes('Проверенные параметры и обнаруженные объекты приведены'),id+' is placeholder');
  });
});
assert.strictEqual(criteria,490);
const injectedMarker='        // DOC4c: complete human-reviewed RU descriptions';
const endMarker='        // Scoring context data for context-aware risk calculation';
const start=js.indexOf(injectedMarker);
const doc4dStart=js.indexOf('        // DOC4d: verified field-scoped display translations',start);
const end=doc4dStart>=0 ? doc4dStart : js.indexOf(endMarker,start);
assert(start>=0 && end>start,'DOC4c injection boundaries missing');
const injection=js.slice(start,end);
const original=JSON.parse(JSON.stringify(canonical));
// Recreate the exact prior Apply-Catalogs behavior. It stores the source
// criteria in originalEnglish before overwriting whatWeCheck with two short RU
// summary items. The old DOC4c guard erroneously checked these short items,
// so production HTML crashed although the former synthetic fixture passed.
const genericRU=getEmbeddedCatalog('ruCheckContext');
assert.deepStrictEqual(Object.keys(genericRU).sort(),Object.keys(canonical).sort());
Object.entries(canonical).forEach(([id,check])=>{
  check.originalEnglish={
    whyItMatters:check.whyItMatters,
    whatWeCheck:check.whatWeCheck.slice(),
    secureMessage:check.secureMessage,
    filteringNote:check.filteringNote
  };
  check.title=genericRU[id].title;
  check.summary=genericRU[id].summary;
  check.whyItMatters=genericRU[id].whyItMatters;
  check.whatWeCheck=genericRU[id].whatWeCheck.slice();
  if(check.secureMessage) check.secureMessage=genericRU[id].secureMessage;
  if(check.filteringNote) check.filteringNote=genericRU[id].filteringNote;
});
assert.strictEqual(canonical.BitLockerRecoveryKey.whatWeCheck.length,2);
assert.strictEqual(canonical.BitLockerRecoveryKey.originalEnglish.whatWeCheck.length,3);
const fakeWindow={};
vm.runInNewContext(injection,{checkDescriptions:canonical,window:fakeWindow},{timeout:3000});
assert.strictEqual(fakeWindow.adPEASRUCheckTooltipAudit.translatedObjectTypes,125);
assert.strictEqual(fakeWindow.adPEASRUCheckTooltipAudit.translatedCriteria,490);
const escapeHtml=x=>String(x).replace(/&/g,'&amp;').replace(/</g,'&lt;')
 .replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
const builderStart=js.indexOf('function buildCheckTooltipHtml(');
assert(builderStart>=0,'check-tooltip renderer not found');
const builderMatch=js.slice(builderStart).match(/^(function buildCheckTooltipHtml\([\s\S]*?\n        \})\s*\n\s*\/\/ ={12,}/);
assert(builderMatch,'cannot isolate actual check-tooltip renderer');
const render=vm.runInNewContext('('+builderMatch[1]+')',{escapeHtml},{timeout:3000});
for(const [id,check] of Object.entries(canonical)){
  assert(check.ruDetailedCheckReady===true,id+' translation flag missing');
  assert.deepStrictEqual(Array.from(check.whatWeCheck),Array.from(translated[id].whatWeCheck),id+' bullets not applied');
  assert.strictEqual(check.whyItMatters,translated[id].whyItMatters,id+' why not applied');
  assert.strictEqual(check.originalEnglish.whyItMatters,original[id].whyItMatters,id+' upstream why changed');
  assert.deepStrictEqual(Array.from(check.originalEnglish.whatWeCheck),Array.from(original[id].whatWeCheck),id+' upstream criteria changed');
  assert.strictEqual(check.primaryFindingId,original[id].primaryFindingId,id+' scoring/finding identifier changed');
  assert.strictEqual(check.secureMessage,original[id].secureMessage,id+' secure status changed');
  const result=render(check,'synthetic check','note');
  assert(!result.includes('Подробные критерии проверки (оригинал EN)'),id+' English panel shown');
  assert(result.includes(escapeHtml(check.whyItMatters)),id+' detailed reason hidden');
  assert.strictEqual((result.match(/<li>/g)||[]).length,check.whatWeCheck.length,id+' rendered criterion count');
  check.whatWeCheck.forEach((bullet,j)=>{
    assert(result.includes('<li>'+escapeHtml(bullet)+'</li>'),id+' item '+j+' not rendered');
  });
}
const rbcd=render(canonical.RBCDelegation,'RBCD test','secure');
assert(rbcd.includes('msDS-AllowedToActOnBehalfOfOtherIdentity'));
assert(rbcd.includes('Не проверяется, кто может записывать этот атрибут'));
assert.strictEqual((rbcd.match(/<li>/g)||[]).length,5);
assert(!rbcd.includes('RBCD allows specified accounts to impersonate users'));
assert(!rbcd.includes('Подробные критерии проверки (оригинал EN)'));
// Verify that a changed upstream criterion count blocks the build rather than
// hiding untranslated details.
const altered=JSON.parse(JSON.stringify(canonical));
altered.RBCDelegation.originalEnglish.whatWeCheck.pop();
assert.throws(()=>vm.runInNewContext(injection,{
  checkDescriptions:altered,window:{}
},{timeout:3000}),/DOC4c: detailed criterion count or type differs/);
// Even when a legacy brief summary has any number of items, the original
// pinned English criterion list must govern the completeness decision.
const shortened=JSON.parse(JSON.stringify(canonical));
shortened.BitLockerRecoveryKey.whatWeCheck=['Это временный перевод'];
vm.runInNewContext(injection,{checkDescriptions:shortened,window:{}},{timeout:3000});
assert.strictEqual(shortened.BitLockerRecoveryKey.whatWeCheck.length,3);
// HTML data is escaped inside the tooltip instead of interpreted.
const malicious=Object.assign({},canonical.RBCDelegation,{
  whyItMatters:'Проверка <img src=x onerror=alert(1)>',
  whatWeCheck:['Не выполнять <script>alert(1)</script>']
});
const safe=render(malicious,'synthetic','note');
assert(!safe.includes('<img src=x'));
assert(!safe.includes('<script>alert(1)'));
assert(safe.includes('&lt;img'));
console.log('PASS DOC4c: all 125 tooltips, 490 criteria 1:1, RBCD 5/5, no EN panels, XSS escaping, mismatch fail-closed; no domain contacted');
