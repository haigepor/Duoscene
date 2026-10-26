// 真机性能基线采集。遵循 docs/playra-performance-study-20261022.zh.md 的测量边界：
// - 仅 Profile 构建结果可作为性能证据；Debug/JIT 帧耗时只用于回归对比，不宣称真实 FPS。
// - am start -W 只衡量 Activity 显示，不等于登录恢复/片库/首帧全部就绪。
// - FrameTiming 的 build/raster >16.667ms 是 60Hz 单阶段超预算参考，不等于实际丢帧率。
//
// 用法：
//   node scripts/perf-baseline.mjs                     # 采集已安装应用的基线
//   node scripts/perf-baseline.mjs --install output/android/duoscene-lan-arm64-profile-perf.apk
//   node scripts/perf-baseline.mjs --serial <device-id> --swipes 6
// 产物写入 .local/perf/baseline-<时间戳>/（gitignored），终端只打印摘要。

import { execFile } from 'node:child_process';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { promisify } from 'node:util';

const run = promisify(execFile);
const PACKAGE = 'com.example.duoscene';
const ACTIVITY = `${PACKAGE}/.MainActivity`;
const PERF_FILE = '/storage/emulated/0/Android/data/com.example.duoscene/files/duoscene-performance.json';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function arg(name, fallback) {
  const index = process.argv.indexOf(name);
  return index > 0 && process.argv[index + 1] !== undefined ? process.argv[index + 1] : fallback;
}
const serial = process.argv.includes('--serial') ? arg('--serial', '') : null;
const installApk = process.argv.includes('--install') ? arg('--install', '') : null;
const swipes = Number(arg('--swipes', '4'));

async function adb(...args) {
  const full = serial ? ['-s', serial, ...args] : args;
  try {
    const { stdout } = await run('adb', full, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
    return stdout;
  } catch (error) {
    throw new Error(`adb ${full.join(' ')} failed: ${error.message}\n${error.stderr ?? ''}`);
  }
}

function firstMatch(text, pattern) {
  const match = text.match(pattern);
  return match ? match[1] : null;
}

// 与 apps/mobile/lib/core/performance_capture.dart 的 frameStatistics 同口径。
function frameStatistics(samples) {
  if (samples.length === 0) return { count: 0 };
  const sorted = [...samples].sort((a, b) => a - b);
  const percentile = (fraction) => sorted[Math.ceil(sorted.length * fraction) - 1];
  return {
    count: sorted.length,
    p50Us: percentile(0.5),
    p95Us: percentile(0.95),
    p99Us: percentile(0.99),
    maxUs: sorted[sorted.length - 1],
    above16667Us: samples.filter((value) => value > 16667).length,
  };
}

async function main() {
  const listing = await adb('devices');
  const devices = listing
    .split('\n')
    .slice(1)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('*') && !line.endsWith('offline'));
  if (devices.length === 0) {
    console.error('NO_DEVICE: adb 未发现设备。请检查：1) USB 调试已开启且模式为传输文件；2) 数据线支持数据传输；3) 手机上已接受 RSA 指纹授权；4) 无线调试需先 adb connect <IP>:<端口>。');
    process.exit(2);
  }
  if (devices.length > 1 && !serial) {
    console.error(`MULTIPLE_DEVICES: ${devices.join(', ')}；请用 --serial 指定。`);
    process.exit(2);
  }
  const target = serial ?? devices[0].split(/\s+/)[0];

  const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
  const outDir = join('.local', 'perf', `baseline-${stamp}`);
  await mkdir(outDir, { recursive: true });
  const save = async (name, text) => {
    await writeFile(join(outDir, name), text.endsWith('\n') ? text : `${text}\n`, 'utf8');
    return join(outDir, name);
  };

  if (installApk) {
    console.log(`installing ${installApk} ...`);
    console.log(await adb('install', '-r', installApk));
  }

  const props = await adb('shell', 'getprop');
  const deviceInfo = {
    serial: target,
    model: firstMatch(props, /\[ro\.product\.model\]:\s*\[(.*?)\]/) ?? 'unknown',
    androidRelease: firstMatch(props, /\[ro\.build\.version\.release\]:\s*\[(.*?)\]/) ?? 'unknown',
    abi: firstMatch(props, /\[ro\.product\.cpu\.abi\]:\s*\[(.*?)\]/) ?? 'unknown',
  };
  console.log(`device: ${deviceInfo.model} Android ${deviceInfo.androidRelease} ${deviceInfo.abi}`);

  // 冷启动 x3：force-stop 后完整冷启；只作为 Activity 显示耗时参考。
  const starts = [];
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    await adb('shell', 'am', 'force-stop', PACKAGE);
    await sleep(2000);
    const output = await adb('shell', 'am', 'start', '-W', '-n', ACTIVITY);
    starts.push({
      attempt,
      totalMs: Number(firstMatch(output, /TotalTime:\s*(\d+)/) ?? -1),
      waitMs: Number(firstMatch(output, /WaitTime:\s*(\d+)/) ?? -1),
      launchState: firstMatch(output, /LaunchState:\s*(\S+)/) ?? 'warm-ish',
    });
    await sleep(4000);
  }
  await save('cold-start.json', JSON.stringify(starts, null, 2));
  console.log(`cold start TotalTime ms: ${starts.map((item) => item.totalMs).join(', ')}`);

  // 帧统计窗口：重置 gfxinfo 后按脚本滑动当前页面（盲操作，页面位置由调用者保证）。
  // 注意：Flutter 不经 Android HWUI 渲染，宿主 gfxinfo 通常报 0 帧；
  // 其统计仅作平台层参考，Flutter 帧证据以应用内 PERF_CAPTURE FrameTiming 报告为准。
  await adb('shell', 'dumpsys', 'gfxinfo', PACKAGE, 'reset');
  for (let index = 0; index < swipes; index += 1) {
    await adb('shell', 'input', 'swipe', '540', '1700', '540', '500', '300');
    await sleep(1200);
  }
  for (let index = 0; index < Math.ceil(swipes / 2); index += 1) {
    await adb('shell', 'input', 'swipe', '540', '500', '540', '1700', '300');
    await sleep(1200);
  }
  const gfx = await adb('shell', 'dumpsys', 'gfxinfo', PACKAGE);
  await save('gfxinfo.txt', gfx);
  const gfxStats = {
    totalFrames: Number(firstMatch(gfx, /Total frames rendered:\s*(\d+)/) ?? -1),
    jankyFrames: Number(firstMatch(gfx, /Janky frames:\s*(\d+)/) ?? -1),
    jankyPercent: Number(firstMatch(gfx, /Janky frames:\s*\d+\s*\(([\d.]+)%\)/) ?? -1),
    p50Ms: Number(firstMatch(gfx, /50th percentile:\s*([\d.]+)ms/) ?? -1),
    p90Ms: Number(firstMatch(gfx, /90th percentile:\s*([\d.]+)ms/) ?? -1),
    p95Ms: Number(firstMatch(gfx, /95th percentile:\s*([\d.]+)ms/) ?? -1),
    p99Ms: Number(firstMatch(gfx, /99th percentile:\s*([\d.]+)ms/) ?? -1),
  };
  console.log(`gfxinfo: ${gfxStats.totalFrames} frames, janky ${gfxStats.jankyPercent}%, p50 ${gfxStats.p50Ms}ms, p95 ${gfxStats.p95Ms}ms, p99 ${gfxStats.p99Ms}ms`);

  // 应用内 FrameTiming 采集：PERF_CAPTURE 构建启动 40 秒后落盘；等待并拉取。
  let perfCapturePath = null;
  let frameTiming = null;
  for (let wait = 0; wait < 60; wait += 5) {
    const check = await run('adb', serial ? ['-s', serial, 'shell', 'ls', PERF_FILE] : ['shell', 'ls', PERF_FILE], { encoding: 'utf8' }).catch(() => null);
    if (check && check.stdout.trim().length > 0) break;
    await sleep(5000);
  }
  const exists = await run('adb', serial ? ['-s', serial, 'shell', 'ls', PERF_FILE] : ['shell', 'ls', PERF_FILE], { encoding: 'utf8' }).catch(() => null);
  if (exists && exists.stdout.trim().length > 0) {
    perfCapturePath = join(outDir, 'duoscene-performance.json');
    await run('adb', serial ? ['-s', serial, 'pull', PERF_FILE, perfCapturePath] : ['pull', PERF_FILE, perfCapturePath]);
    const report = JSON.parse(await readFile(perfCapturePath, 'utf8'));
    frameTiming = {
      mode: report.mode,
      windowS: Math.round(report.windowUs / 1e6),
      build: report.build,
      raster: report.raster,
      decodedImageCacheBytes: report.decodedImageCacheBytes,
    };
    console.log(`frame timing (${frameTiming.mode}, ${frameTiming.windowS}s): build p50/p95/p99 ${frameTiming.build.p50Us}/${frameTiming.build.p95Us}/${frameTiming.build.p99Us} us, raster p50/p95/p99 ${frameTiming.raster.p50Us}/${frameTiming.raster.p95Us}/${frameTiming.raster.p99Us} us, over-budget ${frameTiming.build.above16667Us}/${frameTiming.build.count}`);
  } else {
    console.log('PERF_CAPTURE file not found: 该构建未启用 PERF_CAPTURE，或应用未启动满 40 秒。该段跳过（NOT RUN）。');
  }

  const meminfo = await adb('shell', 'dumpsys', 'meminfo', PACKAGE);
  await save('meminfo.txt', meminfo);
  const memory = {
    totalPssKb: Number(firstMatch(meminfo, /TOTAL PSS:\s*(\d+)/) ?? -1),
    javaHeapKb: Number(firstMatch(meminfo, /Java Heap:\s*(\d+)/) ?? -1),
    nativeHeapKb: Number(firstMatch(meminfo, /Native Heap:\s*(\d+)/) ?? -1),
    graphicsKb: Number(firstMatch(meminfo, /Graphics:\s*(\d+)/) ?? -1),
  };
  console.log(`meminfo: TOTAL ${Math.round(memory.totalPssKb / 1024)}MB, native ${Math.round(memory.nativeHeapKb / 1024)}MB, graphics ${Math.round(memory.graphicsKb / 1024)}MB`);

  const topOutput = await adb('shell', 'top', '-n', '1', '-b', '-o', '%CPU').catch(() => '');
  const cpuLine = topOutput.split('\n').find((line) => line.includes(PACKAGE)) ?? '';
  await save('top.txt', topOutput || 'top not available');
  const cpuPercent = Number(firstMatch(cpuLine, /(\d+(?:\.\d+)?)\s*$/) ?? firstMatch(cpuLine.trim().split(/\s+/).slice(-8).join(' '), /(\d+(?:\.\d+)?)/) ?? -1);

  const summary = {
    capturedAt: new Date().toISOString(),
    device: deviceInfo,
    coldStart: starts,
    gfxinfo: gfxStats,
    frameTiming,
    memory,
    cpuPercentSample: cpuPercent,
    caveats: [
      'am start -W 仅衡量 Activity 显示，不是登录/片库/首帧就绪。',
      'FrameTiming 需 Profile 构建才可作为性能证据；Debug/JIT 仅作回归对比。',
      '宿主 gfxinfo 统计不到 Flutter 帧（HWUI-only），仅作平台层参考；Flutter 帧证据以 PERF_CAPTURE 报告为准。',
      'PERF_CAPTURE 每进程只写一次（启动后 40s）；拉取前先删除旧文件并等待满 44s，防止读到上一轮报告。',
      '滑动交互为脚本盲操作，统计窗口覆盖的是当前停留页面的表现。',
    ],
  };
  const summaryPath = join(outDir, 'summary.json');
  await writeFile(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
  console.log(`summary written: ${summaryPath}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
