--@module = true
--[=====[
dwarftalk/debug_logger
======================
Simple debug logger - set LOGGING_ENABLED = true to activate
]=====]

local logger = {}

local LOGGING_ENABLED = false

local log_file = dfhack.getDFPath() .. '/dwarftalk_debug.log'

function logger.log(section, message)
    if not LOGGING_ENABLED then return end
    
    local f = io.open(log_file, 'a')
    if f then
        f:write('[' .. section .. '] ' .. tostring(message) .. '\n')
        f:close()
    end
end

function logger.section(title)
    if not LOGGING_ENABLED then return end
    
    local f = io.open(log_file, 'a')
    if f then
        f:write('\n=== ' .. tostring(title) .. ' ===\n')
        f:close()
    end
end

function logger.clear()
    if not LOGGING_ENABLED then return end
    local f = io.open(log_file, 'w')
    if f then f:close() end
end

return logger