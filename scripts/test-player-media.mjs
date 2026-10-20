import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { mkdir, readFile, readdir, stat, writeFile, rm } from 'node:fs/promises';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../',import.meta.url));
const media = join(root,'.local','media-fixtures');
const names = new Set(await readdir(media));
assert.ok(names.has('video.mp4') && names.has('main.m3u8'),'Generate synthetic fixtures with scripts/create-player-fixtures.ps1 first');
const header = randomBytes(18).toString('hex');
const counts = { mp4: 0, hls: 0, segments: 0, denied: 0, captures: 0 };
const server = createServer(async (req,res) => {
  try {
    const path = new URL(req.url,'http://localhost').pathname;
    if(req.method === 'POST' && ['/capture/native.png','/capture/page.png'].includes(path)) {
      const blocks=[];let size=0;
      for await(const chunk of req) { size+=chunk.length; if(size>10*1024*1024) { res.writeHead(413).end(); return; } blocks.push(chunk); }
      const image=Buffer.concat(blocks);assert.ok(image.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])));
      const directory=join(root,'.local','screenshots');await mkdir(directory,{recursive:true});
      await writeFile(join(directory,path.endsWith('/native.png') ? 'player-native.png' : 'player-page.png'),image);
      counts.captures++;res.writeHead(204).end();return;
    }
    if(req.headers['x-duoscene-test-media']!==header) { counts.denied++;res.writeHead(403).end();return; }
    const name=path==='/video.mp4' ? 'video.mp4' : path==='/hls/stream' ? 'main.m3u8' : /^\/hls\/seg\d{3}\.ts$/.test(path) ? path.slice('/hls/'.length) : null;
    if(!name || !names.has(name)) { res.writeHead(404).end();return; }
    if(name==='video.mp4') counts.mp4++; else if(name==='main.m3u8') counts.hls++; else counts.segments++;
    const file=join(media,name);const {size}=await stat(file);
    let start=0,end=size-1,status=200;
    if(req.headers.range) {
      const range=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range);
      if(!range) { res.writeHead(416,{'Content-Range':`bytes */${size}`}).end();return; }
      start=Number(range[1]);end=range[2] ? Math.min(Number(range[2]),end) : end;
      if(start>end) { res.writeHead(416,{'Content-Range':`bytes */${size}`}).end();return; }
      status=206;res.setHeader('Content-Range',`bytes ${start}-${end}/${size}`);
    }
    res.writeHead(status,{'Content-Type':name.endsWith('.mp4') ? 'video/mp4' : name.endsWith('.m3u8') ? 'application/vnd.apple.mpegurl' : 'video/mp2t','Content-Length':end-start+1,'Accept-Ranges':'bytes','Cache-Control':'no-store'});
    if(req.method==='HEAD') res.end(); else createReadStream(file,{start,end}).pipe(res);
  } catch { if(!res.headersSent) res.writeHead(500);res.end(); }
});
await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
const port=server.address().port;
const device=process.env.FLUTTER_DEVICE || 'emulator-5554';
const adb=join(process.env.ANDROID_SDK_ROOT || process.env.ANDROID_HOME || 'D:/Android/Sdk','platform-tools',process.platform==='win32' ? 'adb.exe' : 'adb');
const execute=promisify(execFile);
let reversed=false;
const fixture=join(root,'.local','player-test-defines.json');
try {
  // USB、官方模拟器和雷电均通过设备回环访问夹具，不暴露宿主机局域网端口。
  await execute(adb,['-s',device,'reverse',`tcp:${port}`,`tcp:${port}`],{windowsHide:true});
  reversed=true;
  await writeFile(fixture,JSON.stringify({MEDIA_FIXTURE_BASE:`http://127.0.0.1:${port}`,TEST_MEDIA_HEADER:header,TEST_PLAYER_RENDERER:process.env.PLAYER_TEST_RENDERER || ''})+'\n','utf8');
  const flutter=process.env.FLUTTER_BIN || 'flutter.bat';
  const args=['test','integration_test/player_media_test.dart',`--dart-define-from-file=${fixture}`,'-d',device];
  const command=process.platform==='win32' ? process.env.ComSpec || 'cmd.exe' : flutter;
  const commandArgs=process.platform==='win32' ? ['/d','/s','/c',`"${[flutter,...args].map(arg=>`"${arg}"`).join(' ')}"`] : args;
  const child=spawn(command,commandArgs,{cwd:join(root,'apps','mobile'),stdio:'inherit',windowsVerbatimArguments:process.platform==='win32'});
  const exit=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',resolve);});
  assert.equal(exit,0,'Native media integration failed');
  assert.ok(counts.mp4>0 && counts.hls>0 && counts.segments>0 && counts.captures===2);
  assert.equal(counts.denied,0,'Media headers were not forwarded');
  console.log('PASS real MP4/HLS requests, range, headers, first frame, controls:',JSON.stringify(counts));
} finally {
  console.log('Fixture requests:',JSON.stringify(counts));
  await rm(fixture,{force:true});
  if(reversed) await execute(adb,['-s',device,'reverse','--remove',`tcp:${port}`],{windowsHide:true}).catch(()=>{});
  server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
}
