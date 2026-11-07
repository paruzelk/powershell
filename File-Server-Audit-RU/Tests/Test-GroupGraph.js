'use strict';
// File-Server-Audit RU grouped graph regression tests.
// Optional: run "node Tests/Test-GroupGraph.js"; no npm packages needed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const html = fs.readFileSync(path.join(__dirname,'..','AccessMapTemplate.html'),'utf8');
const start = "<script>\n'use strict';";
const at = html.indexOf(start);
assert.ok(at !== -1, 'HTML inline JS exists');
const end = html.indexOf('</script>',at);
assert.ok(end > at, 'HTML inline JS is terminated');
const js = html.slice(at + '<script>'.length,end).replace(/^\s*init\(\);\s*$/m,'');

class FakeElement {
  constructor(tag) {
    this.tag=tag;this.attrs={};this.children=[];this.events={};
    this.style={};this.dataset={};this.className='';this.textContent='';this.title='';
    this._classes=new Set();this._captured=new Set();
    this.classList={
      add:(...names)=>names.forEach(x=>this._classes.add(x)),
      remove:(...names)=>names.forEach(x=>this._classes.delete(x)),
      contains:x=>this._classes.has(x),
      toggle:(x,v)=>{if(v===undefined)v=!this._classes.has(x);
        v?this._classes.add(x):this._classes.delete(x);return v;}
    };
  }
  set innerHTML(v){this._innerHTML=v;this.children=[];}
  get innerHTML(){return this._innerHTML||'';}
  appendChild(n){const i=this.children.indexOf(n);if(i>=0)this.children.splice(i,1);
    this.children.push(n);n.parentNode=this;return n;}
  setAttribute(k,v){this.attrs[k]=String(v);}
  getAttribute(k){return this.attrs[k];}
  addEventListener(k,f){(this.events[k] ||= []).push(f);}
  removeEventListener(k,f){this.events[k]=(this.events[k]||[]).filter(x=>x!==f);}
  getBoundingClientRect(){return {left:0,top:0,width:960,height:560};}
  setPointerCapture(id){this._captured.add(id);}
  hasPointerCapture(id){return this._captured.has(id);}
  releasePointerCapture(id){this._captured.delete(id);}
}
function makeDocument(){
  return {events:{},documentElement:new FakeElement('html'),
    createElement:x=>new FakeElement(x),
    createElementNS:(_,x)=>new FakeElement(x),
    getElementById:()=>new FakeElement('div'),
    addEventListener(k,f){(this.events[k] ||= []).push(f);},
    removeEventListener(k,f){this.events[k]=(this.events[k]||[]).filter(x=>x!==f);}
  };
}
const identities=[
  {name:'DOM\\GroupA',type:'Group',members:[1,2],shareKeys:[],edgeCount:1},
  {name:'DOM\\Dual',type:'User',shareKeys:[],edgeCount:2},
  {name:'DOM\\ViaOnly',type:'User',shareKeys:[],edgeCount:1},
  {name:'DOM\\DirectOnly',type:'User',shareKeys:[],edgeCount:1},
  {name:'DOM\\GroupB',type:'Group',members:[1],shareKeys:[],edgeCount:1}
];
const manifest={identities,
  folders:[{path:'\\\\SHARE\\Network',share:'\\\\SHARE\\Network',broken:false}],
  shares:[],maxEdgesPerNode:60,rightsDistribution:[6,1,0,0,0,0],totalEdgeCount:7};
const rows=[
 [0,0,0,0,0,0,-1], // GroupA ACL
 [0,4,1,0,0,0,-1], // GroupB ACL
 [0,1,0,0,0,0,-1], // Dual direct ACL
 [0,3,0,0,0,0,-1], // Direct-only ACL
 [0,1,0,0,0,0,0],  // Dual through GroupA
 [0,2,0,0,0,0,0],  // ViaOnly through GroupA
 [0,1,1,0,0,0,4]   // Dual through GroupB
];
const harnessBody=[
  'precompute();mergeEdges(rows);',
  "const keys=Array.from(adjacency.get('f:0').keys()).sort();",
  "const g=await buildEgoGraph(center||'f:0',depth,600,60);",
  "const positions=layoutRadial(g.layers,g.visited);",
  'let visual=null;',
  'if(render){',
  " const wrap=renderRelationshipGraphInner(g,positions,'f:0',()=>{},()=>{});",
  " const canvas=wrap.children.find(x=>x.className==='graphCanvas');",
  " const svg=canvas.children.find(x=>x.tag==='svg');",
  " const edges=svg.children[0],nodes=svg.children[1];",
  " const user=nodes.children.find(x=>x.getAttribute('data-key')==='i:1');",
  " const secondary=edges.children.filter(x=>x.getAttribute('class')==='graphSecondaryEdge');",
  " const direct=secondary.find(x=>x.getAttribute('data-reason')==='additionalDirectAcl');",
  " const member=secondary.find(x=>x.getAttribute('data-reason')==='additionalMembership');",
  " const badges=user.children.filter(x=>x.getAttribute('class')==='graphRightsTag');",
  " const old=[user.getAttribute('transform'),direct.getAttribute('x2'),member.getAttribute('x2')];",
  " const ev=(id,x,y)=>({button:0,pointerId:id,clientX:x,clientY:y,cancelable:true,stopPropagation(){},preventDefault(){}});",
  ' user.events.pointerdown[0](ev(3,100,100));',
  ' document.events.pointermove.forEach(f=>f(ev(3,180,150)));',
  ' document.events.pointerup.forEach(f=>f(ev(3,180,150)));',
  " const moved=[user.getAttribute('transform'),direct.getAttribute('x2'),member.getAttribute('x2')];",
  " const reset=wrap.children[0].children.find(x=>x.title==='Сбросить масштаб и расположение узлов');",
  ' reset.onclick();',
  " const restored=[user.getAttribute('transform'),direct.getAttribute('x2'),member.getAttribute('x2')];",
  ' visual={secondary,badges,user,old,moved,restored};',
  '}',
  'return {g,keys,visual,edgeCount:DATA.edges.length,folderRows:byFolder.get(0).length};'
].join('\n');
async function run(m,aces,depth,render=false,center='f:0'){
  const doc=makeDocument();
  const factory=new Function('ACCESS_MAP_MANIFEST','document','window','history','location','console',
    js+'\nreturn async function(rows,depth,render,center){\n'+harnessBody+'\n};');
  return factory(m,doc,{matchMedia:()=>({matches:false})},{},{},console)(aces,depth,render,center);
}
(async()=>{
  const r=await run(manifest,rows,2,true);
  assert.deepEqual(r.keys,['i:0','i:1','i:3','i:4'],
    'group-expanded members must not become direct ACLs');
  assert.equal(r.edgeCount,rows.length,'all raw ACE rows remain');
  assert.equal(r.folderRows,rows.length,'tables retain original ACE rows');
  assert.equal(r.g.visited.get('i:2').from,'i:0','via-only user under group');
  assert.equal(r.g.visited.get('i:1').from,'i:0','dual user under group');
  assert.equal(r.g.visited.get('i:1').hop,2);
  assert.equal(r.g.visited.get('i:3').from,'f:0','direct-only user at folder');
  assert.ok(r.g.extraLinks.some(x=>x.from==='f:0'&&x.to==='i:1'&&
    x.reason==='additionalDirectAcl'),'dual direct ACL drawn');
  assert.ok(r.g.extraLinks.some(x=>x.from==='i:4'&&x.to==='i:1'&&
    x.reason==='additionalMembership'),'second group retained');
  assert.equal(r.visual.secondary.length,2,'both secondary edges rendered');
  assert.equal(r.visual.badges.length,2,'group and direct ACL badges');
  assert.ok(r.visual.badges.every(x=>x.parentNode===r.visual.user));
  assert.notDeepEqual(r.visual.moved,r.visual.old,'drag moved nodes and lines');
  assert.equal(r.visual.old[0]===r.visual.moved[0],false);
  assert.equal(r.visual.old[1]===r.visual.moved[1],false);
  assert.equal(r.visual.old[2]===r.visual.moved[2],false);
  assert.deepEqual(r.visual.restored,r.visual.old,'reset restores all lines');
  const one=await run(manifest,rows,1);
  assert.ok(one.g.visited.has('i:1'));
  assert.ok(!one.g.visited.has('i:2'),'depth 1 shows only direct relationships');
  const missing=await run({...manifest,identities:[{...identities[0],members:[1]},identities[1]],
    totalEdgeCount:1},[[0,1,0,0,0,0,0]],2);
  assert.equal(missing.g.visited.get('i:0').edgeInfo.edges[0].type,'inferredGroupGrant');
  assert.equal(missing.g.visited.get('i:1').from,'i:0');
  const dualUser=await run(manifest,rows,2,false,'i:1');
  assert.equal(dualUser.g.visited.get('f:0').from,'i:1','user direct folder grant');
  assert.ok(dualUser.g.extraLinks.some(x=>x.from==='i:0'&&x.to==='f:0'&&
    x.reason==='additionalGroupAcl'),'user also accesses folder via GroupA');
  assert.ok(dualUser.g.extraLinks.some(x=>x.from==='i:4'&&x.to==='f:0'&&
    x.reason==='additionalGroupAcl'),'user also accesses folder via GroupB');
  const viaOnlyUser=await run(manifest,rows,2,false,'i:2');
  assert.equal(viaOnlyUser.g.visited.get('i:0').from,'i:2');
  assert.equal(viaOnlyUser.g.visited.get('f:0').from,'i:0',
    'user without direct ACL reaches folder through granting group');
  assert.ok(html.includes('graphDepth: 2,'),'group tree is default');
  console.log('PASS grouped ACL graph: viaGroup, dual ACL, multi-group, depth 1,');
  console.log('     missing group ACE, identity-centered routes, original records, drag, reset');
})().catch(err=>{console.error(err);process.exitCode=1;});
