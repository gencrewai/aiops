#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REGISTRY_FILE = path.join(__dirname, 'profiles', 'ai-model-profiles.json');

const TOP_LEVEL_CODEX_KEYS = [
  'model',
  'model_provider',
  'model_reasoning_effort',
  'model_reasoning_summary',
  'model_verbosity',
  'model_context_window',
  'model_auto_compact_token_limit',
];

const args = process.argv.slice(2);

main().catch((error) => {
  console.error(`aiops-models: ${error.message}`);
  process.exit(1);
});

async function main() {
  const command = args[0];

  if (!command || command === '-h' || command === '--help' || command === 'help') {
    printHelp();
    return;
  }

  if (command === 'list') {
    const options = parseOptions(args.slice(1));
    listProfiles(options.target);
    return;
  }

  if (command === 'show') {
    const id = args[1];
    if (!id) usageError('show requires a profile id');
    const profile = getProfile(id);
    console.log(JSON.stringify(profile, null, 2));
    return;
  }

  if (command === 'validate') {
    validateRegistry(loadRegistry());
    console.log('aiops model profiles ok');
    return;
  }

  if (command === 'use') {
    const id = args[1];
    if (!id) usageError('use requires a profile id');
    const options = parseOptions(args.slice(2));
    const profile = getProfile(id);
    applyProfile(profile, options);
    return;
  }

  usageError(`unknown command: ${command}`);
}

function printHelp() {
  console.log(`Usage:
  node aiops-models.mjs list [--target codex|opencode]
  node aiops-models.mjs show <profile>
  node aiops-models.mjs use <profile> [--target codex|opencode|all] [--dry-run]
  node aiops-models.mjs validate

Environment:
  CODEX_HOME       Override Codex config directory (default: ~/.codex)
  OPENCODE_CONFIG  Override OpenCode config file path

Notes:
  Profiles never store secret values. Use env vars or file references in the profile registry.
  Existing config files are backed up before write unless --dry-run is used.`);
}

function usageError(message) {
  console.error(`aiops-models: ${message}`);
  console.error('Run: node aiops-models.mjs help');
  process.exit(2);
}

function parseOptions(optionArgs) {
  const options = {
    target: undefined,
    dryRun: false,
  };

  for (let index = 0; index < optionArgs.length; index += 1) {
    const arg = optionArgs[index];

    if (arg === '--dry-run') {
      options.dryRun = true;
      continue;
    }

    if (arg === '--target') {
      const value = optionArgs[index + 1];
      if (!value) usageError('--target requires a value');
      options.target = value;
      index += 1;
      continue;
    }

    if (arg.startsWith('--target=')) {
      options.target = arg.slice('--target='.length);
      continue;
    }

    usageError(`unknown option: ${arg}`);
  }

  if (options.target && !['codex', 'opencode', 'all'].includes(options.target)) {
    usageError('--target must be codex, opencode, or all');
  }

  return options;
}

function loadRegistry() {
  const raw = fs.readFileSync(REGISTRY_FILE, 'utf8');
  const registry = JSON.parse(raw);
  validateRegistry(registry);
  return registry;
}

function validateRegistry(registry) {
  if (!registry || typeof registry !== 'object' || !Array.isArray(registry.profiles)) {
    throw new Error(`${REGISTRY_FILE} must contain a profiles array`);
  }

  const ids = new Set();
  for (const profile of registry.profiles) {
    if (!profile || typeof profile !== 'object') throw new Error('profile entries must be objects');
    if (!profile.id || typeof profile.id !== 'string') throw new Error('every profile needs a string id');
    if (ids.has(profile.id)) throw new Error(`duplicate profile id: ${profile.id}`);
    ids.add(profile.id);

    if (!Array.isArray(profile.targets) || profile.targets.length === 0) {
      throw new Error(`${profile.id} needs at least one target`);
    }

    for (const target of profile.targets) {
      if (!['codex', 'opencode'].includes(target)) {
        throw new Error(`${profile.id} has unsupported target: ${target}`);
      }
      if (!profile[target]) {
        throw new Error(`${profile.id} lists ${target} but has no ${target} config`);
      }
    }

    if (profile.codex) validateCodexProfile(profile.id, profile.codex);
    if (profile.opencode) validateOpenCodeProfile(profile.id, profile.opencode);
  }
}

function validateCodexProfile(id, codex) {
  if (!codex.model || typeof codex.model !== 'string') {
    throw new Error(`${id}.codex.model is required`);
  }
  if (codex.model_provider && typeof codex.model_provider !== 'string') {
    throw new Error(`${id}.codex.model_provider must be a string`);
  }
  if (codex.provider && codex.provider.id !== codex.model_provider) {
    throw new Error(`${id}.codex.provider.id must match model_provider`);
  }
  if (codex.provider) validateProviderId(`${id}.codex.provider.id`, codex.provider.id);
}

function validateOpenCodeProfile(id, opencode) {
  if (!opencode.model || typeof opencode.model !== 'string') {
    throw new Error(`${id}.opencode.model is required`);
  }
  if (opencode.provider && !opencode.provider.id) {
    throw new Error(`${id}.opencode.provider.id is required`);
  }
  if (opencode.provider) validateProviderId(`${id}.opencode.provider.id`, opencode.provider.id);
}

function validateProviderId(label, value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error(`${label} must contain only letters, numbers, underscores, or hyphens`);
  }
}

function getProfile(id) {
  const registry = loadRegistry();
  const profile = registry.profiles.find((item) => item.id === id);
  if (!profile) throw new Error(`unknown profile: ${id}`);
  return profile;
}

function listProfiles(target) {
  const registry = loadRegistry();
  const profiles = registry.profiles.filter((profile) => {
    if (!target || target === 'all') return true;
    return profile.targets.includes(target);
  });

  const rows = profiles.map((profile) => ({
    id: profile.id,
    targets: profile.targets.join(','),
    label: profile.label || '',
    description: profile.description || '',
  }));

  const widths = {
    id: Math.max(2, ...rows.map((row) => row.id.length)),
    targets: Math.max(7, ...rows.map((row) => row.targets.length)),
    label: Math.max(5, ...rows.map((row) => row.label.length)),
  };

  console.log(`${pad('ID', widths.id)}  ${pad('TARGETS', widths.targets)}  ${pad('LABEL', widths.label)}  DESCRIPTION`);
  for (const row of rows) {
    console.log(`${pad(row.id, widths.id)}  ${pad(row.targets, widths.targets)}  ${pad(row.label, widths.label)}  ${row.description}`);
  }
}

function applyProfile(profile, options) {
  const selectedTargets = resolveTargets(profile, options.target);
  for (const target of selectedTargets) {
    if (target === 'codex') applyCodexProfile(profile, options);
    if (target === 'opencode') applyOpenCodeProfile(profile, options);
  }
}

function resolveTargets(profile, requestedTarget) {
  if (!requestedTarget || requestedTarget === 'all') return profile.targets;
  if (!profile.targets.includes(requestedTarget)) {
    throw new Error(`${profile.id} does not support target: ${requestedTarget}`);
  }
  return [requestedTarget];
}

function applyCodexProfile(profile, options) {
  const codex = profile.codex;
  const codexHome = process.env.CODEX_HOME || path.join(os.homedir(), '.codex');
  const configFile = path.join(codexHome, 'config.toml');
  const before = readFileIfExists(configFile);
  let after = before;

  const topLevelConfig = {};
  for (const key of TOP_LEVEL_CODEX_KEYS) {
    if (codex[key] !== undefined) topLevelConfig[key] = codex[key];
  }

  for (const [key, value] of Object.entries(topLevelConfig)) {
    after = setTomlTopLevelKey(after, key, value);
  }

  if (codex.provider) {
    after = upsertTomlTable(after, `model_providers.${codex.provider.id}`, providerToTomlEntries(codex.provider));
  }

  writeConfigFile(configFile, before, after, {
    dryRun: options.dryRun,
    label: `Codex profile ${profile.id}`,
  });
}

function applyOpenCodeProfile(profile, options) {
  const opencode = profile.opencode;
  const configFile = resolveOpenCodeConfigFile();
  const before = readFileIfExists(configFile);
  const config = before.trim() ? parseJsonc(before, configFile) : {};

  if (!config || typeof config !== 'object' || Array.isArray(config)) {
    throw new Error(`${configFile} must contain a JSON object`);
  }

  config.$schema = config.$schema || 'https://opencode.ai/config.json';
  config.model = opencode.model;
  if (opencode.small_model) config.small_model = opencode.small_model;

  if (opencode.provider) {
    const { id, ...providerConfig } = opencode.provider;
    config.provider = {
      ...(isPlainObject(config.provider) ? config.provider : {}),
      [id]: providerConfig,
    };
  }

  if (opencode.agent) {
    config.agent = mergePlainObjects(isPlainObject(config.agent) ? config.agent : {}, opencode.agent);
  }

  const after = `${JSON.stringify(config, null, 2)}\n`;
  if (before && (configFile.endsWith('.jsonc') || hasJsoncSyntax(before))) {
    console.warn(`OpenCode profile ${profile.id}: JSONC comments/trailing commas are not preserved; backup will keep the original.`);
  }
  writeConfigFile(configFile, before, after, {
    dryRun: options.dryRun,
    label: `OpenCode profile ${profile.id}`,
  });
}

function resolveOpenCodeConfigFile() {
  if (process.env.OPENCODE_CONFIG) return expandHome(process.env.OPENCODE_CONFIG);

  const configDir = path.join(os.homedir(), '.config', 'opencode');
  const json = path.join(configDir, 'opencode.json');
  const jsonc = path.join(configDir, 'opencode.jsonc');

  if (fs.existsSync(json)) return json;
  if (fs.existsSync(jsonc)) return jsonc;
  return json;
}

function providerToTomlEntries(provider) {
  const entries = {};
  for (const [key, value] of Object.entries(provider)) {
    if (key === 'id') continue;
    entries[key] = value;
  }
  return entries;
}

function setTomlTopLevelKey(toml, key, value) {
  const lines = splitLines(toml);
  const rendered = `${key} = ${tomlValue(value)}`;
  let found = false;
  let firstTableIndex = lines.findIndex((line) => /^\s*\[/.test(line));

  if (firstTableIndex === -1) firstTableIndex = lines.length;

  const nextLines = lines.map((line, index) => {
    if (index >= firstTableIndex) return line;
    const pattern = new RegExp(`^\\s*${escapeRegExp(key)}\\s*=`);
    if (pattern.test(line)) {
      found = true;
      return rendered;
    }
    return line;
  });

  if (!found) {
    nextLines.splice(firstTableIndex, 0, rendered);
  }

  return normalizeTrailingNewline(joinLines(nextLines));
}

function upsertTomlTable(toml, tableName, entries) {
  const lines = splitLines(toml);
  const header = `[${tableName}]`;
  const renderedTable = [
    header,
    ...Object.entries(entries).map(([key, value]) => `${key} = ${tomlValue(value)}`),
  ];

  const start = lines.findIndex((line) => line.trim() === header);
  if (start === -1) {
    const next = trimTrailingEmptyLines(lines);
    if (next.length > 0) next.push('');
    next.push(...renderedTable);
    return normalizeTrailingNewline(joinLines(next));
  }

  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^\s*\[/.test(lines[index])) {
      end = index;
      break;
    }
  }

  const next = [
    ...lines.slice(0, start),
    ...renderedTable,
    ...lines.slice(end),
  ];
  return normalizeTrailingNewline(joinLines(next));
}

function tomlValue(value) {
  if (typeof value === 'string') return JSON.stringify(value);
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (Array.isArray(value)) return `[${value.map(tomlValue).join(', ')}]`;
  throw new Error(`unsupported TOML value: ${JSON.stringify(value)}`);
}

function parseJsonc(raw, file) {
  try {
    return JSON.parse(stripTrailingCommas(stripJsonComments(raw)));
  } catch (error) {
    throw new Error(`failed to parse ${file}: ${error.message}`);
  }
}

function stripJsonComments(raw) {
  let output = '';
  let inString = false;
  let quote = '';
  let escaped = false;

  for (let index = 0; index < raw.length; index += 1) {
    const char = raw[index];
    const next = raw[index + 1];

    if (inString) {
      output += char;
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === quote) {
        inString = false;
        quote = '';
      }
      continue;
    }

    if (char === '"' || char === "'") {
      inString = true;
      quote = char;
      output += char;
      continue;
    }

    if (char === '/' && next === '/') {
      while (index < raw.length && raw[index] !== '\n') index += 1;
      output += '\n';
      continue;
    }

    if (char === '/' && next === '*') {
      index += 2;
      while (index < raw.length && !(raw[index] === '*' && raw[index + 1] === '/')) index += 1;
      index += 1;
      continue;
    }

    output += char;
  }

  return output;
}

function stripTrailingCommas(raw) {
  return raw.replace(/,\s*([}\]])/g, '$1');
}

function hasJsoncSyntax(raw) {
  return stripJsonComments(raw) !== raw || stripTrailingCommas(raw) !== raw;
}

function writeConfigFile(file, before, after, { dryRun, label }) {
  if (before === after) {
    console.log(`${label}: no changes (${file})`);
    return;
  }

  if (dryRun) {
    console.log(`${label}: would update ${file}`);
    console.log('Inspect profile details with: node aiops-models.mjs show <profile>');
    return;
  }

  fs.mkdirSync(path.dirname(file), { recursive: true });
  if (before) {
    const backupFile = `${file}.bak.${timestamp()}`;
    fs.copyFileSync(file, backupFile);
    console.log(`${label}: backed up ${backupFile}`);
  }
  fs.writeFileSync(file, after);
  console.log(`${label}: updated ${file}`);
}

function readFileIfExists(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
}

function splitLines(text) {
  if (!text) return [];
  return text.replace(/\n$/, '').split('\n');
}

function joinLines(lines) {
  return lines.join('\n');
}

function trimTrailingEmptyLines(lines) {
  const next = [...lines];
  while (next.length > 0 && next[next.length - 1].trim() === '') next.pop();
  return next;
}

function normalizeTrailingNewline(text) {
  return text ? `${text.replace(/\n*$/, '')}\n` : '';
}

function timestamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.(\d{3})Z$/, '$1Z');
}

function expandHome(file) {
  if (file === '~') return os.homedir();
  if (file.startsWith('~/')) return path.join(os.homedir(), file.slice(2));
  return file;
}

function isPlainObject(value) {
  return Boolean(value && typeof value === 'object' && !Array.isArray(value));
}

function mergePlainObjects(base, override) {
  const output = { ...base };
  for (const [key, value] of Object.entries(override)) {
    if (isPlainObject(value) && isPlainObject(output[key])) {
      output[key] = mergePlainObjects(output[key], value);
    } else {
      output[key] = value;
    }
  }
  return output;
}

function pad(value, width) {
  return String(value).padEnd(width, ' ');
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
