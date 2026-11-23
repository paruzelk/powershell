// MIG11 source-backed UI regression. Runs without AD or browser.
'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const text=fs.readFileSync(process.argv[2],'utf8').replace(/^\uFEFF/,'');
function slice(a,b){
    const i=text.indexOf(a),j=text.indexOf(b,i+a.length);
    assert(i>=0&&j>i,'source anchor missing: '+a);return text.slice(i,j);
}
const drag=slice('function updateExtendedAttrCounters(movedElement) {','//  PRINT / PDF PREPARATION');
assert(!drag.includes(' more attribute(s)'), 'legacy English drag-drop counter');
for(const expanded of [false,true])for(const count of [0,1,15]){
    const label={textContent:'old'};
    const toggle={style:{},classList:{contains:x=>x==='expanded'&&expanded},
        querySelector:x=>{assert.strictEqual(x,'span:last-child');return label;}};
    const ext={style:{},querySelectorAll:()=>Array(count).fill({})};
    const body={querySelector:x=>x==='.extended-attrs'?ext:toggle};
    const moved={closest:x=>{assert.strictEqual(x,'.object-body');return body;}};
    const c=vm.createContext({});
    vm.runInContext(drag+'\nthis.run=updateExtendedAttrCounters;',c);
    c.run(moved);
    if(count===0){
        assert.strictEqual(toggle.style.display,'none');
        assert.strictEqual(ext.style.display,'none');
    }else{
        assert.strictEqual(label.textContent,(expanded?'Скрыть дополнительные атрибуты: ':'Показать дополнительные атрибуты: ')+count);
    }
}
const storage=slice('function clearAdPEASData() {','function toggleShortcutHelp() {');
const alerts=[],messages=[],prompts=[],items={};
const ctx=vm.createContext({
    localStorage:items,alert:x=>alerts.push(x),
    confirm:x=>{prompts.push(x);return false;},
    announceToScreenReader:x=>messages.push(x),
    location:{reload:()=>{throw Error('reload without confirmation');}}
});
vm.runInContext(storage+'\nthis.clear=clearAdPEASData;',ctx);
ctx.clear();
assert(alerts[0].includes('нет сохранённых данных'));
items['adpeas-theme']='dark';
items['adpeas-hide-completed']='true';
items['other-key']='unchanged';
ctx.clear();
assert(prompts[0].includes('Найдено сохранённых элементов: 2'));
assert(prompts[0].includes('ВСЕХ отчётах'));
assert.strictEqual(items['other-key'],'unchanged');
const print=slice('function buildPrintTOC() {','// Register print event handlers');
for(const phrase of ["'Оглавление отчёта'","'Нарушения', 'Предупреждения', 'Сведения', 'Безопасно'","'Итого'"])
    assert(print.includes(phrase),'print label: '+phrase);
const plain=slice('function formatScoreBreakdown(breakdown) {','// Format score breakdown as styled HTML tooltip content');
const reason=slice('function translateMIG9ScoreReason(raw) {','function formatScoreBreakdownHtml(');
const scoreCtx=vm.createContext({});
vm.runInContext(plain+reason+'\nthis.score=formatScoreBreakdown;',scoreCtx);
const v=scoreCtx.score({finalScore:42,baseScore:20,matchedPattern:'',impactMod:2,impactReason:'Disabled',
    exploitMod:1,exploitReasons:[],securityMod:1,securityReasons:[],
    correlationBonus:2,correlationReason:'Mitigated'});
assert(v.includes('Базовая оценка: 20'));
assert(v.includes('Последствия: ×2.00 (Учётная запись отключена)'));
assert(v.includes('Взаимосвязи: +2 (Риск снижен)'));
assert(v.includes('Итоговая оценка: 42'));
assert(text.includes('Команды приведены только для примера.'));
assert(text.includes('>Копировать</button>'));
assert(text.includes("button.textContent = 'Скопировано';"));
assert(text.includes("button.textContent = 'Ошибка';"));
assert(!text.includes("announceToScreenReader('Filtered by '"));
console.log('MIG11 PASS: 6 drag states, storage dialog, print labels, score text and clipboard strings');
