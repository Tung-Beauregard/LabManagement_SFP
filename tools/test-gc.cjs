/* Isolated GC regression tests. No live Firebase or NIST calls.
   npm module: playwright (or set PLAYWRIGHT_MODULE to its absolute directory).
   Optional CHROME_PATH selects a local Chrome installation. */
const fs=require('fs'),path=require('path'),http=require('http'),vm=require('vm'),assert=require('node:assert/strict');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const index=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
const gc=Buffer.from(index.match(/GC_IFRAME_B64\s*=\s*"([^"]+)"/)[1],'base64').toString('utf8');
let checks=0;
function check(name,value){assert.ok(value,name);checks++;console.log('PASS '+name);}
const clone=x=>JSON.parse(JSON.stringify(x));
async function browserTests(){
 const server=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html; charset=utf-8');res.end(req.url==='/gc.html'?gc:'<!doctype html><button id="outside">outside</button><iframe id="gcFrame" src="/gc.html" style="width:1300px;height:1000px"></iframe>');});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 let browser;
 try{
  browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
  const page=await browser.newPage({viewport:{width:1450,height:1100}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',r=>r.request().url().startsWith('http://127.0.0.1:')?r.continue():r.abort());
  await page.goto('http://127.0.0.1:'+server.address().port);
  let frame=page.frames().find(f=>f.url().endsWith('/gc.html'));
  await frame.waitForFunction(()=>typeof renderMain==='function');
  await page.evaluate(()=>{window.requests=[];window.addEventListener('message',e=>{if(e.data?.gcRequest)requests.push(e.data.gcRequest)});});
  const createSample=async()=>frame.evaluate(()=>{
    const L=['RT,Intensity'];for(let i=0;i<=2000;i++){const t=5+i*.005;L.push(t+','+(100+1e6*Math.exp(-.5*((t-8)/.07)**2)+5e5*Math.exp(-.5*((t-12)/.1)**2)));}
    const s=parseCSV(L.join('\n'),'synthetic.csv');samples=[s];cur=s.id;params={...params,rtMin:5,rtMax:15,minPct:.1,prom:2500,bleed:30};renderRail();renderMain();
  });
  await createSample();
  let r=await frame.evaluate(()=>{const p=activePeaks(samples[0]);return {rt:p.map(x=>x.rt),pct:p.map(x=>x.pct),svg:chartSVG(samples[0],{})};});
  check('two synthetic peaks at expected RT',r.rt.length===2&&r.rt[0]===8&&r.rt[1]===12);
  check('areas match analytical Gaussian ratio',Math.abs(r.pct[0]-100*7/12)<.01&&Math.abs(r.pct.reduce((a,b)=>a+b,0)-100)<1e-8);
  check('single plot finite',!(/NaN|Infinity/.test(r.svg)));
  r=await frame.evaluate(()=>{const s=samples[0];s.manualText=tabulateText(s);s.manualOn=true;const p=activePeaks(s);return {count:p.length,finite:p.every(x=>Number.isFinite(x.pct)),svg:overlaySVG([s,{...s,id:'other',ab:s.ab.map(x=>x*.1)}])};});
  check('valid manual integration and overlay',r.count===2&&r.finite&&!/NaN|Infinity/.test(r.svg));
  r=await frame.evaluate(()=>{
   const s=samples[0];alkSets=[{id:'old',name:'Calibration',rows:[[8,6],[9,10],[10,14]]}];s.alkSetId='old';
   window.exportedGc=buildExportCsv(s);const before=calcKI(8,setOf(s));
   alkSets=[{id:'cloud',name:'Calibration',rows:[[8,5],[9,9],[10,13]],created_by_uid:'admin'}];
   importGcFile(exportedGc,'roundtrip.csv');return {before,after:calcKI(8,setOf(samples.at(-1))),snapshot:!!samples.at(-1).alkSnapshot};
  });check('same-name imported calibration preserves KI',r.before===856&&r.after===856&&r.snapshot);
  const shared={kidb:[['Linalool',1096]],pending:[],alkSets:[{id:'cloud',name:'Calibration',rows:[[8,5],[9,9],[10,13]],created_by_uid:'admin'}]};
  async function push(data){await page.evaluate(d=>document.getElementById('gcFrame').contentWindow.postMessage(d,'*'),data);await frame.evaluate(()=>new Promise(r=>setTimeout(r,30)));}
  await push({gcIdentity:{uid:'admin',name:'Admin',isAdmin:true},gcShared:shared});
  check('cloud sync preserves imported calibration',await frame.evaluate(()=>calcKI(8,setOf(samples.at(-1)))===856));
  await frame.evaluate(()=>save());await page.reload();frame=page.frames().find(f=>f.url().endsWith('/gc.html'));await frame.waitForFunction(()=>typeof setOf==='function');
  check('reload preserves imported calibration',await frame.evaluate(()=>calcKI(8,setOf(samples.at(-1)))===856));
  await push({gcIdentity:{uid:'admin',name:'Admin',isAdmin:true},gcShared:shared});
  await frame.evaluate(()=>{editSetId='cloud';drawAlk();pnAlk.classList.add('on');setName.value='My unsaved draft';});
  await push({gcShared:{...shared,pending:[{id:'p',name:'New proposal',ki:1234,status:'pending',by:'Other',at:'2026-10-25'}]}});
  check('unrelated cloud update preserves draft',await frame.evaluate(()=>setName.value==='My unsaved draft'));
  check('draft is separate from shared calibration',await frame.evaluate(()=>alkSets[0].name==='Calibration'));
  await push({gcShared:{...shared,alkSets:[{...shared.alkSets[0],name:'Other user edit'}]}});
  check('conflicting cloud update retains local draft',await frame.evaluate(()=>setName.value==='My unsaved draft'&&alkSets[0].name==='Other user edit'));
  await push({gcAlkSaved:{...shared.alkSets[0],name:'Saved first draft'}});
  check('save acknowledgment keeps later typing and advances base',await frame.evaluate(()=>setName.value==='My unsaved draft'&&alkDraftBases.get('cloud').name==='Saved first draft'));
  const newId=await frame.evaluate(()=>{newSet({id:'new-draft',name:'New set',rows:[[8,6],[10,12]]});return editSetId;});
  await push({gcShared:shared});
  check('new set remains available before cloud creation finishes',await frame.evaluate(id=>editSetId===id&&alkDrafts.has(id),newId));
  await frame.evaluate(()=>{editSetId='cloud';drawAlk();setName.value='Applied calibration';document.getElementById('alkSave').click();});
  r=await frame.evaluate(()=>{const s=samples.find(x=>x.id===cur),a=setOf(s);return {name:a.name,local:a.local,options:[...document.getElementById('fAlk').options].map(o=>o.value),id:a.id};});
  check('applied snapshot and live shared set are separately selectable',r.local&&r.name==='Applied calibration'&&r.options.includes('cloud')&&r.options.includes(r.id));
  await push({gcShared:{...shared,alkSets:[{...shared.alkSets[0],rows:[[8,7],[9,11],[10,14]]}]}});
  check('applied snapshot unaffected by later shared edits',await frame.evaluate(()=>setOf(samples.find(x=>x.id===cur)).rows[0][1]===5));
  await frame.evaluate(()=>{pnAlk.classList.remove('on');});
  r=await frame.evaluate(()=>({end:calcKI(12,{rows:[[8,6],[10,12]]}),mid:calcKI(Math.sqrt(72),{rows:[[8,6],[10,12]]}),bad:calcKI(8,{rows:[[8,6],[9,6]]}),regular:calcKI(8,{rows:[[8,6],[9,10]]})}));
  check('sparse carbon numbers and endpoints',r.end===1000&&r.mid===900);
  check('invalid standards rejected; contiguous calculation unchanged',r.bad===null&&r.regular===856);
  await createSample();
  r=await frame.evaluate(()=>{const s=samples[0];s.title='Sample "A" standard';renderMain();return document.getElementById('fTitle').value;});
  check('quoted title survives DOM rendering',r==='Sample "A" standard');
  // Install the actual main-page idle implementation and trusted bridge listener.
  const idle=index.slice(index.indexOf('const IDLE_LOGOUT_MS ='),index.indexOf('function findAccount('));
  const marker="  if(ev.data && ev.data.gcRequest) handleGcRequest(ev.data.gcRequest);";
  const listenerEnd=index.indexOf(marker)+marker.length;
  const listenerStart=index.lastIndexOf("window.addEventListener('message'",listenerEnd);
  await page.addScriptTag({content:"let currentUser={uid:'admin'};function showToast(){};function handleGcRequest(){};"+idle+index.slice(listenerStart,index.indexOf('});',listenerEnd)+3)});
  await page.evaluate(()=>{lastUserActivityAt=1;lastActivityResetAt=0;});
  await frame.locator('#fTitle').click();
  await page.waitForFunction(()=>lastUserActivityAt>1);
  check('trusted iframe activity resets parent idle time',await page.evaluate(()=>Date.now()-lastUserActivityAt<3000));
  await page.evaluate(()=>{lastUserActivityAt=1;lastActivityResetAt=0;window.dispatchEvent(new MessageEvent('message',{data:{gcActivity:true},source:window}));});
  check('unrelated message cannot reset idle time',await page.evaluate(()=>lastUserActivityAt===1));
  r=await frame.evaluate(()=>{const s=samples[0];renderMain();mintText.value='1\t15\tM\t0.1\t-\t15\t16';document.getElementById('mintApply').click();return {on:s.manualOn,msg:document.getElementById('mintMsg').textContent,html:document.getElementById('main').textContent};});
  check('out-of-range manual integration rejected through UI',!r.on&&r.msg.includes('範圍')&&!r.html.includes('NaN'));
  r=await frame.evaluate(()=>{const s={...samples[0],manualOn:true,manualText:'1\t8\tM\t0.1\t0\t7.8\t8.2'};return activePeaks(s).map(x=>x.pct);});
  check('zero total manual area stays finite',r.length===1&&r[0]===0);
  r=await frame.evaluate(async()=>{
   const s=samples[0];s.edits['8.000']={cmp:'Linalool',auto:true,rki:'1111',rkiAuto:false,rkiSrc:'Manual reference'};
   const oldSpectra=nistSpectra,oldFetch=fetch;
   nistSpectra=async()=>[{key:'8.000',name:'P1 RT 8.000',peaks:[[93,999]]}];let mf=900;
   window.fetch=async()=>({ok:true,json:async()=>({ok:true,result:`Unknown: P1 RT 8.000  Compound in Library Factor\nHit 1 : <<Linalool>>;<<C10H18O>>; MF: ${mf}; RMF: 920; Prob: 90; CAS: 78-70-6; Mw: 154; Lib: <<mainlib>>; Id: 1; RI: 1096`})});
   try{await nistRun(s);const high={...s.edits['8.000']};mf=650;await nistRun(s);return {high,low:s.edits['8.000']};}
   finally{nistSpectra=oldSpectra;window.fetch=oldFetch;}
  });
  check('NIST high-MF re-search preserves manual rKI/source',r.high.rki==='1111'&&!r.high.rkiAuto&&r.high.rkiSrc==='Manual reference');
  check('NIST low-MF clearing preserves manual rKI/source',r.low.rki==='1111'&&r.low.rkiSrc==='Manual reference'&&!r.low.cmp);
  r=await frame.evaluate(()=>{const old=Storage.prototype.setItem;Storage.prototype.setItem=()=>{throw new DOMException('test quota','QuotaExceededError');};try{const ok=save();toast('Another message');return {ok,warning:document.getElementById('storageWarning')?.textContent};}finally{Storage.prototype.setItem=old;}});
  check('quota failure is visible and cannot be hidden by success toast',r.ok===false&&r.warning.includes('儲存失敗'));
  check('successful save clears warning',await frame.evaluate(()=>save()&&!document.getElementById('storageWarning')));
  r=await frame.evaluate(()=>{const s={...samples[0],alkSetId:'deleted'};delete s.alkSnapshot;return {ki:calcKI(8,setOf(s)),name:setOf(s).name};});
  check('missing calibration does not silently use first set',r.ki===null&&r.name.includes('不存在'));
  check('no browser runtime exceptions',errors.length===0);
 }finally{if(browser)await browser.close();await new Promise(r=>server.close(r));}
}
async function transactionTests(){
 const documents=new Map(), notices=[];let attempts=0,failCommit=false;
 const wrap=list=>({value:JSON.stringify({list})});
 const put=(id,list)=>documents.set(id,{rev:(documents.get(id)?.rev||0)+1,data:wrap(list)});
 const list=id=>JSON.parse(documents.get(id).data.value).list;
 const db={collection:()=>({doc:id=>({id})}),runTransaction:async(fn)=>{
  for(let i=0;i<10;i++){
   attempts++;const reads=new Map(),writes=new Map();
   const tx={get:async(ref)=>{const d=documents.get(ref.id);reads.set(ref.id,d?.rev||0);const data=d?clone(d.data):null;return {exists:!!d,data:()=>data};},set:(ref,data)=>writes.set(ref.id,clone(data))};
   const out=await fn(tx);await new Promise(r=>setTimeout(r,5));
   if([...reads].some(([id,rev])=>(documents.get(id)?.rev||0)!==rev))continue;
   if(failCommit)throw new Error('simulated commit failure');
   for(const [id,data] of writes)documents.set(id,{rev:(documents.get(id)?.rev||0)+1,data});
   return out;
  }throw new Error('retry limit');
 }};
 const context={db,FS_COLLECTION:'lab-data',TextEncoder,console:{error:()=>{}},currentUser:{uid:'member',name:'Member',role:'member'},isAdmin:()=>context.currentUser?.role==='admin',document:{getElementById:()=>({contentWindow:{postMessage:m=>notices.push(m)}})},window:{addEventListener:()=>{}}};
 vm.createContext(context);
 const start=index.indexOf("const GC_KI_KEY ="),end=index.indexOf('// 主题切换时通知 iframe',start);
 vm.runInContext(index.slice(start,end),context);
 const run=(op,payload)=>context.handleGcRequest({op,payload});
 const KI='gc-ki-database-data',PD='gc-ki-pending-data',ALK='gc-alkane-sets-data';
 put(KI,[['Existing',1000]]);put(PD,[]);put(ALK,[]);
 await Promise.all([run('pending.add',{name:'A',ki:1200}),run('pending.add',{name:'B',ki:1300})]);
 check('concurrent proposals both persist after retry',list(PD).length===2&&attempts>=3);
 check('transaction retries do not duplicate success notices',notices.filter(x=>x.gcNotice?.includes('已送出')).length===2);
 await run('ki.add',{name:'Unauthorized',ki:1400});check('member cannot directly edit KI',list(KI).length===1);
 context.currentUser={uid:'admin',name:'Admin',role:'admin'};
 const id=list(PD)[0].id;failCommit=true;await run('pending.approve',{id});failCommit=false;
 check('approval failure changes neither document',list(KI).length===1&&list(PD)[0].status==='pending');
 await run('pending.approve',{id});check('approval atomically updates KI and proposal',list(KI).length===2&&list(PD)[0].status==='approved');
 await Promise.all([run('ki.add',{name:'C',ki:1400}),run('ki.add',{name:'D',ki:1500})]);
 check('concurrent KI additions both persist',list(KI).some(x=>x[0]==='C')&&list(KI).some(x=>x[0]==='D'));
 const a={id:'cal',name:'Cal',rows:[[8,6],[10,12]],created_by_uid:'member',created_by:'Member'};put(ALK,[a]);
 context.currentUser={uid:'other',name:'Other',role:'member'};await run('alk.save',{set:{...a,name:'Forbidden'}});
 check('other member cannot edit RT set',list(ALK)[0].name==='Cal');
 context.currentUser={uid:'member',name:'Member',role:'member'};
 await run('alk.save',{set:{...a,name:'Updated'},baseSet:a});check('owner can save RT set',list(ALK)[0].name==='Updated');
 await run('alk.save',{set:{...a,name:'Stale overwrite'},baseSet:a});
 check('stale RT draft cannot overwrite newer cloud version',list(ALK)[0].name==='Updated'&&notices.at(-1).gcNotice.includes('草稿已保留'));
  await run('alk.save',{set:{...a,id:'removed'},baseSet:{...a,id:'removed'},existing:true});
  check('deleted shared calibration is not recreated by stale draft',!list(ALK).some(x=>x.id==='removed'));
 await run('alk.save',{set:{id:'invalid',name:'Invalid',rows:[[8,6],[9,6]]}});check('invalid RT rows rejected server-side bridge',list(ALK).length===1);
 context.currentUser={uid:'admin',name:'Admin',role:'admin'};
 await run('ki.seed',{list:[['Stale seed',1]]});check('seed checks server document rather than stale local cache',!list(KI).some(x=>x[0]==='Stale seed'));
}
(async()=>{await browserTests();await transactionTests();console.log(`ALL ${checks} CHECKS PASSED`);})().catch(e=>{console.error(e);process.exitCode=1;});
