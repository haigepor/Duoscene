import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createReadStream} from 'node:fs';
import {mkdir,writeFile,stat,unlink} from 'node:fs/promises';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
const output=process.env.TABLET_LAYOUT_OUTPUT||join(root,'.local','tablet-layout-native');
await mkdir(output,{recursive:true});
const fixture=join(root,'.local','media-fixtures','video.mp4');
const {size}=await stat(fixture);
const device=process.env.FLUTTER_DEVICE;
assert.ok(device,'Set FLUTTER_DEVICE to the connected tablet serial');
const adb=process.env.ADB_BIN||join(process.env.ANDROID_SDK_ROOT||process.env.ANDROID_HOME||'D:/Android/Sdk','platform-tools','adb.exe');
const execute=promisify(execFile);
const shell=async args=>(await execute(adb,['-s',device,'shell',...args],{windowsHide:true,maxBuffer:8*1024*1024})).stdout.trim();
const original=(await shell(['cmd','window','user-rotation'])).split(/\s+/);
const originalStayOn=await shell(['settings','get','global','stay_on_while_plugged_in']);
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const header=randomBytes(18).toString('hex');
let requests=0,result;
const server=createServer(async(req,res)=>{
  try{
    const path=new URL(req.url,'http://localhost').pathname;
    if(req.method==='POST'&&path==='/result'){
      const parts=[];let length=0;
      for await(const part of req){length+=part.length;assert.ok(length<65536);parts.push(part);}
      result=JSON.parse(Buffer.concat(parts).toString('utf8'));
      await writeFile(join(output,'native-video-result.json'),JSON.stringify(result,null,2)+'\n','utf8');
      res.writeHead(204).end();return;
    }
    if(req.method==='POST'&&path.startsWith('/phase/')){
      const phase=path.slice('/phase/'.length);
      console.log('TABLET_PHASE:'+phase);
      if(['portrait','landscape'].includes(phase)){
        await shell(['cmd','window','user-rotation','lock',phase==='portrait'?'0':'1']);
        await pause(1000);
      }else if(phase==='inspect-keyboard'){
        const state=await shell(['dumpsys','input_method']);
        await writeFile(join(output,'native-ime-state.log'),state.split('\n').filter(line=>/mInputShown=|mImeWindowVis=|mCurId=/.test(line)).join('\n')+'\n','utf8');
      }else if(phase==='foreground'){
        await shell(['am','start','-n','com.example.duoscene/.MainActivity']);
        await pause(600);
      }else if(['capture-landscape','capture-portrait','capture-keyboard'].includes(phase)){
        const name='native-video-'+phase.slice('capture-'.length);
        await shell(['screencap','-p','/data/local/tmp/duoscene-tablet-video.png']);
        await execute(adb,['-s',device,'pull','/data/local/tmp/duoscene-tablet-video.png',join(output,name+'.png')],{windowsHide:true});
      }else throw Error('Unsupported native test phase');
      res.writeHead(204).end();return;
    }
    if(path!=='/video.mp4'||req.headers['x-duoscene-test-media']!==header){res.writeHead(403).end();return;}
    requests++;
    let start=0,end=size-1,status=200;
    if(req.headers.range){
      const range=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range);
      if(!range){res.writeHead(416).end();return;}
      start=Number(range[1]);end=range[2]?Math.min(end,Number(range[2])):end;
      if(start>end){res.writeHead(416).end();return;}
      status=206;res.setHeader('Content-Range',`bytes ${start}-${end}/${size}`);
    }
    res.writeHead(status,{'Content-Type':'video/mp4','Content-Length':end-start+1,'Accept-Ranges':'bytes','Cache-Control':'no-store'});
    if(req.method==='HEAD')res.end();else createReadStream(fixture,{start,end}).pipe(res);
  }catch(error){if(!res.headersSent)res.writeHead(500);res.end();process.stderr.write(error.message+'\n');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const port=server.address().port,defines=join(output,'native-video-defines.json');
let reversed=false;
try{
  // 构建/安装期间也要保持测试屏幕可绘制，避免息屏让 LiveTest 的帧等待挂起。
  await shell(['svc','power','stayon','true']);
  await shell(['input','keyevent','KEYCODE_WAKEUP']);
  await shell(['wm','dismiss-keyguard']);
  await pause(500);
  const keyguard=(await shell(['dumpsys','window','policy'])).split('KeyguardStateMonitor')[1]?.split('Looper state:')[0]||'';
  assert.ok(!/mIsShowing=true/.test(keyguard),'Unlock the tablet manually before running native layout tests');
  await execute(adb,['-s',device,'reverse',`tcp:${port}`,`tcp:${port}`],{windowsHide:true});reversed=true;
  await writeFile(defines,JSON.stringify({MEDIA_FIXTURE_BASE:`http://127.0.0.1:${port}`,TEST_MEDIA_HEADER:header})+'\n','utf8');
  const flutter=process.env.FLUTTER_BIN||'flutter.bat';
  const args=['test','integration_test/tablet_player_layout_test.dart','--no-pub',`--dart-define-from-file=${defines}`,'-d',device,'--reporter','expanded'];
  const windows=process.platform==='win32';
  const child=spawn(windows?process.env.ComSpec||'cmd.exe':flutter,windows?['/d','/s','/c',`"${[flutter,...args].map(a=>`"${a}"`).join(' ')}"`]:args,{cwd:join(root,'apps','mobile'),stdio:'inherit',windowsVerbatimArguments:windows});
  const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',resolve);});
  assert.equal(code,0,'Native tablet integration failed');assert.ok(requests>0&&result?.controllerPreserved);
  console.log('TABLET_NATIVE_RESULT:'+JSON.stringify({...result,fixtureRequests:requests}));
}finally{
  await shell(['cmd','window','user-rotation',...original]).catch(()=>{});
  await shell(originalStayOn==='null'
    ? ['settings','delete','global','stay_on_while_plugged_in']
    : ['settings','put','global','stay_on_while_plugged_in',originalStayOn]).catch(()=>{});
  if(reversed)await execute(adb,['-s',device,'reverse','--remove',`tcp:${port}`],{windowsHide:true}).catch(()=>{});
  await unlink(defines).catch(()=>{});
  server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
}
