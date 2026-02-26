local logger = require('debug_logger')

logger.section("NPC MONITOR AUTO-START")
logger.log("NPCSTART", "Script called")

-- Auto-start NPC conversation monitor with retry
local function try_start()
    logger.log("NPCSTART", "try_start() called")
    
    -- Check if world is loaded
    if not dfhack.isWorldLoaded() then
        logger.log("NPCSTART", "World NOT loaded, scheduling retry...")
        dfhack.timeout(10, 'frames', try_start)
        return
    end
    
    logger.log("NPCSTART", "World IS loaded")
    logger.log("NPCSTART", "Requiring npc_conversation_monitor...")
    
    local ok, monitor = pcall(require, 'npc_conversation_monitor')
    
    if not ok then
        logger.log("NPCSTART", "ERROR requiring module: " .. tostring(monitor))
        return
    end
    
    logger.log("NPCSTART", "Module loaded successfully")
    logger.log("NPCSTART", "Current monitor.enabled: " .. tostring(monitor.enabled))
    
    if monitor.enabled then
        logger.log("NPCSTART", "Monitor already running, exiting")
        return
    end
    
    logger.log("NPCSTART", "Calling monitor.start()...")
    
    local start_ok, err = pcall(monitor.start)
    
    if not start_ok then
        logger.log("NPCSTART", "ERROR calling start(): " .. tostring(err))
        return
    end
    
    logger.log("NPCSTART", "monitor.start() completed")
    logger.log("NPCSTART", "New monitor.enabled: " .. tostring(monitor.enabled))
    logger.log("NPCSTART", "SUCCESS - Monitor started")
end

logger.log("NPCSTART", "Starting retry loop...")
try_start()
logger.log("NPCSTART", "Script complete")