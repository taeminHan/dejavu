const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const context = { window: {} };
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(root, 'themes.js'), 'utf8'), context);
const { DejavuThemes, DejavuProgress } = context.window;
let count = 0;
for (const theme of Object.keys(DejavuThemes)) {
  for (const value of [0, 3, 24, 100, -5, 105, null, NaN]) {
    const result = DejavuProgress(value, theme);
    const expected = Number.isFinite(value) ? Math.max(0, Math.min(100, value)) : 'unknown';
    assert(result.includes(`data-value="${expected}"`), `${theme}: invalid normalized value`);
    assert(result.includes(`--usage:${expected === 'unknown' ? 0 : expected}%`));
    if (theme === 'paper') {
      assert(result.includes(`clip-path:inset(0 ${100 - (expected === 'unknown' ? 0 : expected)}% 0 0)`));
    }
    if (theme === 'terminal') assert(result.includes('graph-bracket'));
    count++;
  }
}
assert(!Object.hasOwn(DejavuThemes, 'orbit'), 'Orbit must remain outside this redesign');
assert(fs.existsSync(path.join(root, 'OFL-NanumPenScript.txt')));
for (const file of ['index.html', 'app.js', 'themes.js', 'themes.css', '../../docs/DESIGN_SYSTEM.md', '../../docs/ICON_SYSTEM.md']) {
  const lines = fs.readFileSync(path.join(root, file), 'utf8').split(/\r?\n/);
  assert(lines.every(line => !/[ \t]+$/.test(line)), `${file}: trailing whitespace`);
}
console.log(`Graph numerical boundaries: ${count} checked, 0 mismatched`);
console.log('Orbit exclusion, font license and source whitespace: passed');
