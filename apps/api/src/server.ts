import { buildApp } from './app.ts';
import { loadConfig } from './config/env.ts';

async function main() {
  const config = loadConfig();
  const app = buildApp({ config });
  let closing = false;
  async function shutdown() {
    if (closing) return;
    closing = true;
    // 防止失联连接阻止进程退出；正常路径由 onClose 释放连接池。
    const timeout = setTimeout(() => process.exit(1), 10_000);
    timeout.unref();
    try { await app.close(); } catch { process.exitCode = 1; }
    finally { clearTimeout(timeout); }
  }
  process.once('SIGINT', () => { void shutdown(); });
  process.once('SIGTERM', () => { void shutdown(); });
  try {
    await app.listen({ host: config.host, port: config.port });
  } catch {
    app.log.fatal('API startup failed; verify configuration and port availability');
    process.exitCode = 1;
    await shutdown();
  }
}

main().catch(() => {
  // 不打印配置异常的原始对象，以免意外暴露敏感环境变量。
  console.error('API initialization failed; check environment configuration');
  process.exitCode = 1;
});
