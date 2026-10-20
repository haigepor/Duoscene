import assert from 'node:assert/strict';
import { readdir, readFile, access } from 'node:fs/promises';
import { extname, join, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const ignored = new Set(['.git', '.local', '.gradle', '.idea', '.playwright-mcp', 'Pods', '.symlinks', 'node_modules', '.dart_tool', 'dist', 'build', 'coverage', 'secrets', 'backups']);
const extensions = new Set(['.md', '.json', '.yaml', '.yml', '.ts', '.mjs', '.dart', '.sql']);
const plainFiles = new Set(['.gitignore', '.gitattributes', '.editorconfig', '.env.example', '.node-version', '.npmrc']);
const decoder = new TextDecoder('utf-8', { fatal: true });
const files = [];

async function checkReferences(value, path, document) {
  if (!value || typeof value !== 'object') return;
  if (typeof value.$ref === 'string' && (value.$ref.startsWith('./') || value.$ref.startsWith('#'))) {
    const [filename, fragment = ''] = value.$ref.split('#');
    const target = filename ? fileURLToPath(new URL(filename, pathToFileURL(path))) : path;
    let node = filename ? JSON.parse(await readFile(target, 'utf8')) : document;
    for (const segment of fragment.split('/').filter(Boolean)) {
      node = node?.[segment.replaceAll('~1', '/').replaceAll('~0', '~')];
    }
    assert.notEqual(node, undefined, `${relative(root, path)}: dangling $ref ${value.$ref}`);
  }
  for (const item of Object.values(value)) await checkReferences(item, path, document);
}

async function walk(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (ignored.has(entry.name)) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) await walk(path);
    else if (entry.isFile() && (extensions.has(extname(path)) || plainFiles.has(entry.name))) files.push(path);
  }
}

await walk(root);
for (const path of files) {
  const bytes = await readFile(path);
  const name = relative(root, path);
  const vendored = name.replaceAll('\\', '/').startsWith('apps/mobile/third_party/media-kit/');
  assert.ok(!(bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf), `${name}: unexpected BOM`);
  const text = decoder.decode(bytes);
  // fork 的 UTF-8 解码器用该字面量检测损坏输入，保留经过来源核对的两处比较。
  const decoderLiteral = name.replaceAll('\\', '/') === 'apps/mobile/third_party/media-kit/media_kit/lib/ffi/src/utf8.dart';
  if (!decoderLiteral) assert.ok(!text.includes('\uFFFD'), `${name}: replacement character`);
  else assert.equal(text.split('\uFFFD').length - 1, 2, `${name}: unexpected replacement literal count`);
  // 固定第三方快照保留来源的换行字节；仍执行 UTF-8、JSON 和引用检查。
  if (!vendored) {
    assert.ok(text.endsWith('\n'), `${name}: missing final newline`);
    assert.ok(!text.includes('\r'), `${name}: expected LF newlines`);
  }
  if (path.endsWith('.json')) {
    const document = JSON.parse(text);
    await checkReferences(document, path, document);
  }
  if (path.endsWith('.ts')) {
    for (const match of text.matchAll(/from\s+['"](\.[^'"]+)['"]/g)) {
      await access(fileURLToPath(new URL(match[1], pathToFileURL(path))));
    }
  }
}
for (const required of [
  'apps/mobile/lib/main.dart', 'apps/mobile/pubspec.yaml', 'apps/api/src/app.ts',
  'apps/api/src/server.ts', 'apps/api/migrations/README.md',
  'packages/contracts/openapi/openapi.json', 'packages/contracts/websocket/README.md',
  'infra/compose/compose.dev.yaml', 'infra/caddy/README.md', 'infra/coturn/README.md',
  'docs/architecture.md', 'docs/implementation-plan.md', '.env.example',
]) await access(join(root, required));

const manifest = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
assert.equal(manifest.name, 'duoscene');
assert.equal(manifest.private, true);
assert.deepEqual(manifest.workspaces, ['apps/api']);
const api = JSON.parse(await readFile(join(root, 'apps/api/package.json'), 'utf8'));
assert.equal(api.name, '@duoscene/api');
assert.equal(api.type, 'module');
console.log(`PASS: structure, JSON, relative TypeScript imports and UTF-8/LF (${files.length} text files)`);
