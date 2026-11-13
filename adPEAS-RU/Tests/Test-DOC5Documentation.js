// DOC5 documentation regression: six RU pages, valid Markdown fences,
// representative source-aligned topics and protected command identifiers.
'use strict';
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const base=path.join(__dirname,'..','docs');
const specs={
 '00-Home.md':{
   topics:['Полнота справочника DOC5','README_RU.md','Active Directory','Установка'],
   commands:[],minBlocks:0},
 '01-Installation.md':{
   topics:['Дополнительная диагностика установки (DOC5)','GitHub Releases','RSA-SHA256','PowerShell 5.1'],
   commands:['Build-Release.ps1','Get-Command','Import-Module','License'],minBlocks:17},
 '02-Quick-Start.md':{
   topics:['Дополнительные практические примеры оригинала (DOC5)','OutputAppend','VerboseLogging','BuildCompletionCache','Compare-adPEASReport'],
   commands:['Invoke-adPEAS','Convert-adPEASReport','Get-adPEASSession'],minBlocks:23},
 '03-Authentication-Methods.md':{
   topics:['Расширенные сценарии аутентификации (DOC5)','PA-ETYPE-INFO2','LOGON32_LOGON_NEW_CREDENTIALS','Schannel','UnPAC-the-Hash'],
   commands:['ForceNTLM','NTHash','AES128Key','AES256Key','Kirbi','Ccache','ForcePassTheCert'],minBlocks:13},
 '05-BloodHound-Collector.md':{
   topics:['Дополнения о методах и рёбрах графа (DOC5)','GetChangesAll','SharpHound','ObjectIdentifier'],
   commands:['Invoke-adPEASCollector','DCOnly','ObjectProps','CertServices','PrettyPrint'],minBlocks:6},
 '12-FAQ.md':{
   topics:['Дополнительные вопросы исходного FAQ (DOC5)','ESC6','ESC7','SOCKS','Schannel'],
   commands:['NTHash','ForcePassTheCert','ExcludeModule','TimeoutSeconds'],minBlocks:14}
};
const files=Object.keys(specs);
let inspectedBlocks=0,inspectedTopics=0,inspectedIdentifiers=0;
const tick=String.fromCharCode(96);
for(const filename of files){
 const en=fs.readFileSync(path.join(base,filename),'utf8');
 const ru=fs.readFileSync(path.join(base,'ru-RU',filename),'utf8');
 assert(en.startsWith('# '),'missing pinned EN page '+filename);
 assert(ru.startsWith('# '),'missing RU page '+filename);
 assert(ru.includes('(DOC5)')||ru.includes('справочника DOC5'),'missing DOC5 stage '+filename);
 for(const term of specs[filename].topics){
  assert(ru.includes(term),'missing translated detail '+filename+': '+term);
  inspectedTopics++;
 }
 for(const id of specs[filename].commands){
  assert(en.includes(id)||id==='RSA-SHA256','identifier absent in upstream '+filename+': '+id);
  assert(ru.includes(id),'missing original command/parameter '+filename+': '+id);
  inspectedIdentifiers++;
 }
 const fences=ru.split(/\r?\n/).map(s=>s.trim()).filter(s=>s.startsWith('~~~')||s.startsWith(tick.repeat(3)));
 assert.equal(fences.length%2,0,'unclosed markdown fence: '+filename);
 assert(fences.length/2>=specs[filename].minBlocks,'missing restored examples: '+filename);
 inspectedBlocks+=fences.length/2;
 // No accidental raw code markers masquerading as prose placeholders.
 assert(!ru.includes('EN original (перевод пока не завершён)'),'untranslated placeholder in '+filename);
 const links=[...ru.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)];
 for(const match of links){
  const href=match[1].split('#')[0];
  if(!href || /^[a-z][a-z0-9+.-]*:/i.test(href)) continue;
  const local=path.resolve(base,'ru-RU',href);
  assert(fs.existsSync(local),'broken local link in '+filename+': '+href);
 }
}
const readme=fs.readFileSync(path.join(__dirname,'..','README_RU.md'),'utf8');
assert(readme.startsWith('# adPEAS-RU 2.9.0\n\n## Быстрый старт и полный синтаксис параметров'),
 'README full syntax must stay at the beginning');
console.log('PASS DOC5: '+files.length+' RU docs, '+inspectedTopics+' topic markers, '+inspectedIdentifiers+
 ' source identifiers, '+inspectedBlocks+' fenced examples, local links and README front syntax');
