import { emitKeypressEvents } from 'node:readline';
import { loadConfig } from '../config/env.ts';
import { Database } from '../shared/database.ts';
import { migrate } from './migrate.ts';
import { createPrivateUser, disablePrivateUser } from './accounts.ts';

function readPassword(): Promise<string> {
  if (!process.stdin.isTTY) throw new Error('Interactive TTY is required for password entry');
  process.stdout.write('Password (hidden, 12-128 characters): ');
  emitKeypressEvents(process.stdin);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  return new Promise((resolve, reject) => {
    let password = '';
    function done(error?: Error) {
      process.stdin.off('keypress', onKey);
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdout.write('\n');
      if (error) reject(error); else resolve(password);
      password = '';
    }
    function onKey(text: string | undefined, key: { name?: string; ctrl?: boolean; meta?: boolean; sequence?: string }) {
      if (key.ctrl && key.name === 'c') return done(new Error('Cancelled'));
      if (key.name === 'return') return done();
      if (key.name === 'backspace') { password = Array.from(password).slice(0, -1).join(''); return; }
      if (text && !key.ctrl && !key.meta && !text.includes('\u001b') && password.length + text.length <= 128) password += text;
    }
    process.stdin.on('keypress', onKey);
  });
}

async function main() {
  const [command, username, displayName] = process.argv.slice(2);
  const config = loadConfig();
  if (config.database.mode !== 'mysql') throw new Error('DATABASE_MODE=mysql is required');
  if (!['migrate', 'create-user', 'disable-user', 'prune-sessions'].includes(command ?? '')) throw new Error('Unknown command');
  const db = new Database(config.database);
  try {
    if (command === 'migrate') console.log('Applied migrations:', await migrate(db));
    if (command === 'create-user') {
      if (!username || !displayName) throw new Error('Username and display name are required');
      console.log('Created private account:', await createPrivateUser(db, username, displayName, await readPassword()));
    }
    if (command === 'disable-user') {
      if (!username) throw new Error('Username is required');
      await disablePrivateUser(db, username);
      console.log('Account disabled and sessions revoked');
    }
    if (command === 'prune-sessions') {
      await db.run('DELETE FROM auth_sessions WHERE expires_at <= UTC_TIMESTAMP(3)');
      console.log('Expired sessions and refresh history removed');
    }
  } finally { await db.close(); }
}

main().catch(() => {
  console.error('Command failed. Check arguments, database readiness and migration status; credentials are not printed.');
  process.exitCode = 1;
});
