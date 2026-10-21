import path from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

export async function writeNewExport(output, payload) {
  const serialized = JSON.stringify(payload, null, 2);
  const destination = path.resolve(output);
  await mkdir(path.dirname(destination), { recursive: true });
  // Exclusive creation protects reviewed exports, including concurrent commands.
  await writeFile(destination, serialized, { flag: 'wx', encoding: 'utf8' });
}
