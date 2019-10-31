-- from https://bitbucket.org/itraykov/profile.lua/src/master/

local clock = os.clock

local profile = {}

-- function labels
local _labeled = {}
-- function definitions
local _defined = {}
-- time of last call
local _tcalled = {}
-- total execution time
local _telapsed = {}
-- number of calls
local _ncalls = {}
local _nrefs = {}
-- recursion counter
local _current = nil
-- list of internal profiler functions
local _internal = {}

function profile.hooker(event)
  if event == "call" then
    local info = debug.getinfo(2, 'fnS')
    local f = info.func
    -- ignore the profiler itself
    if _internal[f] or info.what ~= "Lua" then
      return
    end
    if _current ~= f then
      _current = f
      -- get the function name if available
      if not _labeled[f] and info.name then
        _labeled[f] = info.name
      end
      -- find the line definition
      if not _defined[f] then
        _defined[f] = info.short_src..":"..info.linedefined
        _ncalls[f] = 0
        _telapsed[f] = 0
        _nrefs[f] = 0
      end
      _nrefs[f] = _nrefs[f] + 1
      if _nrefs[f] == 1 then
        _tcalled[f] = clock()
      end
    end
    _ncalls[f] = _ncalls[f] + 1
  else
    local f = _current
    if f then
      local prev = debug.getinfo(3, 'f')
      if not prev or prev.func ~= f then
        _current = prev.func
        if _nrefs[f] >= 1 then
          _nrefs[f] = _nrefs[f] - 1
          if _nrefs[f] == 0 then
            local dt = clock() - _tcalled[f]
            _telapsed[f] = _telapsed[f] + dt
            _tcalled[f] = nil
          end
        end
        assert(_nrefs[f] >= 0, _nrefs[f])
      end
    end
  end
end

--- Sets a clock function to be used by the profiler.
-- @param f Clock function that returns a number
function profile.setclock(f)
  assert(type(f) == "function", "clock must be a function")
  clock = f
end

--- Starts collecting data.
function profile.start()
  debug.sethook(profile.hooker, "cr")
end

--- Stops collecting data.
function profile.stop()
  debug.sethook()
  for f in pairs(_tcalled) do
    _tcalled[f] = nil
  end
  for f in pairs(_nrefs) do
    _nrefs[f] = 0
  end
  -- combines data generated by closures
  local lookup = {}
  for f, d in pairs(_defined) do
    local id = _labeled[f]..d
    local f2 = lookup[id]
    if f2 then
      _ncalls[f2] = _ncalls[f2] + (_ncalls[f] or 0)
      _telapsed[f2] = _telapsed[f2] + (_telapsed[f] or 0)
      _defined[f], _labeled[f] = nil, nil
      _ncalls[f], _telapsed[f] = nil, nil
    else
      lookup[id] = f
    end
  end
  collectgarbage('collect')
end

--- Resets all collected data.
function profile.reset()
  for f in pairs(_ncalls) do
    _ncalls[f] = 0
  end
  for f in pairs(_telapsed) do
    _telapsed[f] = 0
  end
  for f in pairs(_tcalled) do
    _tcalled[f] = nil
  end
  collectgarbage('collect')
end

function profile.comp(a, b)
  local dt = _telapsed[b] - _telapsed[a]
  if dt == 0 then
    return _ncalls[b] < _ncalls[a]
  end
  return dt < 0
end

--- Iterates all functions that have been called since the profile was started.
-- @param n Number of results (optional)
function profile.query(n)
  local t = {}
  for f in pairs(_ncalls) do
    t[#t + 1] = f
  end
  table.sort(t, profile.comp)
  if n then
    while #t > n do
      table.remove(t)
    end
  end
  for i, f in ipairs(t) do
    t[i] = { i, _labeled[f], _ncalls[f], _telapsed[f], _defined[f] }
  end
  return t
end

local cols = { 3, 32, 8, 24, 32 }
function profile.report(n)
  local out = {}
  local report = profile.query(n)
  for i, row in ipairs(report) do
    for j = 1, 5 do
      local s = row[j]
      local l2 = cols[j]
      s = tostring(s)
      local l1 = s:len()
      if l1 < l2 then
        s = s..(' '):rep(l2-l1)
      elseif l1 > l2 then
        s = s:sub(l1 - l2 + 1, l1)
      end
      row[j] = s
    end
    out[i] = table.concat(row, ' | ')
  end

  local row = " +-----+----------------------------------+----------+--------------------------+----------------------------------+ \n"
  local col = " | #   | Function                         | Calls    | Time                     | Code                             | \n"
  local sz = row..col..row
  if #out > 0 then
    sz = sz..' | '..table.concat(out, ' | \n | ')..' | \n'
  end
  return '\n'..sz..row
end

-- store all internal profiler functions
for k, v in pairs(profile) do
  if type(v) == "function" then
    _internal[v] = true
  end
end

return profile