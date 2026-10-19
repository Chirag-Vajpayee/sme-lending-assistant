#!/usr/bin/env node
/**
 * Fails the build when any Apex test fails or when coverage of this project's own classes
 * (vendored fflib_* classes excluded) is below the threshold.
 *
 * Usage: node scripts/check-test-results.js <sf apex run test --result-format json output> [minCoveragePercent]
 */
const fs = require('fs');

const [, , resultFile, minArg] = process.argv;
const minCoverage = Number(minArg || 90);

if (!resultFile || !fs.existsSync(resultFile)) {
    console.error(`Test result file not found: ${resultFile}`);
    process.exit(1);
}

const raw = JSON.parse(fs.readFileSync(resultFile, 'utf8'));
const result = raw.result || raw;

const tests = result.tests || [];
const failures = tests.filter((t) => t.Outcome !== 'Pass');
console.log(`Tests run: ${tests.length}, failed: ${failures.length}`);
for (const f of failures) {
    console.log(`  FAIL ${f.FullName || f.MethodName}: ${f.Message}\n       ${f.StackTrace || ''}`);
}

const isOwnClass = (name) => name && !name.startsWith('fflib_');
const coverageRows = ((result.coverage && result.coverage.coverage) || []).filter((c) => isOwnClass(c.name));

let totalLines = 0;
let coveredLines = 0;
for (const row of coverageRows) {
    let lines = row.totalLines;
    let covered = row.totalCovered;
    if (lines === undefined && row.lines) {
        const values = Object.values(row.lines);
        lines = values.length;
        covered = values.filter((v) => v > 0).length;
    }
    totalLines += lines || 0;
    coveredLines += covered || 0;
    console.log(`  ${String(row.coveredPercent ?? Math.round(((covered || 0) / (lines || 1)) * 100)).padStart(3)}%  ${row.name}`);
}

const percent = totalLines === 0 ? 0 : (coveredLines / totalLines) * 100;
console.log(`Coverage of project classes: ${percent.toFixed(1)}% (${coveredLines}/${totalLines} lines), minimum ${minCoverage}%`);

if (tests.length === 0) {
    console.error('No test results found. Did the test run fail to start?');
    process.exit(1);
}
if (failures.length > 0) {
    process.exit(1);
}
if (percent < minCoverage) {
    console.error(`Coverage ${percent.toFixed(1)}% is below the ${minCoverage}% minimum.`);
    process.exit(1);
}
