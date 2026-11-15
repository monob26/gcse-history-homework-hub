// Split assets and teacher rendering with fictional mocked client; no hosted requests.
const {chromium}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),http=require('node:http');
(async()=>{
 const root=path.resolve(__dirname,'../..');
 const server=http.createServer((req,res)=>{
  const file=path.join(root,new URL(req.url,'http://localhost').pathname.replace(/\/$/,'/index.html'));
  res.setHeader('Content-Type',file.endsWith('.css')?'text/css':file.endsWith('.js')?'application/javascript':'text/html');
  res.end(fs.readFileSync(file));
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const origin='http://127.0.0.1:'+server.address().port;
 const browser=await chromium.launch({executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE||'/usr/bin/chromium',headless:true});
 const results=[];
 try{for(const scenario of ['homework','no-homework','denied','unallocated','query-error','stale-signout']){
  const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',route=>new URL(route.request().url()).origin===origin?route.continue():route.abort());
  await page.addInitScript(({scenario})=>{
   const classes=scenario==='unallocated'?[]:[{id:'fictional-class',class_name:'Fictional A',year_group:10}];
   const pupils=[{pupil_code:'ZZZZZZZZZZZZ',register_number:2},{pupil_code:'AAAAAAAAAAAA',register_number:1}];
   const queries=[];window.r6Queries=queries;
   const query=(table)=>{
    const q={select(value){queries.push({table,select:value});return q},eq(){return q},order(){return q},then(resolve,reject){
     const data=table==='history_classes'?classes:table==='history_quizzes'?(scenario==='no-homework'?[]:[{id:'quiz',year_group:10,week_number:1,total_questions:25}]):pupils;
     const result={data,error:scenario==='query-error'&&table==='history_pupils'?{message:'Fictional query error'}:null};
     return new Promise(r=>setTimeout(()=>r(result),scenario==='stale-signout'&&table==='history_pupils'?200:0)).then(resolve,reject);
    }};return q;
   };
   window.supabase={createClient(url,key){window.r6Config={url,key};return {
    auth:{onAuthStateChange(){},getSession:async()=>({data:{session:{user:{email:'fictional@example.test'}}}}),signOut:async()=>({})},
    from:query,rpc:async name=>({data:name==='is_history_teacher'?scenario!=='denied':pupils.map(p=>({...p,attempts:1,highest_score:21,homework_status:'Passed'})),error:null})
   }}};
  },{scenario});
  await page.goto(origin+'/teacher/');
  if(scenario==='denied')await page.locator('#authMsg').filter({hasText:'not approved'}).waitFor();
  else{
   await page.locator('#dashboard').waitFor({state:'visible'});
   if(scenario==='stale-signout'){
    await page.locator('#signOut').click();await page.waitForTimeout(300);assert(await page.locator('#dashboard').isHidden());
    assert.equal(await page.locator('#results').innerText(),'Sign in to view results.');
   }else if(scenario==='unallocated')await page.locator('#results').getByText('No classes allocated for this year group.').waitFor();
   else if(scenario==='query-error')await page.locator('#results').getByText('Unable to load pupil codes or results: Fictional query error').waitFor();
   else{
    await page.waitForFunction(()=>document.querySelector('#results tr td')?.textContent==='1');
    assert.deepEqual(await page.locator('#results tr td:first-child').allTextContents(),['1','2']);
    assert.deepEqual(await page.locator('#results tr td:nth-child(2)').allTextContents(),['AAAAAAAAAAAA','ZZZZZZZZZZZZ']);
    if(scenario==='no-homework')assert.match(await page.locator('#results').innerText(),/No homework assigned/);
    else assert.match(await page.locator('#results').innerText(),/21\/25/);
    assert((await page.evaluate(()=>window.r6Queries)).some(q=>q.table==='history_pupils'&&q.select==='pupil_code,register_number'));
    await page.locator('#signOut').click();assert(await page.locator('#dashboard').isHidden());
   }
  }
  assert.equal(await page.evaluate(()=>window.r6Config.url),'https://inxsjdogxvqbvxydxmym.supabase.co');
  assert.deepEqual(errors,[]);results.push({scenario,status:'PASS'});await page.close();
 }}finally{await browser.close();await new Promise(r=>server.close(r))}
 console.log(JSON.stringify({scope:'R6 teacher split files, fictional mocked client; CDN blocked',results},null,2));
})().catch(e=>{console.error(e.message);process.exitCode=1});
