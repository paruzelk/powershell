// MIG4: deterministic UI smoke test using synthetic DOM nodes only.
// No network, LDAP, domain-specific report, or third-party JS libraries.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
const dir = __dirname;
const words = JSON.parse(fs.readFileSync(path.join(dir,'MIG4-VisibleReportTexts.ru-RU.json'),'utf8'));
const runtime = fs.readFileSync(path.join(dir,'MIG4-ReportRuntime.js'),'utf8')
    .replace('__MIG4_CATALOG_JSON__', JSON.stringify(words));
function element(text, kind, props = {}) {
    const child = {nodeType:3,nodeValue:text};
    const attrs = Object.assign({},props);
    return {
        nodeType:1,childNodes:[child],childElementCount:0,
        textContent:text,querySelectorAll(){return [];},
        matches(selector){return selector.includes(kind);},
        getAttribute(k){return attrs[k] || null;},
        setAttribute(k,v){attrs[k]=v;},
        _text:child,_attrs:attrs
    };
}
const title = element('[1/9] Analyzing Domain Configuration','.section-title');
const count = element('3 item(s)','.finding-count');
const line = element('No LAPS schema found','.finding-item.finding-line');
const object = element('Domain Controllers (3)','.object-header');
const sidebar = element('Accounts','.nav-item');
const status = element('Not Configured','.attr-value');
const button = element('', '[title]', {'title':'Click for more info'});
let onLoad = null;
let onChange = null;
const document = {
    nodeType:9,body:{nodeType:1},
    addEventListener(event,callback){if(event==='DOMContentLoaded')onLoad=callback;},
    querySelectorAll(selector){
        if(selector.startsWith('.attr-value >'))return [status];
        if(selector.startsWith('[title]'))return [button];
        return [title,count,line,object,sidebar];
    }
};
class MutationObserver {
    constructor(callback){onChange=callback;}
    observe() {}
}
vm.runInNewContext(runtime,{document,MutationObserver,console},{filename:'MIG4-ReportRuntime.js'});
assert(onLoad,'Missing document ready listener');
onLoad();
assert.strictEqual(title._text.nodeValue,'[1/9] Анализ настроек домена');
assert.strictEqual(count._text.nodeValue,'Объектов: 3');
assert.strictEqual(line._text.nodeValue,'Атрибуты схемы LAPS не обнаружены');
assert.strictEqual(object._text.nodeValue,'Контроллеры домена (3)');
assert.strictEqual(sidebar._text.nodeValue,'Учётные записи');
assert.strictEqual(status.textContent,'Не настроено');
assert.strictEqual(button._attrs.title,'Подробности проверки');
assert(onChange,'Missing dynamic DOM observer');
const late = element('No Exchange Organization detected','.finding-item.finding-line');
onChange([{addedNodes:[late]}]);
assert.strictEqual(late._text.nodeValue,'Организация Exchange не обнаружена.');
console.log('MIG4 UI PASS: section, count, check line, object, sidebar, status, title attribute, dynamic node');
