'use strict';
const vm = require('node:vm');
// Compile a complete real function; do not assume it occupies one line or slice at
// a renamed neighbour. Templates and nested braces are parsed by JavaScript itself.
function functionSource(source, name) {
  const start = source.search(new RegExp('^(?:async )?function ' + name + '\\(', 'm'));
  if (start < 0) throw new Error('Missing function: ' + name);
  let candidate = '';
  for (const line of source.slice(start).split('\n')) {
    candidate += line + '\n';
    try { new vm.Script('(' + candidate + ')'); return candidate; } catch {}
  }
  throw new Error('No complete function: ' + name);
}
function installFunctions(source, scope, names) {
  vm.createContext(scope);
  vm.runInContext(names.map(name => functionSource(source, name)).join('\n'), scope);
  return scope;
}
module.exports = { functionSource, installFunctions };
