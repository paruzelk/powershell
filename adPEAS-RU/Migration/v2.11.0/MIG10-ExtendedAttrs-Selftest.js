// MIG10 synthetic HTML interaction gate: no AD, no browser, no risk logic.
'use strict';
const assert = require('assert'), fs = require('fs'), vm = require('vm');
const source = fs.readFileSync(process.argv[2], 'utf8').replace(/^\uFEFF/, '');
const first = source.indexOf('function toggleExtendedAttrs(objectId) {');
const last = source.indexOf('// Toggle individual object card', first);
assert(first >= 0 && last > first, 'original toggle function missing');
const fn = source.slice(first,last);
assert(!fn.includes(".replace('Show', 'Hide')"), 'old English Show/Hide remains');
assert(!fn.includes(".replace('Hide', 'Show')"), 'old English Hide/Show remains');
assert(source.includes("theme === 'dark' ? 'Светлая' : 'Тёмная'"));
for (const count of [1, 3, 15, 99]) {
    const label = {textContent: 'Показать дополнительные атрибуты: ' + count};
    const classes = new Set();
    const control = {classList:{
        add:x=>classes.add(x),remove:x=>classes.delete(x)
    },querySelector:x=>{assert.strictEqual(x,'span:last-child');return label;}};
    const ext = {style:{display:'none'},previousElementSibling:control};
    const doc = {getElementById:id=>{
        if(id === 'ext-test')return ext;
        if(id === 'icon-test')return {};
        throw new Error('Unexpected HTML ID '+id);
    }};
    const ctx = vm.createContext({document:doc});
    vm.runInContext(fn+'\nthis.toggleExtendedAttrs=toggleExtendedAttrs;',ctx);
    ctx.toggleExtendedAttrs('test');
    assert.strictEqual(ext.style.display,'block');
    assert.strictEqual(label.textContent,'Скрыть дополнительные атрибуты: '+count);
    assert(classes.has('expanded'));
    ctx.toggleExtendedAttrs('test');
    assert.strictEqual(ext.style.display,'none');
    assert.strictEqual(label.textContent,'Показать дополнительные атрибуты: '+count);
    assert(!classes.has('expanded'));
}
console.log('PASS MIG10: 4 counts x open and close, correct Russian text');
