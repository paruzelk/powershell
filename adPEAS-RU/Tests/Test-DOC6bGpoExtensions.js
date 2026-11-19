// DOC6b: synthetic GPO CSE label regression; no production AD identifiers.
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict');
const js=fs.readFileSync(path.join(__dirname,'..','src/modules/Reporting/templates/report-scripts.js'),'utf8');
const start=js.indexOf('        // DOC6b BEGIN: field-scoped, human-readable GPO CSE labels.');
const end=js.indexOf('        // DOC6b END: no raw AD mutations.',start);
assert(start>=0&&end>start,'DOC6b block present');
assert.equal(js.indexOf('        // DOC6b BEGIN:',start+5),-1,'DOC6b only once');
const text=s=>({nodeType:3,nodeValue:s});
const elem=(name,...children)=>({nodeType:1,tagName:name,childNodes:children,firstChild:children[0]||null});
const guid='{53D6AB1D-2488-11D1-A28C-00C04FB94F17}',soft='{C6DC5466-785A-11D2-84D0-00C04FB169F7}';
const values=[
 elem('DIV',text('Registry (Wireless Group Policy)')),
 elem('DIV',elem('SPAN',text('Security (Security Settings)'))),
 elem('DIV',text(soft+' (Software Installation)')),
 elem('DIV',text('Registry ('+guid+')'),elem('BR'),text('EFS Recovery ('+guid+')')),
 elem('DIV',text('Security (Security Settings) ')),
 elem('DIV',elem('CODE',text('Security (Security Settings)'))),
 elem('DIV',text('Registry ({INVALID-GUID})')),
 elem('DIV',text('Registry (VPN Configuration)'))
];
const irrelevant=elem('DIV',text('Registry (Wireless Group Policy)'));
let ready;
const document={
 addEventListener:(type,cb)=>{assert.equal(type,'DOMContentLoaded');ready=cb;},
 querySelectorAll:q=>{
  assert.equal(q,'.attr-row[data-attr-name="gpcmachineextensionnames"] .attr-value');
  return values;}
};
const window={};
const snapshot=values.map(v=>JSON.stringify((function shape(n){return [n.tagName,...(n.childNodes||[]).map(shape)]})(v)));
vm.runInNewContext(js.slice(start,end),{document,window,Node:{TEXT_NODE:3,ELEMENT_NODE:1}},{timeout:4000});
assert.equal(typeof ready,'function');
ready();
function value(n){return n.nodeType===3?n.nodeValue:(n.childNodes||[]).map(value).join(' | ');}
assert.equal(value(values[0]),'Реестр (групповая политика беспроводной сети)');
assert.equal(value(values[1]),'Безопасность (параметры безопасности)');
assert.equal(value(values[2]),soft+' (установка программного обеспечения)');
assert(value(values[3]).includes('Реестр ('+guid+')'));
assert(value(values[3]).includes('Восстановление EFS ('+guid+')'));
assert.equal(value(values[4]),'Безопасность (параметры безопасности) ');
assert.equal(value(values[5]),'Security (Security Settings)');
assert.equal(value(values[6]),'Registry ({INVALID-GUID})');
assert.equal(value(values[7]),'Registry (VPN Configuration)');
assert.equal(value(irrelevant),'Registry (Wireless Group Policy)');
assert.equal(window.adPEASRUDOC6b.translatedTextNodes,6);
values.forEach((v,i)=>assert.equal(JSON.stringify((function shape(n){return [n.tagName,...(n.childNodes||[]).map(shape)]})(v)),snapshot[i]));
ready();
assert.equal(window.adPEASRUDOC6b.translatedTextNodes,0,'idempotence');
console.log('PASS DOC6b: five GPO CSE label patterns, six text nodes, GUID preservation, zero cross-field changes, idempotence');
