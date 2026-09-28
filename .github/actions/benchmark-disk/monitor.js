// Register before cache restoration so this post hook samples after cache saving.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const childProcess = require('node:child_process');

/** Sample filesystem usage without adding volumes together or deleting any data. */
function sample(directory) {
  const filename = path.join(directory, 'metrics.json');
  const metrics = fs.existsSync(filename) ? JSON.parse(fs.readFileSync(filename, 'utf8')) : {};
  for (const [name, target] of Object.entries({workspace: process.cwd(), temporary: os.tmpdir(), nix: '/nix/store'})) {
    if (!fs.existsSync(target)) continue;
    const stats = fs.statfsSync(target);
    const used = stats.bsize * (stats.blocks - stats.bfree);
    const available = stats.bsize * stats.bavail;
    const prior = metrics[name];
    metrics[name] = {path: target, sampled_at: new Date().toISOString(),
      peak_used_bytes: Math.max(prior?.peak_used_bytes ?? 0, used),
      minimum_available_bytes: Math.min(prior?.minimum_available_bytes ?? available, available)};
  }
  fs.writeFileSync(filename + '.tmp', JSON.stringify(metrics));
  fs.renameSync(filename + '.tmp', filename);
  return metrics;
}

if (process.argv[2] === '--sample') {
  const directory = process.argv[3];
  const timer = setInterval(() => {
    if (fs.existsSync(path.join(directory, 'stop'))) clearInterval(timer);
    else sample(directory);
  }, 1000);
} else if (process.env.STATE_directory) {
  const directory = process.env.STATE_directory;
  fs.writeFileSync(path.join(directory, 'stop'), 'stop');
  // The detached sampler exits at its next tick. Sample after it to avoid concurrent writes.
  setTimeout(() => console.log('ADR1_DISK_METRICS=' + JSON.stringify(sample(directory))), 1100);
} else {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'adr1-disk-'));
  sample(directory);
  fs.appendFileSync(process.env.GITHUB_STATE, `directory=${directory}\n`);
  const child = childProcess.spawn(process.execPath, [__filename, '--sample', directory],
    {detached: true, stdio: 'ignore', env: process.env});
  child.unref();
}
