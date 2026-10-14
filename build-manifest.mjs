#!/usr/bin/env node
/**
 * 下载器分发清单生成（在 buxuku/smartsub-downloaders 仓库 CI 中运行）。
 *
 * 输入：dist/ 目录内已按固定名落位的二进制 + 各引擎版本号
 * 输出：dist/downloader-versions.json（应用内更新检测消费，
 *       结构对应 types/download.ts 的 DownloaderVersionsManifest）
 *       与 dist/checksums.sha256（GitCode 镜像同步校验用）。
 *
 * 用法：
 *   node build-manifest.mjs --dist dist --ytdlp 2026.07.04 --lux 2025.12.29 \
 *     --lux-commit dd00f6d...(完整 sha)
 *
 * 版本语义（上游没变 → 清单里的版本号与二进制都不应变化）：
 *   --ytdlp      yt-dlp 官方 tag（去掉前导 v）
 *   --lux        所构建 lux 提交的 UTC 日期（YYYY.MM.DD），不是构建日期
 *   --lux-commit 所构建 lux 提交的完整 sha，写入 engines.lux.commit；
 *                scripts/check-upstream.sh 靠它判断 lux 上游是否有新提交
 *
 * 资产命名约定（平台键 = `${process.platform}-${process.arch}`）：
 *   yt-dlp-win32-x64.exe / yt-dlp-win32-arm64.exe / yt-dlp-macos(universal)
 *   yt-dlp-linux-x64 / yt-dlp-linux-arm64
 *   lux-win32-x64.exe / lux-win32-arm64.exe / lux-darwin-x64 / lux-darwin-arm64
 *   lux-linux-x64 / lux-linux-arm64
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

function parseArgs(argv) {
  const args = {};
  for (const a of argv) {
    const m = a.match(/^--([^=]+)(?:=(.*))?$/);
    if (m) args[m[1]] = m[2] ?? argv[argv.indexOf(a) + 1];
  }
  return args;
}

const args = parseArgs(process.argv.slice(2));
const distDir = path.resolve(args.dist || 'dist');
const ytdlpVersion = String(args.ytdlp || '').replace(/^v/, '');
const luxVersion = String(args.lux || '');
const luxCommit = String(args['lux-commit'] || '');
if (!ytdlpVersion || !luxVersion) {
  console.error(
    'usage: build-manifest.mjs --dist <dir> --ytdlp <ver> --lux <YYYY.MM.DD> [--lux-commit <sha>]',
  );
  process.exit(1);
}
if (luxCommit && !/^[0-9a-f]{40}$/.test(luxCommit)) {
  console.error(`invalid --lux-commit (expect 40-char hex sha): ${luxCommit}`);
  process.exit(1);
}

/** macOS 官方 yt-dlp 为 universal 二进制：两个平台键共享同一资产 */
const YTDLP_ASSETS = {
  'win32-x64': 'yt-dlp-win32-x64.exe',
  'win32-arm64': 'yt-dlp-win32-arm64.exe',
  'darwin-x64': 'yt-dlp-macos',
  'darwin-arm64': 'yt-dlp-macos',
  'linux-x64': 'yt-dlp-linux-x64',
  'linux-arm64': 'yt-dlp-linux-arm64',
};

const LUX_ASSETS = {
  'win32-x64': 'lux-win32-x64.exe',
  'win32-arm64': 'lux-win32-arm64.exe',
  'darwin-x64': 'lux-darwin-x64',
  'darwin-arm64': 'lux-darwin-arm64',
  'linux-x64': 'lux-linux-x64',
  'linux-arm64': 'lux-linux-arm64',
};

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

const shaCache = new Map();
function assetInfo(name) {
  const filePath = path.join(distDir, name);
  if (!fs.existsSync(filePath)) {
    console.error(`missing asset: ${name}`);
    process.exit(1);
  }
  if (!shaCache.has(name)) {
    shaCache.set(name, {
      name,
      sha256: sha256(filePath),
      size: fs.statSync(filePath).size,
    });
  }
  return shaCache.get(name);
}

function buildAssets(mapping) {
  const out = {};
  for (const [platformKey, assetName] of Object.entries(mapping)) {
    out[platformKey] = assetInfo(assetName);
  }
  return out;
}

const manifest = {
  generatedAt: new Date().toISOString(),
  engines: {
    'yt-dlp': {
      version: ytdlpVersion,
      updateNotes: `yt-dlp official release ${ytdlpVersion}`,
      assets: buildAssets(YTDLP_ASSETS),
    },
    lux: {
      version: luxVersion,
      // 构建所用的上游提交；缺省（旧调用方式）时不写，check-upstream.sh 会视为「需要重建」。
      ...(luxCommit ? { commit: luxCommit } : {}),
      updateNotes: luxCommit
        ? `lux built from iawia002/lux master @ ${luxCommit.slice(0, 7)} (commit date ${luxVersion})`
        : `lux built from iawia002/lux master (commit date ${luxVersion})`,
      assets: buildAssets(LUX_ASSETS),
    },
  },
};

fs.writeFileSync(
  path.join(distDir, 'downloader-versions.json'),
  JSON.stringify(manifest, null, 2),
);

// checksums.sha256：`<sha256>  <name>` 行（sha256sum -c 兼容，镜像同步校验用）
const lines = [...shaCache.values()].map((a) => `${a.sha256}  ${a.name}`);
fs.writeFileSync(path.join(distDir, 'checksums.sha256'), lines.join('\n') + '\n');

console.log(
  `manifest written: yt-dlp ${ytdlpVersion}, lux ${luxVersion}${luxCommit ? ` (${luxCommit.slice(0, 7)})` : ''}`,
);
console.log(lines.join('\n'));
