// DOC4e: test emitted JavaScript without domain connection or private reports.
// The cases are synthetic equivalents of patterns verified in two live HTMLs.
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const root=path.resolve(__dirname,'..');
const js=fs.readFileSync(path.join(root,'src/modules/Reporting/templates/report-scripts.js'),'utf8');
const marker='        // DOC4e: only field-scoped human-readable suffixes and grammar.';
const ending='        // Scoring context data for context-aware risk calculation';
const from=js.indexOf(marker);
const next=js.indexOf('        // DOC4f: original HTML evidence identifies exactly three field-scoped',from);
const to=next>=0 ? next : js.indexOf(ending,from);
assert(from>=0 && to>from,'DOC4e injection boundaries missing');
const body=js.slice(from,to);
let callback;
let rows=[];
const document={
  addEventListener:(n,fn)=>{
    assert.equal(n,'DOMContentLoaded');
    assert(!callback,'duplicate DOC4e handler');
    callback=fn;
  },
  querySelectorAll:(sel)=>{
    assert.equal(sel,'.attr-row[data-attr-name]');
    return rows;
  },
  createTreeWalker:(node)=>{
    let returned=false;
    return { nextNode:()=>returned?null:(returned=true,node) };
  }
};
const window={};
vm.runInNewContext(body,{document,window,NodeFilter:{SHOW_TEXT:4}},{timeout:2500});
assert.equal(typeof callback,'function');
const source=[
  ['operatingSystems','1 server(s)','1 сервер'],
  ['operatingSystems','2 server(s)','2 сервера'],
  ['operatingSystems','5 server(s)','5 серверов'],
  ['operatingSystems','11 server(s)','11 серверов'],
  ['operatingSystems','21 server(s)','21 сервер'],
  ['operatingSystems','2 server(s), 4 client(s), 2 other','2 сервера, 4 клиентские ОС, 2 другие ОС'],
  ['operatingSystems','1 client(s), 5 other','1 клиентская ОС, 5 других ОС'],
  ['privilegeGrantedBy',"GPO 'Synthetic DC Policy' grants SeMachineAccountPrivilege to NT AUTHORITY\\Authenticated Users",
   'Групповая политика «Synthetic DC Policy» предоставляет право SeMachineAccountPrivilege субъекту NT AUTHORITY\\Authenticated Users'],
  ['affectedGroups','DnsAdmins (privileged group)','DnsAdmins (привилегированная группа)'],
  ['affectedOUs','OU=Synthetic,DC=example,DC=invalid (set here)',
   'OU=Synthetic,DC=example,DC=invalid (назначено непосредственно здесь)'],
  ['affectedOUs','CN=Builtin,DC=example,DC=invalid (set here)',
   'CN=Builtin,DC=example,DC=invalid (назначено непосредственно здесь)'],
  ['LinkedOUs','OU=Synthetic,DC=example,DC=invalid (link enforced)',
   'OU=Synthetic,DC=example,DC=invalid (принудительная связь GPO)'],
  ['LinkedOUs','OU=Synthetic,DC=example,DC=invalid (link disabled)',
   'OU=Synthetic,DC=example,DC=invalid (link disabled)'],
  ['affectedOUs','not-a-dn (set here)','not-a-dn (set here)'],
  ['affectedGroups','DnsAdmins (privileged groups)','DnsAdmins (privileged groups)'],
  ['operatingSystems','Windows Server 2022 Standard','Windows Server 2022 Standard'],
  ['operatingSystems','2 server(s), unrecognized text','2 server(s), unrecognized text'],
  ['privilegeGrantedBy',"GPO 'Synthetic DC Policy' grants GenericAll to Admins",
   "GPO 'Synthetic DC Policy' grants GenericAll to Admins"],
  ['privilegeGrantedBy','S-1-5-11','S-1-5-11'],
  ['LinkedOUs','OU=synthetic,DC=example,DC=invalid','OU=synthetic,DC=example,DC=invalid'],
  ['otherField','DnsAdmins (privileged group)','DnsAdmins (privileged group)'],
  ['dangerousRights','Reset Password (Extended Right)','Reset Password (Extended Right)']
];
rows=source.map(([key,old])=>{
  const n={nodeValue:'\t'+old+'  ',parentElement:{closest:()=>null}};
  return {key,node:n,getAttribute:(attr)=>attr==='data-attr-name'?key:null,
    querySelector:(sel)=>sel==='.attr-value'?n:null};
});
callback();
let changed=0;
for(let i=0;i<source.length;i++) {
  const [key,old,want]=source[i];
  if(old!==want) changed++;
  assert.equal(rows[i].key,key,'attribute field changed');
  assert.equal(rows[i].node.nodeValue,'\t'+want+'  ','wrong DOC4e translation '+i);
}
assert.equal(changed,12);
assert.equal(window.adPEASRUDOC4e.translated,12);
assert.equal(window.adPEASRUDOC4e.inspected,source.filter(([k])=>k!=='otherField'&&k!=='dangerousRights').length);
assert.equal(window.adPEASRUDOC4e.byField.operatingSystems,7);
assert.equal(window.adPEASRUDOC4e.byField.privilegeGrantedBy,1);
assert.equal(window.adPEASRUDOC4e.byField.affectedGroups,1);
assert.equal(window.adPEASRUDOC4e.byField.affectedOUs,2);
assert.equal(window.adPEASRUDOC4e.byField.LinkedOUs,1);
console.log('PASS DOC4e: 12 field-scoped Russian phrases, grammar 1/2/5/11/21, GPO and DN unchanged; no AD contacted');
