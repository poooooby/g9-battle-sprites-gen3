-- Run from the mod root: luajit tests/host_test.lua
-- Which host main.lua takes itself to be in. The save editor is the host only while it is open
-- (its App has a session). Once it has been opened, its require path stays set for the rest of
-- the run, so `require("Gen")` keeps working in games started later: a Red to Crystal game must
-- still get the Red to Crystal hooks, and a FireRed to Emerald game must not be taken for the
-- editor.
local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

love = { timer = { getTime = function() return 0 end } }

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- every sibling but options.lua is a stub: a table whose every field is a function returning a
-- table, and which can itself be called
local STUB = [[
local function stub()
  return setmetatable({}, {
    __index = function() return function() return {} end end,
    __call = function() return {} end,
  })
end
return stub()
]]

-- Loads main.lua as a game would. Returns the siblings it read and the option keys it defined.
local function load()
  local read, defined = {}, nil
  local mod = {
    path = "mod",
    exports = {},
    log = { error = function() end, info = function() end, warn = function() end },
    options = {
      define = function(_, schema)
        defined = {}
        for _, row in ipairs(schema) do defined[#defined + 1] = row.key end
      end,
      get = function() return nil end,
    },
    events = { on = function() end },
    hooks = { wrap = function() end },
  }
  function mod:read(name)
    read[name] = true
    if name == "options.lua" then return readFile(name) end
    return STUB
  end
  function mod:find() return nil end
  -- (as the mod sandbox runs it: no `package`)
  local chunk = assert(loadfile("main.lua"))
  setfenv(chunk, setmetatable({}, { __index = function(_, k)
    if k ~= "package" then return _G[k] end
  end }))
  local main = chunk()
  main(mod)
  return read, defined
end

local function editorModules(open)
  package.loaded["Gen"] = { bindGame3Data = function() end }
  package.loaded["App"] = { getState = function() return open and {} or nil end }
end
local function editorClosed()
  -- (closing evicts the editor's modules; its require path stays, so require("Gen") still loads)
  package.loaded["Gen"], package.loaded["App"] = nil, nil
  package.preload["Gen"] = function() return { bindGame3Data = function() end } end
  package.preload["App"] = function() return { getState = function() return nil end } end
end

local version = 1
package.loaded["src.core.GameVersion"] = { generation = function() return version end }

-- a Red game, with the editor never opened: the Red to Crystal hooks and all the options
do
  local read, defined = load()
  check(read["src/gen1.lua"] and not read["src/editor.lua"], "Red: the Red to Crystal hooks")
  check(defined and #defined > 5, "Red: every option")
end

-- a Red game after the editor was opened and closed (the report: the game's own pics in battle)
editorClosed()
do
  local read, defined = load()
  check(read["src/gen1.lua"] and not read["src/editor.lua"], "Red after the editor: the Red to Crystal hooks")
  check(defined and #defined > 5, "Red after the editor: every option")
end

-- the editor open: the Gen 3 host whatever the version says (its default version is Red's),
-- with its Red to Crystal pictures
editorModules(true)
do
  local read, defined = load()
  check(defined and #defined == 5, "the editor: the FireRed to Emerald options")
  check(read["src/editor.lua"], "the editor: its Red to Crystal pictures")
end

-- the editor's modules still loaded but its session gone (App.unload): a game
editorModules(false)
do
  local read, defined = load()
  check(defined and #defined > 5 and not read["src/editor.lua"], "the editor unloaded: a game")
end

print(("%d/%d checks passed (g9-battle-sprites-gen3 host)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
