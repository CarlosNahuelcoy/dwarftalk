--@module = true
--[=====[

dwarftalk/logger
===============
Simple file logger for debugging

]=====]

local logger = {}

local log_path = dfhack.getDFPath() .. '/dwarftalk_temp/debug.log'

function logger.log(message)
    local f = io.open(log_path, 'a')
    if f then
        f:write(os.date("[%H:%M:%S] ") .. message .. "\n")
        f:close()
    end
end

function logger.clear()
    local f = io.open(log_path, 'w')
    if f then
        f:write("=== DwarfTalk Debug Log ===\n")
        f:write("Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        f:close()
    end
end

return logger