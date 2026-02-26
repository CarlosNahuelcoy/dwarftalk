local logger = {}

-- Set to false to disable all logging
local LOGGING_ENABLED = false  -- CHANGE THIS

function logger.log(section, message)
    if not LOGGING_ENABLED then
        return  -- Do nothing
    end
    
    -- ... rest of the code
end

function logger.section(title)
    if not LOGGING_ENABLED then
        return
    end
    
    -- ... rest of the code
end

return logger