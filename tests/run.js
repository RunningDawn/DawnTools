// Runs tests/run.lua without a Lua install:  cd tests && npm install && npm test
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const dir = path.resolve(__dirname, '..').split(path.sep).join('/') + '/';
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(dir));
lua.lua_setglobal(L, to_luastring('ADDON_DIR'));
lua.lua_getglobal(L, to_luastring('debug'));
lua.lua_getfield(L, -1, to_luastring('traceback'));
lua.lua_remove(L, -2);
if (lauxlib.luaL_loadfile(L, to_luastring(dir + 'tests/run.lua')) !== 0 || lua.lua_pcall(L, 0, 0, -2) !== 0) {
  console.error(to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
