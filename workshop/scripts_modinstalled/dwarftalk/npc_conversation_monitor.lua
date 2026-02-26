--@module = true

local conversations = require('dwarf_conversations')
local player2_api = require('player2_api')
local action_engine = require('action_engine')

local monitor = {}
monitor.enabled = false
monitor.tick_counter = 0
monitor.CHECK_INTERVAL = 1200
monitor.api_busy = false
monitor.session_id = 0  -- ID de sesión - mata loops viejos

function monitor.start()
    local config_manager = require('config_manager')
    local cfg = config_manager.load()
    
    if cfg.npc_conversations_enabled == false then
        print("[NPC Monitor] Disabled in settings")
        return
    end
    
    monitor.session_id = monitor.session_id + 1
    local my_session = monitor.session_id
    
    monitor.enabled = true
    monitor.api_busy = false
    monitor.next_check_time = nil  -- Se inicializa en loop()
    
    local interval_minutes = cfg.npc_interval_minutes or 20
    
    print("[NPC Monitor] ========================================")
    print("[NPC Monitor] Started - Session " .. my_session)
    print("[NPC Monitor] Interval: " .. interval_minutes .. " minutes (REAL TIME)")
    print("[NPC Monitor] ========================================")
    
    monitor.loop(my_session)
end

function monitor.stop()
    -- Incrementar session para matar todos los loops
    monitor.session_id = monitor.session_id + 1
    monitor.enabled = false
    monitor.api_busy = false
    
    print("[NPC Monitor] Stopped - Session " .. monitor.session_id)
end

function monitor.loop(session_id)
    local logger = require('debug_logger')
    
    -- Verify this loop is still the active session
    if session_id ~= monitor.session_id then
        return
    end
    
    if not monitor.enabled then 
        return
    end
    
    -- More frequent checks: every 30 real-world seconds
    local now = os.time()
    
    if not monitor.last_check_time then
        monitor.last_check_time = now
    end
    
    -- Only perform check every 30 seconds
    if now - monitor.last_check_time < 30 then
        -- Reschedule
        if monitor.enabled and session_id == monitor.session_id then
            dfhack.timeout(500, 'ticks', function()
                monitor.loop(session_id)
            end)
        end
        return
    end
    
    monitor.last_check_time = now
    
    -- Calculate probability based on user's interval setting
    local config_manager = require('config_manager')
    local cfg = config_manager.load()
    local interval_minutes = cfg.npc_interval_minutes or 20
    
    -- Probability = 30 seconds / total interval
    -- Example: 5 min interval = 300 sec → probability = 30/300 = 10% per check
    -- Result: on average, 1 conversation every 5 minutes
    local probability = (30.0 / (interval_minutes * 60.0)) * 100
    
    local roll = math.random(100)
    
    logger.log("NPC_LOOP", string.format("Check - Roll: %d vs %.1f%% probability", roll, probability))
    
    if roll > probability then
        -- Don't generate this time
        logger.log("NPC_LOOP", "No conversation this check")
    else
        -- Generate conversation!
        logger.log("NPC_LOOP", "Probability hit - generating conversation")
        
        if not monitor.api_busy then
            monitor.try_generate_conversation()
        else
            logger.log("NPC_LOOP", "API busy - skipping")
        end
    end
    
    -- Reschedule loop every 30 real-world seconds (500 ticks)
    if monitor.enabled and session_id == monitor.session_id then
        dfhack.timeout(500, 'ticks', function()
            monitor.loop(session_id)
        end)
    end
end

function monitor.try_generate_conversation()
    local logger = require('debug_logger')
    
    monitor.api_busy = true
    
    logger.section("NPC CONVERSATION ATTEMPT")
    
    local pairs = conversations.find_nearby_pairs()
    
    logger.log("NPC", "Pairs: " .. #pairs)
    
    if #pairs == 0 then
        monitor.api_busy = false
        return
    end
    
    local pair = pairs[math.random(#pairs)]
    local unit1, unit2 = pair[1], pair[2]
    
    local prompt, name1, name2 = conversations.build_context(unit1, unit2)
    
    logger.log("NPC", "Generating: " .. name1 .. " & " .. name2)
    
    player2_api.generate_npc_conversation(prompt, function(success, result)
        monitor.api_busy = false
        
        if not success or not result or not result.dialogue then
            return
        end
        
        local dwarf1_info = conversations.get_dwarf_info(unit1)
        local dwarf2_info = conversations.get_dwarf_info(unit2)
        
        local effect_msg1, effect_msg2
        
        if result.effect1 and result.effect1.type then
            local ok, msg = pcall(action_engine.execute, dwarf1_info, result.effect1)
            if ok and msg then effect_msg1 = msg end
        end
        
        if result.effect2 and result.effect2.type then
            local ok, msg = pcall(action_engine.execute, dwarf2_info, result.effect2)
            if ok and msg then effect_msg2 = msg end
        end
        
        conversations.save_to_history(name1, name2, result.dialogue, os.time(), {
            effect1 = effect_msg1,
            effect2 = effect_msg2
        })
        
        dfhack.gui.showAnnouncement(
            "💬 " .. name1 .. " & " .. name2 .. " had a conversation",
            COLOR_CYAN,
            false
        )
    end)
end

dfhack.onStateChange.dwarftalk_npc_monitor = function(event)
    if event == SC_WORLD_UNLOADED then
        monitor.stop()
    end
end

return monitor