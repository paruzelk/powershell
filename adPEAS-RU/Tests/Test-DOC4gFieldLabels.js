// DOC4g: verify all 54 synthetic label translations and sensitive data invariants.
// Runs under Node with a deliberately limited DOM model; never contacts AD.
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const file=path.join(__dirname,'..','src/modules/Reporting/templates/report-scripts.js');
const whole=fs.readFileSync(file,'utf8');
const mark='        // DOC4g: display labels for synthetic report fields only.';
const nextStage='        // DOC4h: observed synthetic labels and DC clock note only; no AD values changed.';
const end=whole.includes(nextStage)?nextStage:'        // Scoring context data for context-aware risk calculation';
const from=whole.indexOf(mark),to=whole.indexOf(end,from);
assert(from>=0&&to>from,'DOC4g missing JavaScript handler');
const body=whole.slice(from,to);
let load,rows=[];
const textNode=x=>({nodeType:3,nodeValue:x});
const makeLabel=(value,nested=false)=>{
 const node=textNode(value);
 return {textContent:value,firstChild:node,childNodes:nested?[node,textNode(' icon')]:[node]};
};
const makeValue=x=>{
 const node=textNode(x);
 return {textContent:x,firstChild:node,childNodes:[node]};
};
const row=(key,label=key,value='S-1-5-21-111-222-333-500',nested=false)=>{
 const name=makeLabel(label,nested),val=makeValue(value);
 return {key,name,val,
   getAttribute:(k)=>k==='data-attr-name'?key:null,
   querySelector:(q)=>q==='.attr-name'?name:q==='.attr-value'?val:null};
};
const document={
 addEventListener:(e,fn)=>{assert.equal(e,'DOMContentLoaded');assert(!load);load=fn;},
 querySelectorAll:(selector)=>{
  assert.equal(selector,'.attr-row[data-attr-name]');
  return rows;
 }
};
const window={};
vm.runInNewContext(body,{document,window,Node:{TEXT_NODE:3}},{timeout:2500});
assert.equal(typeof load,'function');
const translated={
 PrivilegeCategory:'Категория учётной записи',
 privilegedGroups:'Привилегированные группы',
 tier0Groups:'Группы с привилегиями Tier 0',
 UserRight:'Право пользователя',
 AppliesTo:'Область применения',
 SourceFile:'Исходный файл',
 IsDomainWide:'Действует на весь домен',
 UserVersion:'Версия настроек пользователей',
 ComputerVersion:'Версия настроек компьютеров',
 affectedComputerCount:'Количество затронутых компьютеров',
 PrivilegedGroup:'Привилегированная группа',
 EffectiveSetting:'Итоговое применённое значение',
 ServerSigning:'Требование подписи SMB на сервере',
 ClientSigning:'Требование подписи SMB на клиенте',
 decidedBy:'Определяющая групповая политика',
 LDAPSigning:'Требование подписи LDAP',
 ChannelBinding:'Привязка канала LDAP',
 anonymousLDAPAccess:'Анонимный доступ LDAP',
 anonymousSamEnumeration:'Анонимное перечисление учётных записей SAM',
 anonymousSidNameTranslation:'Анонимное преобразование SID в имя',
 Accounts:'Учётные записи',
 targetContainer:'Целевой контейнер',
 whoCanAddComputers:'Кто может добавлять компьютеры в домен',
 privilegeGrantedBy:'Назначение права через групповую политику',
 CoversDCs:'Охватывает контроллеры домена',
 _PrecedenceRank:'Ранг приоритета политики',
 _PrecedenceScope:'Область приоритета политики',
 _PrecedenceOrder:'Порядок применения политики',
 _HasAuthenticatedUsers:'Включены Authenticated Users',
 _HasEveryone:'Включена группа Everyone',
 accountsRead:'Проверено учётных записей',
 protectedByAdminSDHolder:'Записи под защитой AdminSDHolder',
 affectedAccounts:'Затронутые учётные записи',
 prewin2000DefaultMember:'Участник группы совместимости с Windows 2000 по умолчанию',
 MemberName:'Имя участника',
 MemberSID:'SID участника',
 siteName:'Имя сайта AD',
 siteSubnets:'Подсети сайта AD',
 siteDomainControllers:'Контроллеры домена сайта',
 domainControllers:'Контроллеры домена',
 domainNameDNS:'DNS-имя домена',
 domainNameNetBIOS:'NetBIOS-имя домена',
 domainSID:'SID домена',
 domainFunctionalLevel:'Функциональный уровень домена',
 forestFunctionalLevel:'Функциональный уровень леса',
 forestName:'Имя леса',
 tombstoneLifetime:'Срок хранения удалённых объектов',
 recycleBin:'Корзина Active Directory',
 sysvolReplication:'Механизм репликации SYSVOL',
 accountStatus:'Состояние учётной записи',
 adminSDHolderExclusion:'Исключение из защиты AdminSDHolder',
 principalNameUniqueness:'Проверка уникальности имени субъекта',
 anonymousNSPIAccess:'Анонимный доступ NSPI',
 Policies:'Связанные групповые политики'
};
assert.equal(Object.keys(translated).length,54,'unexpected dictionary count');
const protect=[
 'distinguishedName','objectSid','sAMAccountName','userAccountControl',
 'GPOGUID','GPOPath','dscorepropagationdata','gpcmachineextensionnames',
 'ms-DS-MachineAccountQuota','cn','memberOf'
];
rows=[
 ...Object.keys(translated).map(k=>row(k,k,k==='PrivilegeCategory'?'Privileged':'S-1-5-21-111-222-333-500')),
 ...protect.map(k=>row(k)),
 row('tier0Groups','Уже переведено'),
 row('SourceFile','SourceFile','S-1-5-11',true),
 row('PrivilegeCategory','PrivilegeCategory','Privileged (tier0)'),
 row('PrivilegeCategory','PrivilegeCategory','Привилегированная'),
 row('objectSid','objectSid','Privileged')
];
load();
for(let i=0;i<Object.keys(translated).length;i++){
 const key=rows[i].key;
 assert.equal(rows[i].name.firstChild.nodeValue,translated[key],'wrong field label: '+key);
 const original=key==='PrivilegeCategory'?'Privileged':'S-1-5-21-111-222-333-500';
 const newValue=key==='PrivilegeCategory'?'Привилегированная':original;
 assert.equal(rows[i].val.firstChild.nodeValue,newValue,'dangerous data change: '+key);
 assert.equal(rows[i].key,key,'data-attr-name changed');
}
for(let i=Object.keys(translated).length;i<Object.keys(translated).length+protect.length;i++){
 assert.equal(rows[i].name.firstChild.nodeValue,rows[i].key);
 assert.equal(rows[i].val.firstChild.nodeValue,'S-1-5-21-111-222-333-500');
}
assert.equal(rows[rows.length-5].name.firstChild.nodeValue,'Уже переведено');
assert.equal(rows[rows.length-4].name.firstChild.nodeValue,'SourceFile');
assert.equal(rows[rows.length-3].val.firstChild.nodeValue,'Privileged (tier0)');
assert.equal(rows[rows.length-2].val.firstChild.nodeValue,'Привилегированная');
assert.equal(rows[rows.length-1].val.firstChild.nodeValue,'Privileged');
assert.equal(window.adPEASRUDOC4g.dictionaryEntries,54);
assert.equal(window.adPEASRUDOC4g.translatedLabels,56);
assert.equal(window.adPEASRUDOC4g.translatedValues,1);
assert.equal(window.adPEASRUDOC4g.inspected,58);
console.log('PASS DOC4g: 54 exact RU field labels, 1 exact display enum, 11 protected AD keys, 5 negative cases');
