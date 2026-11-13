// DOC4i: offline synthetic GPO/risk-UI regression; no real AD report needed.
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const js=fs.readFileSync(path.join(__dirname,'..','src/modules/Reporting/templates/report-scripts.js'),'utf8');
const begin=js.indexOf('        // DOC4i: context-specific GPO display labels; do not rewrite GPO identity.');
const end=js.indexOf('        // Scoring context data for context-aware risk calculation',begin);
assert(begin>0&&end>begin,'DOC4i handler');
const text=x=>({nodeType:3,nodeValue:x});
const gpo='Default Domain Controllers Policy';
const prefix='Параметры GPO для добавления компьютеров: ';
function card(check,value=prefix+gpo,nested=false){
 const first=text(value),display={childNodes:nested?[first,text('icon')]:[first],firstChild:first};
 return {check,display,value,
 querySelector:q=>{assert.equal(q,'.finding-title');return {textContent:check};},
 querySelectorAll:q=>{assert.equal(q,'.object-detail .object-header > span:first-child');return [display];}};
}
const cards=[
 card('Настройки подписи LDAP в GPO'),
 card('Настройки подписи SMB'),
 card('Права добавления компьютеров в домен'),
 card('Настройки подписи LDAP в GPO','Параметры подписи LDAP в GPO: '+gpo),
 card('Настройки подписи SMB',prefix+gpo,true)
];
let cb=null;
const document={
 addEventListener:(kind,fn)=>{assert.equal(kind,'DOMContentLoaded');assert(!cb);cb=fn;},
 querySelectorAll:q=>{assert.equal(q,'.finding-card');return cards;}
};
const window={};
const context=vm.createContext({document,window,Node:{TEXT_NODE:3}});
vm.runInContext(js.slice(begin,end),context,{timeout:3000});
cb();
assert.equal(cards[0].display.firstChild.nodeValue,'Параметры подписи LDAP в GPO: '+gpo);
assert.equal(cards[1].display.firstChild.nodeValue,'Параметры подписи SMB в GPO: '+gpo);
for(const c of cards.slice(2)) assert.equal(c.display.firstChild.nodeValue,c.value);
assert.equal(window.adPEASRUDOC4i.correctedGpoHeaders,2);
function node(raw){const first=text(raw);return {firstChild:first,childNodes:[first]};}
const labels=['Impact','Correlation','Security','Возможность эксплуатации','Базовая оценка'].map(node);
const reasons=['Tier 0 (Domain Admin)','Appears in multiple findings',
 'hint (informational)','Old password (3y), RC4 encryption',
 'Mitigated','DANGEROUS_ACL_DCSYNC','Protected Users'].map(node);
const values=['67','×1.30','+5'].map(node);
const tooltip={querySelectorAll:q=>{
 if(q==='.score-tooltip-label')return labels;
 if(q==='.score-tooltip-label .reason')return reasons;
 if(q==='.score-tooltip-value')return values;
 throw Error('unrecognized selector '+q);
}};
const baseline=JSON.stringify(values.map(x=>x.firstChild.nodeValue));
context.ruDOC4iLocalizeScoreTooltip(tooltip);
assert.deepEqual(labels.map(x=>x.firstChild.nodeValue),
 ['Влияние','Корреляция','Защитные меры','Возможность эксплуатации','Базовая оценка']);
assert.deepEqual(reasons.map(x=>x.firstChild.nodeValue),
 ['Tier 0 (администратор домена)','Обнаружено в нескольких результатах',
 'Предупреждение (информационный результат)','Пароль не менялся 3 г., Шифрование RC4',
 'Риск снижен','DANGEROUS_ACL_DCSYNC','Protected Users']);
assert.equal(window.adPEASRUDOC4iScoreLast.translatedLabels,3);
assert.equal(window.adPEASRUDOC4iScoreLast.translatedReasons,5);
assert.equal(JSON.stringify(values.map(x=>x.firstChild.nodeValue)),baseline);
context.ruDOC4iLocalizeScoreTooltip(tooltip);
assert.equal(window.adPEASRUDOC4iScoreLast.translatedLabels,0,'must be idempotent');
assert.equal(window.adPEASRUDOC4iScoreLast.translatedReasons,0,'must be idempotent');
const match='            tooltip.innerHTML = formatScoreBreakdownHtml(breakdown);';
assert(js.includes(match+'\n            ruDOC4iLocalizeScoreTooltip(tooltip);') ||
       js.includes(match+'\r\n            ruDOC4iLocalizeScoreTooltip(tooltip);'),
       'translator must run immediately after HTML scoring tooltip render');
assert(js.includes("breakdown.matchedPattern = 'hint (informational)'"),'raw machine breakdown unchanged');
assert(js.includes("breakdown.correlationReason = 'Appears in multiple findings'"),'raw correlation unchanged');
console.log('PASS DOC4i: 2 GPO context headers, 3 unchanged cases, 3 score labels and 5 reasons, idempotence and unchanged numeric data');
