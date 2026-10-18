--@module = true
--[=====[

dwarftalk/world_paths
=====================
Per-world save locations. Conversations are keyed by unit id, and unit ids
repeat across worlds, so everything tied to a fortress lives under
dwarftalk_saves/worlds/<DF save folder>/. Settings stay global.

]=====]

local world_paths = {}

local root = dfhack.getDFPath() .. '/dwarftalk_saves/'

local function world_key()
    local ok, dir = pcall(function() return df.global.world.cur_savegame.save_dir end)
    if ok and dir and dir ~= '' then
        return (dir:gsub('[^%w%-_]', '_'))
    end
    return 'unsaved'
end

-- Files written before saves were per-world belong to whichever world the
-- player had loaded; adopt them into the first world we see, once.
local function migrate_legacy(dir)
    local marker = root .. 'worlds/.migrated'
    if dfhack.filesystem.exists(marker) then return end
    for _, name in ipairs(dfhack.filesystem.listdir(root) or {}) do
        if name:match('^conversation_%d+%.json$') or name == 'fortress_context.json' then
            os.rename(root .. name, dir .. name)
        end
    end
    os.rename(root .. 'messages/pending.json', dir .. 'pending_messages.json')
    os.rename(dfhack.getDFPath() .. '/dwarftalk_temp/npc_conversations.json', dir .. 'npc_conversations.json')
    local f = io.open(marker, 'w')
    if f then f:close() end
end

-- Directory (with trailing slash) for the currently loaded world.
function world_paths.dir()
    local key = world_key()
    local dir = root .. 'worlds/' .. key .. '/'
    dfhack.filesystem.mkdir_recursive(dir)
    if key ~= 'unsaved' then
        migrate_legacy(dir)
    end
    return dir
end

function world_paths.file(name)
    return world_paths.dir() .. name
end

return world_paths
