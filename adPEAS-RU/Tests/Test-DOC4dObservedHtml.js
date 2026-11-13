// DOC4d: regression for user-provided real HTML (synthetic data only).
// Requires no network, AD access, screenshot or report publication.
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const js=fs.readFileSync(path.join(root,'src/modules/Reporting/templates/report-scripts.js'),'utf8');
const marker='        // DOC4d: verified field-scoped display translations';
const endMarker='        // Scoring context data for context-aware risk calculation';
const begin=js.indexOf(marker);
const end=js.indexOf(endMarker,begin);
assert(begin>=0 && end>begin,'DOC4d dynamic handler absent');
const handler=js.slice(begin,end);
let domLoaded=null;
let cases=[];
const fakeDocument={
  addEventListener:(name,callback)=>{
    assert.equal(name,'DOMContentLoaded');
    assert(!domLoaded,'multiple DOC4d DOM callbacks');
    domLoaded=callback;
  },
  querySelectorAll:(selector)=>{
    assert.equal(selector,'.attr-row[data-attr-name]');
    return cases;
  },
  createTreeWalker:(root)=>{
    let supplied=false;
    return {nextNode:()=>{
      if(supplied) return null;
      supplied=true;
      return root;
    }};
  }
};
const fakeWindow={};
vm.runInNewContext(handler,{
  document:fakeDocument,
  NodeFilter:{SHOW_TEXT:4},
  window:fakeWindow
},{timeout:2000});
assert.equal(typeof domLoaded,'function');
const checks=[
 ['logonhours','All hours (no restriction)','Любое время (ограничений нет)'],
 ['adSubnet','Not in Sites and Services','Не задана в «Сайты и службы Active Directory»'],
 ['whoCanAddComputers','Any authenticated user, up to the quota',
  'Любой прошедший проверку подлинности пользователь (в пределах квоты)'],
 ['decidedBy','None (signing is set on the DC OU only)',
  'Нет (подпись задана только в OU контроллеров домена)'],
 ['LinkedOUs','Not linked','Не привязана'],
 ['activityStatus','INACTIVE (no logon recorded, password not changed for >90 days)',
  'НЕАКТИВНА (входы не зарегистрированы, пароль не менялся более 90 дней)'],
 ['activityStatus','INACTIVE (no logon recorded, password not changed for >120 days)',
  'НЕАКТИВНА (входы не зарегистрированы, пароль не менялся более 120 дней)'],
 ['decidedBy','Default Domain Controllers Policy (LDAP signing)',
  'Default Domain Controllers Policy (подпись LDAP)'],
 ['decidedBy','Default Domain Policy (anonymous SID/name translation)',
  'Default Domain Policy (анонимное сопоставление SID и имени)'],
 ['decidedBy','Default Domain Controllers Policy (server signing)',
  'Default Domain Controllers Policy (подпись SMB на сервере)'],
 ['dangerousRights','All Extended Rights (grants DS-Replication-Get-Changes and DS-Replication-Get-Changes-All)',
  'Все расширенные права (включая DS-Replication-Get-Changes и DS-Replication-Get-Changes-All)'],
 ['dangerousRights','DS-Replication-Get-Changes-In-Filtered-Set - replicates the directory except secrets but is one right short of DCSync',
  'DS-Replication-Get-Changes-In-Filtered-Set — репликация каталога без секретов; самого этого права для DCSync недостаточно'],
 ['dangerousRights','Owner of the account - may rewrite its DACL',
  'Владелец учётной записи — может изменять её DACL'],
 // Known values remain unchanged if not approved for translation.
 ['decidedBy','Default Domain Policy','Default Domain Policy'],
 ['whoCanAddComputers','S-1-5-11','S-1-5-11'],
 ['adSubnet','192.168.1.0/24','192.168.1.0/24'],
 ['dangerousRights','GenericAll','GenericAll'],
 ['otherField','Not linked','Not linked'],
 ['decidedBy','Default Domain Policy (LDAP signing) EXTRA',
  'Default Domain Policy (LDAP signing) EXTRA']
];
cases=checks.map(([key,input])=>{
  const node={
    nodeValue:'  '+input+'  ',
    parentElement:{closest:()=>null}
  };
  return {
    key,
    node,
    getAttribute:(name)=>name==='data-attr-name'?key:null,
    querySelector:(selector)=>selector==='.attr-value'?node:null
  };
});
domLoaded();
for(let i=0;i<checks.length;i++){
  const [,input,expected]=checks[i],row=cases[i];
  assert.equal(row.node.nodeValue,'  '+expected+'  ','failed field-scoped translation '+i+': '+input);
  assert.equal(row.key,checks[i][0],'machine data key was changed');
}
assert.equal(fakeWindow.adPEASRUDOC4d.inspected,checks.length);
assert.equal(fakeWindow.adPEASRUDOC4d.translated,13);
const ps=fs.readFileSync(path.join(root,'src/modules/Reporting/Export-HTMLReport.ps1'),'utf8');
const headers=[
 ["'Analyzing Credential Exposure' = 'Анализ раскрытия учётных данных'"],
 ["'Analyzing Computer Security' = 'Анализ безопасности компьютеров'"],
 ["'Analyzing Application Infrastructure' = 'Анализ инфраструктуры приложений'"]
];
headers.forEach(([value])=>assert(ps.includes(value),'Missing translated category header '+value));
console.log('PASS DOC4d: 3 section headers + 13 field-scoped display values; 6 unchanged technical inputs, no report/AD side effects');
