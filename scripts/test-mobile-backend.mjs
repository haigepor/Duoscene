import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { buildApp } from '../apps/api/src/app.ts';
import { loadConfig } from '../apps/api/src/config/env.ts';
import { Database } from '../apps/api/src/shared/database.ts';
import { migrate } from '../apps/api/src/commands/migrate.ts';
import { createPrivateUser } from '../apps/api/src/commands/accounts.ts';

// 只在隔离测试库创建短期账户；不暴露数据库/测试账户凭据到控制台。
const root = fileURLToPath(new URL('../', import.meta.url));
const base = loadConfig();
const database = process.env.DUOSCENE_TEST_DATABASE;
assert.ok(database && /^duoscene_test_[a-z0-9_]{1,40}$/.test(database), 'An isolated duoscene_test_* database is required');
assert.equal(base.database.mode, 'mysql');
const config = { ...base, environment: 'test', logLevel: 'silent', database: { ...base.database, database } };
const db = new Database(config.database);
const app = buildApp({ config, logger: false });
const ids = [];
const suffix = randomUUID().slice(0, 8);
const directory = join(root, '.local', 'mobile-test', suffix);
let child;
let reversedPort;
const native = process.argv.includes('--native');
const device = process.env.FLUTTER_DEVICE || 'emulator-5554';
const adb = join(process.env.ANDROID_SDK_ROOT || 'D:/Android/Sdk', 'platform-tools/adb.exe');
const execute = promisify(execFile);
try {
  await migrate(db);
  const password = randomBytes(24).toString('base64url');
  const owner = await createPrivateUser(db, `mobile_owner_${suffix}`, '测试房主', password); ids.push(owner.id);
  const guest = await createPrivateUser(db, `mobile_guest_${suffix}`, '测试成员', password); ids.push(guest.id);
  await app.listen({ host: '127.0.0.1', port: 0 });
  const address = app.server.address();
  assert.ok(address && typeof address !== 'string');
  // 雷电与官方 AVD 的宿主别名不同；统一走当前设备的 ADB 回环映射。
  if (native) {
    await execute(adb, ['-s', device, 'reverse', `tcp:${address.port}`, `tcp:${address.port}`], { windowsHide: true });
    reversedPort = address.port;
  }
  const fixture = {
    API_BASE_URL: `http://127.0.0.1:${address.port}`,
    TEST_OWNER: owner.username, TEST_GUEST: guest.username, TEST_PASSWORD: password,
  };
  await mkdir(directory, { recursive: true });
  const path = join(directory, 'fixture.json');
  await writeFile(path, `${JSON.stringify(fixture)}\n`, { encoding: 'utf8', flag: 'wx' });
  const flutter = process.env.FLUTTER_BIN || 'flutter.bat';
  const args = native
    ? ['test', 'integration_test/rooms_flow_test.dart', `--dart-define-from-file=${path}`, '-d', device]
    : ['test', 'test/backend_integration_test.dart'];
  // Windows .bat 必须通过命令解释器；参数均来自本脚本的固定路径，不含凭据。
  const command = process.platform === 'win32' ? process.env.ComSpec || 'cmd.exe' : flutter;
  const commandArgs = process.platform === 'win32'
    ? ['/d', '/s', '/c', `"${[flutter, ...args].map((arg) => `"${arg}"`).join(' ')}"`]
    : args;
  child = spawn(command, commandArgs, {
    cwd: join(root, 'apps', 'mobile'), stdio: 'inherit',
    windowsVerbatimArguments: process.platform === 'win32',
    env: { ...process.env, DUOSCENE_MOBILE_FIXTURE: path },
  });
  const code = await new Promise((resolve, reject) => {
    child.once('error', reject); child.once('exit', (value) => resolve(value ?? 1));
  });
  assert.equal(code, 0, 'Flutter backend integration failed');
  console.log(`PASS: Flutter ${native ? 'Android UI' : 'HTTP client'} against real Fastify/MySQL`);
} finally {
  if (child && child.exitCode === null) child.kill();
  if (reversedPort) await execute(adb, ['-s', device, 'reverse', '--remove', `tcp:${reversedPort}`], { windowsHide: true }).catch(() => {});
  await app.close();
  try {
    for (const id of ids) await db.run('DELETE FROM rooms WHERE owner_user_id = ?', [id]);
    for (const id of ids) await db.run('DELETE FROM users WHERE id = ?', [id]);
    console.log('Temporary mobile test accounts/rooms removed');
  } finally {
    await db.close();
    // 仅删除本次随机子目录中的已知夹具文件，不递归操作未知目录。
    await rm(join(directory, 'fixture.json'), { force: true });
  }
}
