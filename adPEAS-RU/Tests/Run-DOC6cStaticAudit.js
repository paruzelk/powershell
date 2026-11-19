// DOC6c source-language inventory: heuristic triage, not a 100% translation certificate.
// Operates ONLY on project source, never on private AD audit reports.
'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),src=path.join(root,'src');
const outJson=path.join(root,'Localization','DOC6c-StaticSourceAudit.json');
const outMd=path.join(root,'docs','ru-RU','14-Static-Source-Language-Audit.md');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'Localization','DOC6c-ReportingPhrases.ru-RU.json'),'utf8'));
const files=[];
function visit(dir){
 for(const name of fs.readdirSync(dir).sort()){
  const f=path.join(dir,name),st=fs.statSync(f);
  if(st.isDirectory())visit(f);
  else if(/\.(?:ps1|psm1|js|html)$/i.test(name))files.push(f);
 }
}
assert(fs.existsSync(src),'Run Import-adPEAS-RU.ps1 before this audit');
visit(src);
assert(files.length>=160,'Unexpectedly few source files: '+files.length);
const items=[],stats={sourceFiles:files.length,powershell:0,javascript:0,html:0,sourceLines:0};
function candidate(v){
 const t=v.trim();
 if(t.length<10||t.length>300||/[А-ЯЁа-яё]/.test(t))return false;
 const reduced=t.replace(/\$\([^)]+\)|\$\w+|\{\{[^}]+\}\}|&[a-z]+;|<[^>]+>/g,' ');
 const words=reduced.match(/[A-Za-z]{3,}/g)||[];
 return words.length>=2&&/[a-z]/.test(reduced);
}
function push(file,line,type,value){
 const t=value.replace(/\s+/g,' ').trim();
 if(!candidate(t))return;
 items.push({path:path.relative(root,file).replaceAll(path.sep,'/'),line,type,text:t.slice(0,240)});
}
const diag=/\b(?:Write-(?:Warning|Error|Log|Host|Verbose|Information)|Show-(?:Output|Line|KeyValue|SubHeader)|throw)\b/i;
const scriptUi=/\b(?:textContent|innerText|innerHTML|setAttribute|aria-label|placeholder|tooltip|alert\s*\(|confirm\s*\(|\.title\s*=)/i;
for(const file of files){
 const ext=path.extname(file).toLowerCase();
 if(ext==='.js')stats.javascript++;else if(ext==='.html')stats.html++;else stats.powershell++;
 const lines=fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'').split(/\r?\n/);
 stats.sourceLines+=lines.length;
 for(let i=0;i<lines.length;i++){
  const row=lines[i],t=row.trim();
  if(ext==='.ps1'||ext==='.psm1'){
   if(t.startsWith('#')||!diag.test(row))continue;
   for(const m of row.matchAll(/"([^"]{10,300})"/g))push(file,i+1,'ps-diagnostic',m[1]);
  }else if(ext==='.html'){
   if(/<style|<script|data:image|base64,/i.test(row)||row.length>800)continue;
   for(const m of row.matchAll(/>([^<>]{8,240})</g))push(file,i+1,'html-visible',m[1]);
   for(const m of row.matchAll(/(?:aria-label|placeholder|title)="([^"]{8,180})"/g))push(file,i+1,'html-attribute',m[1]);
  }else if(scriptUi.test(row)&&!t.startsWith('//')&&row.length<1600){
   for(const m of row.matchAll(/(['"])([^'"\r\n]{10,220})\1/g))push(file,i+1,'js-ui-candidate',m[2]);
  }
 }
}
items.sort((a,b)=>a.path.localeCompare(b.path,'en')||a.line-b.line||a.text.localeCompare(b.text,'en'));
const byType={};
for(const v of items)byType[v.type]=(byType[v.type]||0)+1;
const high=items.filter(v=>v.type==='html-visible'||v.type==='html-attribute'||v.type==='ps-diagnostic');
const js=items.filter(v=>v.type==='js-ui-candidate');
const read=p=>fs.readFileSync(path.join(src,p),'utf8');
const diff=read('modules/Reporting/templates/diff-template.html');
const compare=read('modules/Reporting/Compare-adPEASReport.ps1');
const convert=read('modules/Reporting/Convert-adPEASReport.ps1');
const exportHtml=read('modules/Reporting/Export-HTMLReport.ps1');
for(const x of ['Comparison Report','>Compared<','>Generated<','aria-label="Toggle theme"'])
 assert(!diff.includes(x),'DOC6c: untranslated diff HTML '+x);
for(const x of ['"Comparison Summary"','"New Findings (','"Remediated Findings (','"Changed Findings (','"text changed"','"adPEAS Report Comparison"'])
 assert(!compare.includes(x),'DOC6c: untranslated diff PS '+x);
for(const x of ['Starting offline report generation','Invalid JSON file - missing CacheVersion field'])
 assert(!convert.includes(x),'DOC6c: untranslated converter '+x);
for(const x of ['No findings collected. HTML report will be empty.','Failed to load HTML template. Ensure template'])
 assert(!exportHtml.includes(x),'DOC6c: untranslated exporter '+x);
const totalPhrases=manifest.files.reduce((n,f)=>n+f.replacements.length,0);
assert.equal(totalPhrases,54);
const result={
 schema:'adPEAS-RU.DOC6c.StaticSourceInventory.1',
 note:'Heuristic candidates, NOT a list of verified untranslated messages; source code only',
 summary:{...stats,totalCandidates:items.length,byType,strongContextCandidates:high.length,jsContextCandidates:js.length,translatedPhrases:totalPhrases},
 candidates:items,
 omitted:0
};
fs.writeFileSync(outJson,JSON.stringify(result,null,2)+'\n','utf8');
const q=String.fromCharCode(96);
const safe=x=>x.replaceAll('|','\\|').replaceAll('<','&lt;').replaceAll('>','&gt;').slice(0,190);
const subset=high.slice(0,65).concat(js.slice(0,30));
const md=[
'# DOC6c — статический аудит языка исходников',
'',
'Документ автоматически формируется в GitHub Actions после локализации закреплённых исходников adPEAS. Приватные доменные HTML-отчёты не используются.',
'',
'## Охват',
'',
'- Всего файлов исходников: **'+files.length+'** (PowerShell '+stats.powershell+', JavaScript '+stats.javascript+', HTML '+stats.html+').',
'- Строк исходников: **'+stats.sourceLines+'**.',
'- Подтверждённые переводы DOC6c: **54** в 4 файлах подсистемы отчётов.',
'- Эвристические кандидаты на проверку: **'+items.length+'** (вызовы PowerShell/HTML: '+high.length+'; JS-контексты: '+js.length+').',
'',
'**Внимание:** это не число фактически непереведённых пользовательских строк. Среди кандидатов могут быть английские названия продуктов, технические идентификаторы, программные сообщения, значения протоколов, составные строки. Требуется ручная проверка контекста.',
'',
'## Предварительная выборка для следующего этапа',
'',
'| Файл | Строка | Контекст | Выдержка |',
'|---|---:|---|---|',
...subset.map(x=>'| '+q+x.path+q+' | '+x.line+' | '+x.type+' | '+safe(x.text)+' |'),
'',
'## Границы проверки',
'',
'Сканируются только исходные файлы каталога '+q+'src/'+q+': явные PowerShell-операции вывода, текстовые HTML-узлы и доступные подписи, литералы JS около UI-API. Скрытые динамически собранные строки, многорядные строковые выражения и косвенные ссылки могут остаться незамеченными. Каталоги документации, локализации и тестов не рассматриваются как исходный интерфейс.',
'',
'Технические идентификаторы LDAP/AD, SID, GUID, DNS/DN, имена GPO, команды PowerShell и ключи JSON не переводить. Полный машинный реестр всех обнаруженных кандидатов: '+q+'Localization/DOC6c-StaticSourceAudit.json'+q+'.',
''
].join('\n');
fs.writeFileSync(outMd,md,'utf8');
console.log('PASS DOC6c: '+files.length+' source files, '+stats.sourceLines+' lines, 54 translations, '+items.length+' heuristic review candidates');
