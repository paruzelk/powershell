// DOC6j: execute generated report functions on synthetic findings; never use private AD reports.
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const file=path.join(root,'src','modules','Reporting','templates','report-scripts.js');
const bytes=fs.readFileSync(file),js=bytes.toString('utf8');
assert.equal(bytes.subarray(0,3).toString('hex'),'efbbbf','report JS UTF-8 BOM lost');
function catalog(name){
 const marker='const '+name+' = ',pos=js.indexOf(marker);
 assert(pos>=0,'missing catalog '+name);
 const start=pos+marker.length,ends=[js.indexOf(';\n',start),js.indexOf(';\r\n',start)].filter(x=>x>=0);
 assert(ends.length>0,'missing end of '+name);
 return JSON.parse(js.slice(start,Math.min(...ends)));
}
function codeBetween(start,end){
 const i=js.indexOf(start);
 assert(i>=0,'missing function '+start);
 const j=js.indexOf(end,i);
 assert(j>i,'missing boundary '+end);
 return js.slice(i,j);
}
const full=catalog('ruFullFindingTechnical');
const brief=catalog('ruFindingExplanations');
const titles=catalog('ruFindingTitles');
assert.equal(Object.keys(full).length,392,'392 full technical types required');
assert.equal(Object.keys(brief).length,141,'141 short reviewed RU descriptions required');
assert.equal(Object.keys(titles).length,392,'392 translated titles required');
const escapeHtml=v=>String(v??'').replace(/&/g,'&amp;').replace(/</g,'&lt;')
 .replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
const window={};
const findingRender=vm.runInNewContext(
 codeBetween('function buildTooltipHtml(','function escapeHtml(')+'\n;buildTooltipHtml',
 {ruFullFindingTechnical:full,ruFindingExplanations:brief,ruFindingTitles:titles,escapeHtml,window},
 {timeout:5000});
const checkRender=vm.runInNewContext(
 codeBetween('function buildCheckTooltipHtml(','// CHECKBOX SYSTEM - Mark findings as completed')+
 '\n;buildCheckTooltipHtml',{escapeHtml,window},{timeout:5000});
let fallback=0,impact=0,remediation=0,attack=0;
for(const [id,content] of Object.entries(full)){
 const synthetic={title:'ORIGINAL EN TITLE',description:'ORIGINAL EN DESCRIPTION',
    impact:['ORIGINAL EN IMPACT'],attack:['ORIGINAL EN ATTACK'],
    remediation:['ORIGINAL EN REMEDIATION'],risk:'high'};
 const rendered=findingRender(synthetic,id,'finding');
 assert(rendered.includes(escapeHtml(content.description)),'full RU description absent '+id);
 assert(!rendered.includes('Краткое русское пояснение:'),'generic fallback present '+id);
 assert(!rendered.includes('Сверить с исходным текстом на английском'),'original panel shown '+id);
 assert(!rendered.includes('ORIGINAL EN DESCRIPTION'),'English body shown '+id);
 const specialized=brief[id]||{};
 if(!specialized.description){
   fallback++;
   assert(rendered.indexOf(escapeHtml(content.description))<
     rendered.indexOf('Подробное техническое описание'),'full RU not used as main description '+id);
 }
 if(!specialized.impact?.length&&content.impact?.length){
   assert(rendered.includes('<li>'+escapeHtml(content.impact[0])+'</li>'),'RU impact fallback '+id);
   impact++;
 }
 if(!specialized.remediation?.length&&content.remediation?.length){
   assert(rendered.includes('<li>'+escapeHtml(content.remediation[0])+'</li>'),'RU remediation fallback '+id);
   remediation++;
 }
 if(!specialized.attack?.length&&content.attack?.length){
   assert(rendered.includes('<li>'+escapeHtml(content.attack[0])+'</li>'),'RU attack fallback '+id);
   attack++;
 }
}
assert.equal(fallback,251,'251 finding types must use curated full RU fallback');
assert(impact>0&&remediation>0&&attack>0,'fallback fields not exercised');
const check={
 summary:'Русская сводка',whyItMatters:'Почему важно',whatWeCheck:['Проверяемый критерий'],
 ruDetailedCheckReady:false,originalEnglish:{whyItMatters:'ORIGINAL EN CHECK',
 whatWeCheck:['ORIGINAL EN CRITERIA']}
};
assert(!checkRender(check,'synthetic','note').includes('ORIGINAL EN CHECK'),
 'English check help shown by default');
window.adPEASShowOriginalEnglish=true;
const id=Object.keys(full)[0];
const original=findingRender({title:id,description:'ORIGINAL EN DESCRIPTION',risk:'high'},id,'finding');
assert(original.includes('ORIGINAL EN DESCRIPTION'),'developer English source lost');
assert(original.includes('Сверить с исходным текстом на английском (EN)'),
 'developer comparison toggle not functional');
assert(checkRender(check,'synthetic','note').includes('ORIGINAL EN CHECK'),
 'check comparison toggle not functional');
window.adPEASShowOriginalEnglish=false;
const escapedId=Object.keys(full).find(x=>!brief[x]?.description);
assert(escapedId,'no fallback candidate');
const saved=full[escapedId].description;
full[escapedId].description='Тест <img src=x onerror=alert(1)>';
const safe=findingRender({title:escapedId,risk:'high'},escapedId,'finding');
full[escapedId].description=saved;
assert(!safe.includes('<img src=x')&&safe.includes('&lt;img'),
 'untrusted display text not escaped');
console.log('PASS DOC6j: 392 descriptions, 251 full RU fallbacks, '+impact+
 ' impact, '+remediation+' remediation, '+attack+
 ' attack fallbacks, hidden EN by default, comparison opt-in, XSS protection');
