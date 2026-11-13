// DOC4f: synthetic browser-model regression; no AD access or private HTML.
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(root,'src/modules/Reporting/templates/report-scripts.js'),'utf8');
const startMarker='        // DOC4f: original HTML evidence identifies exactly three field-scoped';
const endMarker='        // Scoring context data for context-aware risk calculation';
const from=source.indexOf(startMarker);
const to=source.indexOf(endMarker,from);
assert(from>=0&&to>from,'DOC4f emitted JS block missing');
let onLoad=null,rows=[];
const document={
  addEventListener:(name,fn)=>{
    assert.equal(name,'DOMContentLoaded');
    assert(!onLoad,'DOC4f callback registered twice');
    onLoad=fn;
  },
  querySelectorAll:(q)=>{
    assert.equal(q,'.attr-row[data-attr-name]');
    return rows;
  },
  createTreeWalker:(root)=>{
    let once=false;
    return {nextNode:()=>once?null:(once=true,root)};
  }
};
const window={};
vm.runInNewContext(source.slice(from,to),{
  document,window,NodeFilter:{SHOW_TEXT:4}
},{timeout:3000});
assert.equal(typeof onLoad,'function');
const fixtures=[
  ['privilegedGroups','Администраторы домена (direct)',
      'Администраторы домена (прямое членство)'],
  ['privilegedGroups','Администраторы схемы (direct)',
      'Администраторы схемы (прямое членство)'],
  ['privilegedGroups','Администраторы Hyper-V (direct)',
      'Администраторы Hyper-V (прямое членство)'],
  ['privilegedGroups','SyntheticGroup (indirect)','SyntheticGroup (indirect)'],
  ['privilegedGroups','SyntheticGroup (direct) EXTRATEXT',
      'SyntheticGroup (direct) EXTRATEXT'],
  ['privilegedGroups','S-1-5-21-111-222-333-512','S-1-5-21-111-222-333-512'],
  ['affectedOUs','DC=example,DC=invalid (domain root, inherited by 4 OU и 7 контейнеров)',
      'DC=example,DC=invalid (корень домена; наследование распространяется на 4 OU и 7 контейнеров)'],
  ['affectedOUs','DC=example,DC=invalid (domain root, inherited by 0 OU и 1 контейнеров)',
      'DC=example,DC=invalid (корень домена; наследование распространяется на 0 OU и 1 контейнеров)'],
  ['affectedOUs','OU=Folder,DC=example,DC=invalid (set here)',
      'OU=Folder,DC=example,DC=invalid (set here)'],
  ['affectedOUs','DC=example,DC=invalid (domain root, inherited by many OU и 7 контейнеров)',
      'DC=example,DC=invalid (domain root, inherited by many OU и 7 контейнеров)'],
  ['affectedOUs','not-DN (domain root, inherited by 4 OU и 7 контейнеров)',
      'not-DN (domain root, inherited by 4 OU и 7 контейнеров)'],
  ['tier0Groups','Администраторы, Built-in Administrator (RID 500), Администраторы домена',
      'Администраторы, Встроенная учётная запись администратора (RID 500), Администраторы домена'],
  ['tier0Groups','Built-in Administrator (RID 500)',
      'Встроенная учётная запись администратора (RID 500)'],
  ['tier0Groups','Builtin\\\\Administrators (RID 544)',
      'Builtin\\\\Administrators (RID 544)'],
  ['tier0Groups','Administrator (RID 500)','Administrator (RID 500)'],
  ['otherField','Builtin Administrator (RID 500)',
      'Builtin Administrator (RID 500)'],
  ['otherField','Built-in Administrator (RID 500)',
      'Built-in Administrator (RID 500)'],
  ['AffectedGroup','SyntheticGroup (direct)','SyntheticGroup (direct)'],
  ['affectedOUs','CN=Users,DC=example,DC=invalid',
      'CN=Users,DC=example,DC=invalid']
];
rows=fixtures.map(([key,initial])=>{
  const value={nodeValue:'  '+initial+'\n',
    parentElement:{closest:()=>null}};
  return {
    key,value,
    getAttribute:(n)=>n==='data-attr-name'?key:null,
    querySelector:(n)=>n==='.attr-value'?value:null
  };
});
onLoad();
let changes=0;
for(let i=0;i<fixtures.length;i++){
  const [key,initial,expected]=fixtures[i];
  assert.equal(rows[i].key,key);
  assert.equal(rows[i].value.nodeValue,'  '+expected+'\n','unexpected DOC4f translation '+i);
  if(initial!==expected)changes++;
}
assert.equal(changes,7,'expected seven localized fixtures');
assert.equal(window.adPEASRUDOC4f.translated,changes);
assert.equal(window.adPEASRUDOC4f.byField.privilegedGroups,3);
assert.equal(window.adPEASRUDOC4f.byField.affectedOUs,2);
assert.equal(window.adPEASRUDOC4f.byField.tier0Groups,2);
assert.equal(window.adPEASRUDOC4f.inspected,
 fixtures.filter(([key])=>['privilegedGroups','affectedOUs','tier0Groups'].includes(key)).length);
console.log('PASS DOC4f: 3 attribute-specific translation rules / 7 positive fixtures; no ID, RID, DN or machine value changed');
