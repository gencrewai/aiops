import { spawn } from 'child_process';
import { writeFileSync, unlinkSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

const startFile = join(tmpdir(), 'aiops-start.txt');

const args = process.argv.slice(2);

if (args[0] !== 'claude') {
  console.log('Usage: npx tsx aiops.ts claude [claude-args...]');
  process.exit(1);
}

writeFileSync(startFile, String(Date.now()));

const claudeArgs = args.slice(1);
const child = spawn('claude', claudeArgs, {
  stdio: 'inherit',
  shell: true,
});

child.on('close', (code) => {
  try { unlinkSync(startFile); } catch {}
  process.exit(code ?? 0);
});

child.on('error', (err) => {
  console.error('Failed to start claude:', err.message);
  try { unlinkSync(startFile); } catch {}
  process.exit(1);
});
