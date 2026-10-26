import { readdir } from 'node:fs/promises';

export const migrationDirectory = new URL('../../migrations/', import.meta.url);

/** 迁移执行与就绪探针共用发布文件清单，避免新增迁移后探针仍接受旧库。 */
export async function listMigrationNames() {
  return (await readdir(migrationDirectory)).filter(name => /^\d{4}_[a-z_]+\.sql$/.test(name)).sort();
}
