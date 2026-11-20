// MIG9 synthetic UI regression. No AD or browser dependency, no risk calculation changes.
'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const src=fs.readFileSync(process.argv[2],'utf8').replace(/^\uFEFF/,'');
function catalog(name){
    const marker='const '+name+' = ';
    const line=src.split('\n').find(x=>x.includes(marker));
    assert(line,'missing catalog '+name);
    const json=line.slice(line.indexOf(marker)+marker.length).trim();
    assert(json.endsWith(';'),name+' catalog structure');
    return JSON.parse(json.slice(0,-1));
}
function fn(a,b){
    const i=src.indexOf(a),j=src.indexOf(b,i+1);
    assert(i>=0&&j>i,'missing function '+a);
    return src.slice(i,j);
}
const ruMIG2CheckDetails=catalog('ruMIG2CheckDetails'),ruMIG2Technical=catalog('ruMIG2Technical');
const ids={PrivilegedGroupMember:'PRIVILEGED_GROUP_MEMBERSHIP',
           Tier0Account:'PRIVILEGED_GROUP_MEMBERSHIP',
           PasswordNeverExpires:'PASSWORD_NEVER_EXPIRES'};
const findingDefinitions={},checkDescriptions={};
for(const [type,id] of Object.entries(ids)){
    assert(/[А-Яа-я]/.test(ruMIG2CheckDetails[type]?.whyItMatters||''),'missing RU check text: '+type);
    assert(/[А-Яа-я]/.test(ruMIG2Technical[id]?.remediation?.[0]||''),'missing RU advice: '+id);
    findingDefinitions[id]={title:'English title',remediation:['English recommendation']};
    checkDescriptions[type]={title:'Проверка '+type,primaryFindingId:id,
       summary:'English summary',whyItMatters:'English impact',whatWeCheck:['English item']};
}
const findingCards=Object.keys(ids).map(type=>({
    objectType:type,title:checkDescriptions[type].title,section:'Учётные записи',
    category:'accounts',severity:'finding',objectCount:6,findingIds:[ids[type]]
}));
const container={innerHTML:''};
let captured='';
const context={
    document:{getElementById:id=>id==='topActionsContainer'?container:null,querySelectorAll:()=>[]},
    scoringContext:{findingCards},
    scoreThresholds:{critical:80,high:60,medium:40,low:20},
    findingDefinitions,checkDescriptions,ruMIG2CheckDetails,ruMIG2Technical,
    calculateScoreFromMetadata:m=>({finalScore:100-Object.keys(ids).indexOf(m.objectType)}),
    findBestFindingDefinition:m=>findingDefinitions[ids[m.objectType]],
    escapeHtml:x=>String(x).replaceAll('&','&amp;').replaceAll('<','&lt;'),
    escapeJsonForAttr:x=>JSON.stringify(x),
    showTooltipAt:(_,html)=>{captured=html;},console
};
vm.createContext(context);
vm.runInContext(fn('function generateTopPriorityActions() {','        function scrollToFindingCard('),context);
context.generateTopPriorityActions();
const html=container.innerHTML;
assert.strictEqual((html.match(/class="top-action-item"/g)||[]).length,3,'expected three priority actions');
for(const [type,id] of Object.entries(ids)){
    assert(html.includes(ruMIG2CheckDetails[type].whyItMatters.replaceAll('&','&amp;')),type+' original RU description not used');
    assert(html.includes(ruMIG2Technical[id].remediation[0].replaceAll('&','&amp;')),id+' original RU remediation not used');
}
assert(html.includes('Затронуто объектов: 6'),'source count label');
assert(!html.includes('English impact')&&!html.includes('English recommendation')&&!html.includes(' affected</span>'),'raw English leaked');
for(const n of [100,99,98])assert(html.includes('>'+n+'</span>'),'score changed: '+n);
vm.runInContext(fn('function showTopActionInfo(', '        function showTooltipAt('),context);
context.showTopActionInfo({},'PrivilegedGroupMember','Проверка привилегированных групп');
for(const t of ['Почему это важно','Что проверяется',ruMIG2CheckDetails.PrivilegedGroupMember.whyItMatters]){
    assert(captured.includes(t),'popup text '+t.slice(0,30));
}
assert(!captured.includes('English impact')&&!captured.includes('Why It Matters'),'untranslated popup');
vm.runInContext(fn('function translateMIG9ScoreReason(', '        // Active score tooltip reference'),context);
const score=context.formatScoreBreakdownHtml({
    finalScore:85,baseScore:40,matchedPattern:'PRIVILEGED_GROUP_MEMBERSHIP',
    impactMod:1.2,impactReason:'Tier 0',exploitMod:1.1,exploitReasons:['Old password'],
    securityMod:1,securityReasons:[],correlationBonus:2,correlationReason:'correlation'
});
for(const t of ['Состав оценки риска','Базовая оценка','Последствия','Возможность эксплуатации','Взаимосвязи']){
    assert(score.includes(t),'score label '+t);
}
console.log('PASS MIG9 UI: three RU priority details, original scores and matching RU advice, RU popup, RU score labels');
