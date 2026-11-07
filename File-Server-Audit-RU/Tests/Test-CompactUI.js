'use strict';
// File-Server-Audit RU 1.0.17 compact UI regression.
// Run: node Tests/Test-CompactUI.js  (Node.js built-ins only)
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const html = fs.readFileSync(path.join(__dirname,'..','AccessMapTemplate.html'),'utf8');
const jsStart = "<script>\n'use strict';";
const ix = html.indexOf(jsStart);
assert.ok(ix >= 0, 'inline report script exists');
const script = html.slice(ix + '<script>'.length,html.indexOf('</script>',ix))
  .replace(/^\s*init\(\);\s*$/m,'');
const css = html.slice(html.indexOf('<style>')+7, html.indexOf('</style>'));
assert.match(css, /RU_COMPACT_UI_1_0_17/);
assert.match(css, /#content\.content-split\s*\{\s*padding:8px 10px 5px/);
assert.match(css, /\.graphControlsHost\s*\{[\s\S]*?overflow-x:auto/);
assert.match(css, /\.detailTabs\s*\{[\s\S]*?flex-wrap:nowrap/);
assert.match(css, /\.paneSplitter\s*\{\s*height:5px;\s*margin:3px 0/);
assert.match(css, /button:not\(:disabled\):active\s*\{[\s\S]*?transform:translateY\(1px\) scale\(\.97\)/);
assert.match(css, /button:focus-visible/);
class FakeElement {
  constructor(tag) {
    this.tag = tag; this.children = []; this.attrs = {}; this.events = {};
    this.className = ''; this.style = {}; this.dataset = {};
    this.textContent = ''; this.title = '';
    this.classes = new Set();
    this.classList = {
      add: (...x) => x.forEach(k=>this.classes.add(k)),
      remove: (...x) => x.forEach(k=>this.classes.delete(k)),
      contains: x=>this.classes.has(x),
      toggle: (x,v)=>{
        if(v===undefined)v=!this.classes.has(x);
        v?this.classes.add(x):this.classes.delete(x);
        return v;
      }
    };
  }
  set innerHTML(x) { this.html=x; this.children=[]; }
  get innerHTML() { return this.html||''; }
  appendChild(x) { this.children.push(x); x.parentNode=this; return x; }
  setAttribute(k,x) { this.attrs[k]=String(x); }
  getAttribute(k) { return this.attrs[k]; }
  addEventListener(k,f) { (this.events[k] ||= []).push(f); }
  removeEventListener(k,f) { this.events[k]=(this.events[k]||[]).filter(x=>x!==f); }
  getBoundingClientRect() { return {left:0,top:0,width:1200,height:550}; }
  setPointerCapture() {}
  hasPointerCapture() { return false; }
}
const doc = {
  documentElement:new FakeElement('html'),
  createElement:k=>new FakeElement(k),
  createElementNS:(_,k)=>new FakeElement(k),
  getElementById:()=>new FakeElement('div'),
  addEventListener(){},removeEventListener(){}
};
const m = {
  identities:[{name:'TEST\\User',type:'User',enabled:true}],
  folders:[{path:'\\\\server\\share',share:'\\\\server\\share'}],
  shares:[], maxEdgesPerNode:60
};
const factory = new Function(
  'ACCESS_MAP_MANIFEST','document','window','history','location','console',
  script + "\nreturn function(){\n" +
  " precompute(); state.graphDepth=2; state.detailTab='graph';\n" +
  " const tabs=renderDetailTabs(()=>{});\n" +
  " const host=tabs._graphControlsHost;\n" +
  " const g={layers:[['f:0'],['i:0']],visited:new Map([['f:0',{hop:0,from:null}],['i:0',{hop:1,from:'f:0',edgeInfo:{edges:[{type:'access',e:[0,0,0,false,false,false,-1]}]}}]]),extraLinks:[],truncated:false};\n" +
  " const pos=layoutRadial(g.layers,g.visited);\n" +
  " let callbackCount=0;\n" +
  " const graph=renderRelationshipGraphInner(g,pos,'f:0',()=>{},()=>callbackCount++,host);\n" +
  " const toolbar=host.children[0];\n" +
  " const buttons=toolbar.children.filter(x=>x.tag==='button');\n" +
  " const d4=buttons.find(x=>x.className.startsWith('depthBtn')&&x.textContent==='4');\n" +
  " d4.onclick();\n" +
  " const rights=buttons.find(x=>x.className==='chipBtn graphRightsToggle');\n" +
  " const rightsBefore=rights.textContent;rights.onclick();\n" +
  " const svg=graph.children.find(x=>x.className==='graphCanvas').children.find(x=>x.tag==='svg');\n" +
  " const beforeZoom=svg.getAttribute('viewBox');\n" +
  " const plus=buttons.find(x=>x.title==='Увеличить масштаб');plus.onclick();\n" +
  " const afterZoom=svg.getAttribute('viewBox');\n" +
  " const help=buttons.find(x=>x.className==='zoomBtn graphHelpBtn');\n" +
  " state.detailTab='tree';const treeTabs=renderDetailTabs(()=>{});\n" +
  " const fallback=renderRelationshipGraphInner(g,pos,'f:0',()=>{},()=>{});\n" +
  " return {tabs,host,graph,toolbar,buttons,callbackCount,depth:state.graphDepth,rightsBefore,rightsAfter:rights.textContent,zoomChanged:beforeZoom!==afterZoom,help,treeTabs,fallback};\n" +
  "};"
);
const result = factory(m,doc,{matchMedia:()=>({matches:false})},{},{},console)();
assert.equal(result.tabs.children.length,3, 'tab buttons and graph controls share a row');
assert.equal(result.tabs.children[2],result.host);
assert.equal(result.toolbar.className,'graphToolbar');
assert.equal(result.host.children[0],result.toolbar);
assert.ok(result.graph.children.every(x=>x!==result.toolbar), 'graph itself has no toolbar row');
assert.ok(result.graph.children.some(x=>x.className==='graphCanvas'));
assert.equal(result.depth,4);
assert.equal(result.callbackCount,1);
assert.equal(result.rightsBefore,'Права: всегда');
assert.equal(result.rightsAfter,'Права: при наведении');
assert.ok(result.zoomChanged,'zoom control remains functional');
assert.equal(result.help.textContent,'?');
assert.match(result.help.title,/Глубина 1/);
assert.equal(result.treeTabs.children.length,2,'tree view has no unused controls host');
assert.equal(result.fallback.children[0].className,'graphToolbar',
  'standalone render keeps existing toolbar for legacy tests');
console.log('PASS: compact graph UI, inline controls, zoom, depth, labels, help, fallback.');
