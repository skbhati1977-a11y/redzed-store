'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.resolve(__dirname,'../../real-common.js'),'utf8');
test('universal business uppercase authority is installed and protected',()=>{assert.match(source,/installBusinessUppercaseInputs/);assert.match(source,/toLocaleUpperCase/);assert.match(source,/password.*email.*url.*search/);assert.match(source,/remark\|remarks\|note\|notes\|description/);assert.match(source,/addEventListener\('submit'/);assert.match(source,/dataset\.rrUppercase==='off'/)});

test('number assist must normalize before matching',()=>{const accessory=fs.readFileSync(path.resolve(__dirname,'../../real-accessory-master-v804.js'),'utf8');assert.match(accessory,/uppercaseBusinessValue\?\.\(input\).*const rows=matches\(\)/s);});
