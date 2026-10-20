import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const directory = join(root, '.local/screenshots/ui');
await mkdir(directory, { recursive: true });
const captures = new Set();
const server = createServer(async (req, res) => {
  const match = /^\/capture\/(\d{2}|state-[a-z0-9-]+)\.png$/.exec(req.url);
  if (req.method !== 'POST' || !match) { res.writeHead(404).end(); return; }
  const blocks = []; let size = 0;
  for await (const block of req) { size += block.length; if (size > 12 * 1024 * 1024) { res.writeHead(413).end(); return; } blocks.push(block); }
  const data = Buffer.concat(blocks);
  if (!data.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) { res.writeHead(400).end(); return; }
  await writeFile(join(directory, `${match[1]}.png`), data);
  captures.add(match[1]); res.writeHead(204).end();
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;
const device = process.env.FLUTTER_DEVICE || '127.0.0.1:5557';
const adb = join(process.env.ANDROID_SDK_ROOT || 'D:/Android/Sdk', 'platform-tools/adb.exe');
const execute = promisify(execFile);
const fixture = join(root, '.local/ui-native-defines.json');
let reversed = false;
try {
  await execute(adb, ['-s', device, 'reverse', `tcp:${port}`, `tcp:${port}`], { windowsHide: true }); reversed = true;
  await writeFile(fixture, JSON.stringify({ UI_CAPTURE_BASE: `http://127.0.0.1:${port}` }), 'utf8');
  const flutter = process.env.FLUTTER_BIN || 'flutter.bat';
  const args = ['test', 'integration_test/ui_gallery_test.dart', `--dart-define-from-file=${fixture}`, '-d', device];
  const command = process.env.ComSpec || 'cmd.exe';
  const child = spawn(command, ['/d', '/s', '/c', `"${[flutter, ...args].map(arg => `"${arg}"`).join(' ')}"`], { cwd: join(root, 'apps/mobile'), stdio: 'inherit', windowsVerbatimArguments: true, windowsHide: true });
  const exit = await new Promise((resolve, reject) => { child.once('error', reject); child.once('exit', resolve); });
  assert.equal(exit, 0, 'Android UI verification failed');
  assert.equal(captures.size, 82, '54 themed pages, 24 preview states and 4 navigation/scroll/player checks must be captured');
  await writeFile(join(root, '.local/ui-native-result.json'), JSON.stringify({
    status: 'PASS', testedAt: new Date().toISOString(), device,
    captures: [...captures], directory,
  }, null, 2) + '\n', 'utf8');
  console.log('PASS native Flutter UI pages:', [...captures].join(', '));
} finally {
  await rm(fixture, { force: true });
  if (reversed) await execute(adb, ['-s', device, 'reverse', '--remove', `tcp:${port}`], { windowsHide: true }).catch(() => {});
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
}
