--@module = true

-- Auto-retry if world not loaded
if not dfhack.isWorldLoaded() then
    print("[DwarfTalk] Waiting for world to load...")
    dfhack.timeout(10, 'frames', function()
        dfhack.run_command('dwarftalk/init')
    end)
    return
end

print("[DwarfTalk] ========================================")
print("[DwarfTalk] Initializing DwarfTalk systems...")

-- Load config
local config_manager = require('config_manager')
local cfg = config_manager.load()

-- ============================================================================
-- 1. NOTIFICATION DAEMON (Player notifications)
-- ============================================================================

if cfg.notifications_enabled then
    local daemon = require('notification_daemon')
    
    if daemon.is_running() then
        print("[DwarfTalk] Notification daemon already running")
    else
        print("[DwarfTalk] Starting notification daemon...")
        daemon.start()
        print("[DwarfTalk] ✓ Daemon started (" .. cfg.notification_interval_minutes .. "min, " .. cfg.notification_chance_percent .. "%)")
    end
else
    print("[DwarfTalk] Notification daemon disabled in settings")
end

-- ============================================================================
-- 2. NPC CONVERSATION MONITOR
-- ============================================================================

if cfg.npc_conversations_enabled then
    local monitor = require('npc_conversation_monitor')
    
    if monitor.enabled then
        print("[DwarfTalk] NPC monitor already running")
    else
        print("[DwarfTalk] Starting NPC conversation monitor...")
        monitor.start()
        print("[DwarfTalk] ✓ NPC monitor started (" .. cfg.npc_interval_minutes .. "min)")
    end
else
    print("[DwarfTalk] NPC conversations disabled in settings")
end

print("[DwarfTalk] ✓ Initialization complete")
print("[DwarfTalk] ========================================")