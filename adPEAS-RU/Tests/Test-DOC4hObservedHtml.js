// DOC4h: test real renderer strings with synthetic DOM; never load domain reports.
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(root,'src/modules/Reporting/templates/report-scripts.js'),'utf8');
const html=fs.readFileSync(path.join(root,'src/modules/Reporting/templates/report-template.html'),'utf8');
assert(source.includes("badge.title = 'Оценка риска (нажмите для подробностей)';"));
assert(!source.includes("badge.title = 'Risk Score (click for details)';"));
assert(source.includes('badge.dataset.scoreBreakdown = JSON.stringify(breakdown);'));
assert(html.includes('id="doc4hSummaryCountNote" hidden'));
const marker='        // DOC4h: observed synthetic labels and DC clock note only; no AD values changed.';
const nextStage='        // DOC4i: context-specific GPO display labels; do not rewrite GPO identity.';
const end=whole.includes(nextStage)?nextStage:'        // Scoring context data for context-aware risk calculation';
const pos=source.indexOf(marker),next=source.indexOf(end,pos);
assert(pos>=0&&next>pos,'DOC4h handler present');
const block=source.slice(pos,next);
const translateKeys={
 activityStatus:'Состояние активности',
 adSubnet:'Подсеть AD',
 computerCount:'Количество компьютеров',
 operatingSystems:'Операционные системы',
 organizationalUnits:'Организационные подразделения',
 domainControllerCount:'Количество контроллеров домена',
 domainControllerTime:'Время контроллера домена'
};
function textNode(value){return {nodeType:3,nodeValue:value};}
function element(value,nested=false){
 const n=textNode(value);
 return {textContent:value,childNodes:nested?[n,textNode(' icon')]:[n],firstChild:n};
}
function row(key,label=key,value='S-1-5-21-111-222-333-500',nested=false){
 const name=element(label,nested),val=element(value);
 return {key,name,val,getAttribute:k=>k==='data-attr-name'?key:null,
  querySelector:k=>k==='.attr-name'?name:k==='.attr-value'?val:null};
}
const rows=[
 ...Object.keys(translateKeys).map(key=>row(key,key,key==='domainControllerTime'?'2026-11-13 14:18:08 UTC (skew: -2s)':'S-1-5-21-111-222-333-500')),
 row('activityStatus','Уже переведено','INACTIVE'),
 row('adSubnet','adSubnet','192.0.2.0/24',true),
 row('domainControllerTime','domainControllerTime','2026-11-13 UTC (skew: unknown)'),
 ...['objectSid','userAccountControl','ms-DS-MachineAccountQuota','sAMAccountName'].map(key=>row(key))
];
let init=null;
const document={addEventListener:(event,fn)=>{assert.equal(event,'DOMContentLoaded');assert.equal(init,null);init=fn;},
 querySelectorAll:(q)=>{assert.equal(q,'.attr-row[data-attr-name]');return rows;}};
const window={};
vm.runInNewContext(block,{document,window,Node:{TEXT_NODE:3}},{timeout:3000});
init();
for(let i=0;i<Object.keys(translateKeys).length;i++){
 const r=rows[i];
 assert.equal(r.name.firstChild.nodeValue,translateKeys[r.key],r.key);
 assert.equal(r.key,Object.keys(translateKeys)[i]);
 if(r.key==='domainControllerTime') assert.equal(r.val.firstChild.nodeValue,'2026-11-13 14:18:08 UTC (расхождение: -2 с)');
 else assert.equal(r.val.firstChild.nodeValue,'S-1-5-21-111-222-333-500');
}
assert.equal(window.adPEASRUDOC4h.dictionaryEntries,7);
assert.equal(window.adPEASRUDOC4h.translatedLabels,8);
assert.equal(window.adPEASRUDOC4h.translatedClockValues,1);
assert.equal(rows[7].name.firstChild.nodeValue,'Уже переведено');
assert.equal(rows[8].name.firstChild.nodeValue,'adSubnet');
assert.equal(rows[9].val.firstChild.nodeValue,'2026-11-13 UTC (skew: unknown)');
for(const r of rows.slice(10)) assert.equal(r.name.firstChild.nodeValue,r.key);
// Test the original summary counting procedure, including completed items.
const start=source.indexOf('        function updateSidebarCounts() {');
const stop=source.indexOf('        function toggleHideCompleted()',start);
assert(start>=0&&stop>start,'expected original summary procedure');
const update=source.slice(start,stop);
assert(update.includes("summaryCard.setAttribute('aria-label'"));
assert(update.includes('summaryCountNote.hidden=false'));
const types=['finding','hint','note','secure'];
const labels=['Нарушения','Предупреждения','Сведения','Безопасно'];
const controls=types.map((type,i)=>{
 const value={textContent:'999',closest:selector=>{assert.equal(selector,'.summary-card');return controls[i].card;}};
 const card={aria:'старое число',querySelector:selector=>{assert.equal(selector,'.label');return {textContent:labels[i]};},
  setAttribute:(key,v)=>{assert.equal(key,'aria-label');card.aria=v;}};
 return {type,value,card};
});
const done={};
const cards=types.map((severity,i)=>({dataset:{cardId:String(i+1),severity,category:'test'}}));
const note={hidden:true};
const doc2={
 querySelectorAll:selector=>{
  if(selector==='.finding-card')return cards;
  if(selector==='.severity-filter')return [];
  if(selector==='.nav-item[data-category]')return [];
  throw Error('unexpected selector '+selector);
 },
 querySelector:selector=>{
  const type=types.find(t=>selector==='.summary-card.'+t+' .value');
  assert(type,'unexpected '+selector);
  return controls[types.indexOf(type)].value;
 },
 getElementById:id=>id==='doc4hSummaryCountNote'?note:null
};
const sandbox={document:doc2,completedFindings:done};
vm.runInNewContext(update+'\nupdateSidebarCounts();',sandbox,{timeout:3000});
assert.equal(note.hidden,false);
for(const x of controls){assert.equal(x.value.textContent,1);assert(x.card.aria.includes('карточек проверок: 1'));}
done['1']=true;
vm.runInNewContext(update+'\nupdateSidebarCounts();',sandbox,{timeout:3000});
assert.equal(controls[0].value.textContent,0);
assert(controls[0].card.aria.includes('карточек проверок: 0'));
assert.equal(controls[1].value.textContent,1);
console.log('PASS DOC4h: 7 scoped labels, clock, risk tooltip, live accessible counters, protected LDAP/AD fields');
