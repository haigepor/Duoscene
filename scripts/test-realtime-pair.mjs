import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { mkdir, readFile, writeFile, rm, stat, copyFile } from 'node:fs/promises';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { buildApp } from '../apps/api/src/app.ts';
import { loadConfig } from '../apps/api/src/config/env.ts';
import { Database } from '../apps/api/src/shared/database.ts';
import { migrate } from '../apps/api/src/commands/migrate.ts';

const root = fileURLToPath(new URL('../',import.meta.url));
const execute = promisify(execFile);
const adb = join(process.env.ANDROID_SDK_ROOT || 'D:/Android/Sdk','platform-tools/adb.exe');
const devices = [process.env.PAIR_OWNER_DEVICE || '127.0.0.1:5557', process.env.PAIR_GUEST_DEVICE || 'emulator-5558'];
assert.notEqual(devices[0],devices[1]);
const base = loadConfig(), database = process.env.DUOSCENE_TEST_DATABASE;
assert.equal(base.database.mode,'mysql'); assert.ok(/^duoscene_test_[a-z0-9_]{1,40}$/.test(database || ''));
assert.ok(base.voice,'Load .local/voice.env and start local coturn before testing');
const config = {...base,environment:'test',logLevel:'silent',database:{...base.database,database}};
const db = new Database(config.database), api = buildApp({config,logger:false});
const suffix = randomUUID().slice(0,8), password = randomBytes(24).toString('base64url');
const ids = [], children = [], reversed = [], phases = {owner:[],guest:[]}, reports = [], counts={mp4:0,hls:0,segments:0};
const directory=join(root,'.local','realtime-pair',suffix), screenshotDir=join(root,'.local/screenshots/realtime');
await mkdir(directory,{recursive:true}); await mkdir(screenshotDir,{recursive:true});
let invite = {}, ports = [];
const fixture = createServer(async (req,res) => {
  try {
    const path=new URL(req.url,'http://localhost').pathname;
    if(req.method==='POST') {
      const blocks=[];let size=0;
      for await(const chunk of req){size+=chunk.length;if(size>10*1024*1024){res.writeHead(413).end();return;}blocks.push(chunk);}
      const body=Buffer.concat(blocks);
      if(path==='/invite')invite=JSON.parse(body.toString('utf8'));
      else if(/^\/report\/(owner|guest)$/.test(path)) {
        const role=path.split('/').at(-1), value=JSON.parse(body.toString('utf8'));
        phases[role].push(value.phase);reports.push({role,...value}); console.log(`Android ${role}: ${value.phase}`);
      } else if(/^\/capture\/(owner|guest)\.png$/.test(path)) {
        assert.ok(body.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])));
        await writeFile(join(screenshotDir,path.split('/').at(-1)),body);
      } else {res.writeHead(404).end();return;}
      res.writeHead(204).end();return;
    }
    if(path==='/invite'||path==='/phases'){res.writeHead(200,{'content-type':'application/json','cache-control':'no-store'}).end(JSON.stringify(path==='/invite'?invite:phases));return;}
    const name=path.replace('/media/','');
    if(!/^video\.mp4$|^main\.m3u8$|^seg\d{3}\.ts$/.test(name)){res.writeHead(404).end();return;}
    const file=join(root,'.local/media-fixtures',name), {size}=await stat(file);
    name.endsWith('.mp4')?counts.mp4++:name.endsWith('.m3u8')?counts.hls++:counts.segments++;
    let start=0,end=size-1,status=200;
    if(req.headers.range){const m=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range);if(!m){res.writeHead(416).end();return;}start=Number(m[1]);end=m[2]?Math.min(Number(m[2]),end):end;status=206;res.setHeader('Content-Range',`bytes ${start}-${end}/${size}`);}
    if(start>end){res.writeHead(416).end();return;}
    res.writeHead(status,{'content-type':name.endsWith('.mp4')?'video/mp4':name.endsWith('.m3u8')?'application/vnd.apple.mpegurl':'video/mp2t','content-length':end-start+1,'accept-ranges':'bytes','cache-control':'no-store'});
    if(req.method==='HEAD')res.end();else createReadStream(file,{start,end}).pipe(res);
  } catch {if(!res.headersSent)res.writeHead(500);res.end();}
});
const flutter=process.env.FLUTTER_BIN || 'flutter.bat';
async function runFlutter(args, logName) {
  const command=process.env.ComSpec || 'cmd.exe';
  const child=spawn(command,['/d','/s','/c',`"${[flutter,...args].map(arg=>`"${arg}"`).join(' ')}"`],{cwd:join(root,'apps/mobile'),env:{...process.env,FLUTTER_TEST_OUTPUTS_DIR:join(directory,logName)},windowsHide:true,windowsVerbatimArguments:true});
  children.push(child);
  const chunks=[];
  child.stdout.on('data',b=>{chunks.push(b);if(args[0]==='drive')process.stdout.write(b);});
  child.stderr.on('data',b=>{chunks.push(b);if(args[0]==='drive')process.stdout.write(b);});
  const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',resolve);});
  await writeFile(join(directory,`${logName}.log`),Buffer.concat(chunks));
  if(code!==0){if(args[0]!=='drive')process.stdout.write(Buffer.concat(chunks));throw Error(`${logName} failed (${code})`);}
}
try {
  await migrate(db);
  // 两端通过真实注册 UI 创建账户，清理时仅按本次随机后缀查询。
  const owner={username:`pair_owner_${suffix}`};
  const guest={username:`pair_guest_${suffix}`};
  await api.listen({host:'127.0.0.1',port:0}); await new Promise(resolve=>fixture.listen(0,'127.0.0.1',resolve));
  const apiPort=api.server.address().port,fixturePort=fixture.address().port;ports=[apiPort,fixturePort,3478];
  const defines=join(directory,'defines.json');
  await writeFile(defines,JSON.stringify({API_BASE_URL:`http://127.0.0.1:${apiPort}`,PAIR_FIXTURE:`http://127.0.0.1:${fixturePort}`,TEST_OWNER:owner.username,TEST_GUEST:guest.username,TEST_PASSWORD:password}),'utf8');
  const binaries=[];
  for(const role of ['owner','guest']) {
    console.log(`Building isolated ${role} Android test binary`);
    await runFlutter(['build','apk','--debug','--no-pub','--target-platform','android-x64','-t','integration_test/realtime_pair_test.dart',`--dart-define-from-file=${defines}`,`--dart-define=TEST_ROLE=${role}`],`build-${role}`);
    const binary=join(directory,`${role}-test.apk`);await copyFile(join(root,'apps/mobile/build/app/outputs/flutter-apk/app-debug.apk'),binary);binaries.push(binary);
  }
  for(let i=0;i<devices.length;i++){
    await execute(adb,['-s',devices[i],'install','-r',binaries[i]],{windowsHide:true,maxBuffer:1024*1024});
    await execute(adb,['-s',devices[i],'shell','pm','grant','com.example.duoscene','android.permission.RECORD_AUDIO'],{windowsHide:true});
    for(const port of ports){await execute(adb,['-s',devices[i],'reverse',`tcp:${port}`,`tcp:${port}`],{windowsHide:true});reversed.push([devices[i],port]);}
  }
  const drives=devices.map((device,i)=>runFlutter(['drive','--no-pub','--no-dds','--target','integration_test/realtime_pair_test.dart','--driver','test_driver/realtime_pair_driver.dart',`--use-application-binary=${binaries[i]}`,'-d',device],`drive-${i===0?'owner':'guest'}`));
  const results=await Promise.allSettled(drives);for(const r of results)if(r.status==='rejected')throw r.reason;
  assert.ok(phases.owner.includes('complete') && phases.guest.includes('complete'));
  assert.ok(counts.mp4>=2 && counts.hls>=2 && counts.segments>=2);
  assert.equal(reports.filter(r=>r.phase==='voice-stats' && r.bytesReceived>0 && r.bytesSent>0).length,2);
  await writeFile(join(root,'.local/realtime-pair-result.json'),JSON.stringify({status:'PASS',devices,counts,reports,directory},null,2)+'\n','utf8');
  console.log('PASS two Android users: login/invite, real MP4/HLS sync, chat, WebRTC RTP, mute, reconnect and cleanup');
} finally {
  for(const child of children)if(child.exitCode===null)await execute('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true}).catch(()=>{});
  for(const [device,port]of reversed)await execute(adb,['-s',device,'reverse','--remove',`tcp:${port}`],{windowsHide:true}).catch(()=>{});
  await api.close();fixture.closeAllConnections();await new Promise(resolve=>fixture.close(resolve));
  try {
    const created=await db.rows('SELECT id FROM users WHERE username IN (?,?)',[`pair_owner_${suffix}`,`pair_guest_${suffix}`]);
    ids.push(...created.map(row=>row.id));
    for(const id of ids)await db.run('DELETE FROM rooms WHERE owner_user_id=?',[id]);
    for(const id of ids)await db.run('DELETE FROM users WHERE id=?',[id]);
  } finally {await db.close();await rm(join(directory,'defines.json'),{force:true});}
}
