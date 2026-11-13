// DOC4b synthetic fixture: executes only the injected display-only browser handler.
// Never loads the user's domain report, LDAP data, or network resources.
'use strict';
const fs=require('fs');
const vm=require('vm');
const path=require('path');
const assert=require('assert');
const root=path.resolve(__dirname,'..');
const src=fs.readFileSync(path.join(root,'src/modules/Reporting/templates/report-scripts.js'),'utf8');
const begin='        // DOC4b: translate rendered attribute values only.';
const end='        // Scoring context data for context-aware risk calculation';
const start=src.indexOf(begin);
const doc4cBoundary=src.indexOf('        // DOC4c: complete human-reviewed RU descriptions',start);
const finish=doc4cBoundary>=0 ? doc4cBoundary : src.indexOf(end,start);
assert(start>=0 && finish>start,'DOC4b runtime insertion missing');
assert.strictEqual(src.indexOf(begin,start+1),-1,'DOC4b handler inserted more than once');
const injected=src.slice(start,finish);
const cases=[
  ['activityStatus','INACTIVE (no login for >90 days)','НЕАКТИВНА (нет входа более 90 дней)'],
  ['accountexpires','Never','Никогда'],
  ['accountLockoutStatus','Not locked out','Не заблокирована'],
  ['grouptype','Global Security Group','Глобальная группа безопасности'],
  ['grouptype','Universal Security Group','Универсальная группа безопасности'],
  ['grouptype','Domain Local Security Group','Локальная группа безопасности домена'],
  ['EffectiveSetting','Yes - in force on the domain controllers: LDAP signing','Да — действует на контроллерах домена: подпись LDAP'],
  ['EffectiveSetting','Yes - in force on the domain controllers: anonymous SID/name translation','Да — действует на контроллерах домена: анонимное сопоставление SID и имени'],
  ['EffectiveSetting','Yes - in force on the domain controllers: server signing','Да — действует на контроллерах домена: подпись SMB на сервере'],
  ['EffectiveSetting','Yes - wins precedence on the Domain Controllers OU','Да — имеет приоритет для OU контроллеров домена'],
  ['ServerSigning','Not configured (not required before Server 2025)','Не настроено (до Windows Server 2025 по умолчанию не требуется)'],
  ['settings','All settings disabled','Все настройки отключены'],
  ['domainControllers','DC.EXAMPLE.LOCAL [PDC Emulator, Schema Master, RID Master]','DC.EXAMPLE.LOCAL [эмулятор PDC, мастер схемы, мастер RID]'],
  ['dangerousRights','GenericAll (Full Control)','GenericAll (полный контроль)'],
  ['dangerousRights','CreateChild (Computer) in the computer container','CreateChild (Computer) — создание объектов в контейнере компьютеров'],
  ['dangerousRights','WriteProperty on member - may add a member to every protected group','WriteProperty для member — позволяет менять состав всех защищённых групп'],
  ['dangerousRights','DS-Replication-Get-Changes-All - inert without DS-Replication-Get-Changes and one ACE short of DCSync','DS-Replication-Get-Changes-All — без DS-Replication-Get-Changes не действует, для DCSync требуется ещё одна ACE'],
  ['userparameters','[userParameters blob: 223 bytes, no recognised TSPropertyArray signature]','[данные userParameters: 223 байт; сигнатура TSPropertyArray не распознана]'],
  ['distinguishedName','CN=Test,DC=EXAMPLE,DC=LOCAL','CN=Test,DC=EXAMPLE,DC=LOCAL'],
  ['objectSid','S-1-5-21-1-2-3-512','S-1-5-21-1-2-3-512'],
  ['samaccounttype','USER_OBJECT','USER_OBJECT'],
  ['GPOName','Default Domain Controllers Policy','Default Domain Controllers Policy'],
  ['dangerousRights','GenericAll','GenericAll']
];
function fakeRow(key,value) {
  const node={nodeValue:value,parentElement:{closest:()=>null}};
  const inner={node};
  return {
    original:value, key, inner,
    machineFindingId:'DANGEROUS_ACL_DCSYNC', machineSeverity:'finding',
    getAttribute(k){assert.strictEqual(k,'data-attr-name');return this.key;},
    querySelector(sel){assert.strictEqual(sel,'.attr-value');return inner;}
  };
}
const rows=cases.map(([key,source])=>fakeRow(key,source));
const doc={
  addEventListener(event,fn){assert.strictEqual(event,'DOMContentLoaded');fn();},
  querySelectorAll(selector){assert.strictEqual(selector,'.attr-row[data-attr-name]');return rows;},
  createTreeWalker(inner){let returned=false;return {nextNode(){if(returned)return null;returned=true;return inner.node;}};}
};
const browser={};
vm.runInNewContext(injected,{
  document:doc,window:browser,NodeFilter:{SHOW_TEXT:4}
},{timeout:1500});
cases.forEach(([key,source,want],index)=>{
  const row=rows[index];
  assert.strictEqual(row.inner.node.nodeValue,want,'value translation for '+key+': '+source);
  assert.strictEqual(row.original,source,'raw data changed');
  assert.strictEqual(row.key,key,'machine attribute key changed');
  assert.strictEqual(row.machineFindingId,'DANGEROUS_ACL_DCSYNC');
  assert.strictEqual(row.machineSeverity,'finding');
});
assert.strictEqual(browser.adPEASRUDOC4b.evaluated,cases.length);
assert.strictEqual(browser.adPEASRUDOC4b.translated,cases.filter(x=>x[1]!==x[2]).length);
console.log('PASS DOC4b: '+cases.length+' synthetic HTML text cases; raw AD data and machine keys unchanged');
