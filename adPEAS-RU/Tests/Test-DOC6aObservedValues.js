// DOC6a synthetic regression based on 2026-11-19 observed report value patterns.
// Does not contain real domain details or upload users' HTML.
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync(path.join(__dirname,'..','src/modules/Reporting/templates/report-scripts.js'),'utf8');
const begin=src.indexOf('        // DOC6a BEGIN: verified, field-scoped presentation translations only.');
const end=src.indexOf('        // DOC6a END: verified report display translations.',begin);
assert(begin>0&&end>begin,'DOC6a source block present once');
assert.equal(src.indexOf('        // DOC6a BEGIN:',begin+5),-1,'injected only once');
const T=s=>({nodeType:3,nodeValue:s});
const E=(name,...kids)=>({nodeType:1,tagName:name,childNodes:kids});
function row(key,...values){
 const content=E('DIV',...values),attrs={'data-attr-name':key};
 return {key,content,attrs,getAttribute:k=>attrs[k],querySelector:q=>{assert.equal(q,'.attr-value');return content}};
}
const gpo="Example Policy";
const dn='OU=Domain Controllers,DC=example,DC=local';
const principal='NT AUTHORITY\\Authenticated Users';
const rows=[
 row('activityStatus',E('SPAN',T('INACTIVE (no login for >90 days)'))),
 row('activityStatus',E('SPAN',T('INACTIVE (no logon recorded, password not changed for >90 days)'))),
 row('adSubnet',T('Not in Sites and Services')),
 row('EffectiveSetting',T('Yes - in force on the domain controllers: LDAP signing')),
 row('EffectiveSetting',T('Yes - wins precedence on the Domain Controllers OU')),
 row('ServerSigning',E('SPAN',T('Not configured (not required before Server 2025)'))),
 row('ClientSigning',T('Not configured')),
 row('decidedBy',T(gpo+' (LDAP signing)')),
 row('decidedBy',T('None (signing is set on the DC OU only)')),
 row('privilegeGrantedBy',T("GPO '"+gpo+"' grants SeMachineAccountPrivilege to "+principal)),
 row('whoCanAddComputers',T('Any authenticated user, up to the quota')),
 row('dangerousRights',E('SPAN',T('Owner of the group - may rewrite its DACL')),E('BR'),E('SPAN',T('DS-Replication-Get-Changes-All - inert without DS-Replication-Get-Changes and one ACE short of DCSync'))),
 row('affectedOUs',E('SPAN',T(dn+' (set here)'))),
 row('affectedOUs',T('DC=example,DC=local (domain root, inherited by 4 OU и 7 контейнеров)')),
 row('gpcmachineextensionnames',T('Security (Security Settings)')),
 row('pwdLastSet',T('INACTIVE (no login for >90 days)')),
 row('dangerousRights',E('CODE',T('Owner of the group - may rewrite its DACL'))),
 row('dangerousRights',T('GenericAll'))
];
let callback=null;
const window={};
const document={addEventListener:(name,cb)=>{assert.equal(name,'DOMContentLoaded');callback=cb;},querySelectorAll:q=>{
 assert.equal(q,'.attr-row[data-attr-name]');return rows;}};
vm.runInNewContext(src.slice(begin,end),{document,window,Node:{TEXT_NODE:3,ELEMENT_NODE:1}},{timeout:4000});
assert.equal(typeof callback,'function');
const before=rows.map(r=>({key:r.key,attrs:JSON.stringify(r.attrs),tags:JSON.stringify((function tags(n){return [n.tagName,...(n.childNodes||[]).flatMap(tags)]})(r.content))}));
callback();
function values(row){
 const out=[];function visit(n){if(n.nodeType===3)out.push(n.nodeValue);else (n.childNodes||[]).forEach(visit);}visit(row.content);return out.join(' | ');
}
assert.equal(values(rows[0]),'НЕАКТИВНА (нет входов более 90 дней)');
assert.equal(values(rows[1]),'НЕАКТИВНА (входы не зафиксированы, пароль не менялся более 90 дней)');
assert.equal(values(rows[2]),'Отсутствует в «Сайты и службы Active Directory»');
assert.equal(values(rows[3]),'Да — действует на контроллерах домена: подпись LDAP');
assert.equal(values(rows[4]),'Да — имеет приоритет в OU контроллеров домена');
assert.equal(values(rows[5]),'Не настроена (не требовалась до Windows Server 2025)');
assert.equal(values(rows[6]),'Не настроена');
assert.equal(values(rows[7]),gpo+' (подпись LDAP)');
assert.equal(values(rows[8]),'Нет (подпись настроена только в OU контроллеров домена)');
assert.equal(values(rows[9]),"GPO '"+gpo+"' предоставляет право SeMachineAccountPrivilege субъекту "+principal);
assert.equal(values(rows[10]),'Любой аутентифицированный пользователь — в пределах квоты');
assert(values(rows[11]).includes('Владелец группы — может изменить её DACL'));
assert(values(rows[11]).includes('DS-Replication-Get-Changes-All'));
assert.equal(values(rows[12]),dn+' (назначено непосредственно)');
assert.equal(values(rows[13]),'DC=example,DC=local (корень домена; наследуется 4 OU и 7 контейнерами)');
assert.equal(values(rows[14]),'Security (Security Settings)');
assert.equal(values(rows[15]),'INACTIVE (no login for >90 days)');
assert.equal(values(rows[16]),'Owner of the group - may rewrite its DACL');
assert.equal(values(rows[17]),'GenericAll');
assert(window.adPEASRUDOC6a.translatedTextNodes>=14);
rows.forEach((r,i)=>{
 assert.equal(JSON.stringify(r.attrs),before[i].attrs,'raw attribute changed');
 assert.equal(JSON.stringify((function tags(n){return [n.tagName,...(n.childNodes||[]).flatMap(tags)]})(r.content)),before[i].tags,'HTML changed');
});
callback();
assert.equal(window.adPEASRUDOC6a.translatedTextNodes,0,'must be idempotent');
console.log('PASS DOC6a: 18 scoped DOM fixtures, synthetic AD identities preserved, no mutation of markup, zero second-pass changes');
