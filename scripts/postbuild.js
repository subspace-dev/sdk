#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Create package.json files for module type markers
const cjsDir = path.join(__dirname, '../dist/cjs');
const esmDir = path.join(__dirname, '../dist/esm');

// Ensure directories exist
if (!fs.existsSync(cjsDir)) {
    fs.mkdirSync(cjsDir, { recursive: true });
}

if (!fs.existsSync(esmDir)) {
    fs.mkdirSync(esmDir, { recursive: true });
}

// Write package.json markers
fs.writeFileSync(
    path.join(cjsDir, 'package.json'),
    JSON.stringify({ type: 'commonjs' }, null, 2)
);

fs.writeFileSync(
    path.join(esmDir, 'package.json'),
    JSON.stringify({ type: 'module' }, null, 2)
);

console.log('✅ Package type markers created'); 