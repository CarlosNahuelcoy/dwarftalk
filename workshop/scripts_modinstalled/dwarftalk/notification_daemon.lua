--@module = true
--[=====[

dwarftalk/notification_daemon
=============================
Background daemon that generates periodic messages from dwarves

]=====]

local config_manager = require('config_manager')
local message_generator = require('message_generator')
local message_system = require('message_system')

local daemon = {}

local running = false
local next_check_time = 0
local recent_senders = {}

-- ============================================================================
-- CHECK IF SHOULD GENERATE MESSAGE
-- ============================================================================

function daemon.check_and_generate()
    -- Check if enabled
    if not config_manager.is_notifications_enabled() then
        return
    end
    
    -- Get config
    local chance = config_manager.get_notification_chance()
    
    -- Roll chance
    local roll = math.random(100)
    if roll > chance then
        print("[NotificationDaemon] No message this check (rolled " .. roll .. " vs " .. chance .. "%)")
        return
    end
    
    print("[NotificationDaemon] Generating message...")
    
    -- Get all eligible dwarves
    local eligible = {}
    
    for _, unit in ipairs(df.global.world.units.active) do
        if dfhack.units.isCitizen(unit) and not dfhack.units.isDead(unit) then
            -- SKIP if sent message recently
            if not recent_senders[tonumber(unit.id)] then
                -- Check if dwarf has urgent needs (safely)
                local has_urgent = false
                
                -- Use pcall for extra safety
                local ok = pcall(function()
                    if unit.status and unit.status.current_soul then
                        local soul = unit.status.current_soul
                        if soul.needs then
                            for i = 0, #soul.needs - 1 do
                                local need = soul.needs[i]
                                if need and need.level and need.level >= 8 then
                                    has_urgent = true
                                    break
                                end
                            end
                        end
                    end
                end)
                
                -- Add if urgent or random chance
                if has_urgent or math.random(100) <= 30 then
                    table.insert(eligible, unit)
                end
            end
        end
    end
    
    if #eligible == 0 then
        print("[NotificationDaemon] No eligible dwarves found (all sent messages recently)")
        return
    end
    
    -- Pick random dwarf
    local chosen = eligible[math.random(#eligible)]
    local dwarf_id = tonumber(chosen.id)
    
    -- Mark as sent
    recent_senders[dwarf_id] = os.time()
    
    -- Clean old senders (older than 30 minutes)
    local now = os.time()
    for id, timestamp in pairs(recent_senders) do
        if now - timestamp > 600 then
            recent_senders[id] = nil
        end
    end
    
    -- Generate message
    message_generator.generate_message(chosen, function(success, dwarf_info, message_text)
        if success then
            print("[NotificationDaemon] ✓ Message generated from " .. dwarf_info.name)
            
            -- Show notification
            dfhack.gui.showAnnouncement(
                dwarf_info.name .. " sent you a message! (Press Ctrl+T to view)",
                COLOR_LIGHTCYAN,
                false
            )
        else
            print("[NotificationDaemon] Failed to generate message")
            -- Remove from recent senders if failed
            recent_senders[dwarf_id] = nil
        end
    end)
end

-- ============================================================================
-- DAEMON LOOP
-- ============================================================================

function daemon.tick()
    if not running then return end
    
    local now = os.time()
    
    if now >= next_check_time then
        -- Time for check
        daemon.check_and_generate()
        
        -- Schedule next check
        local interval = config_manager.get_notification_interval()
        next_check_time = now + (interval * 60) -- Convert minutes to seconds
        
        print("[NotificationDaemon] Next check in " .. interval .. " minutes")
    end
    
    -- Schedule next tick (check every 10 seconds)
    dfhack.timeout(500, 'ticks', daemon.tick)
end

-- ============================================================================
-- START/STOP
-- ============================================================================

function daemon.start()
    if running then
        print("[NotificationDaemon] Already running")
        return
    end
    
    if not config_manager.is_notifications_enabled() then
        print("[NotificationDaemon] Notifications disabled in settings")
        return
    end
    
    running = true
    
    -- Schedule first check
    local interval = config_manager.get_notification_interval()
    next_check_time = os.time() + (interval * 60)
    
    print("[NotificationDaemon] Started (interval: " .. interval .. " minutes, chance: " .. config_manager.get_notification_chance() .. "%)")
    
    -- Start tick loop
    daemon.tick()
end

function daemon.stop()
    running = false
    print("[NotificationDaemon] Stopped")
end

function daemon.is_running()
    return running
end

-- ============================================================================
-- EXPORT
-- ============================================================================

return daemon