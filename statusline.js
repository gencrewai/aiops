import { execSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

const startFile = join(tmpdir(), 'aiops-start.txt');

function elapsed() {
  if (!existsSync(startFile)) return '0s';
  const start = parseInt(readFileSync(startFile, 'utf8').trim(), 10);
  const diff = Math.floor((Date.now() - start) / 1000);
  const m = Math.floor(diff / 60);
  const s = diff % 60;
  return m > 0 ? `${m}m${s}s` : `${s}s`;
}

function gitInfo() {
  try {
    const status = execSync('git status --porcelain', { encoding: 'utf8', timeout: 3000 });
    const lines = status.trim().split('\n').filter(Boolean);
    const changed = lines.length;

    const branch = execSync('git branch --show-current', { encoding: 'utf8', timeout: 3000 }).trim();

    return { branch, changed };
  } catch {
    return { branch: '-', changed: 0 };
  }
}

const time = elapsed();
const { branch, changed } = gitInfo();

process.stdout.write(`⏱ ${time} │ 🌿 ${branch} │ 📝 ${changed} changed`);
