local daemon = require('notification_daemon')
local monitor = require('npc_conversation_monitor')
local config_manager = require('config_manager')

print("========================================")
print("DwarfTalk System Status")
print("========================================")

-- Daemon status (player notifications)
if daemon.is_running() then
    print("Notification Daemon: RUNNING")
else
    print("Notification Daemon: STOPPED")
end

-- NPC Monitor status
if monitor.enabled then
    print("NPC Monitor: RUNNING")
    print("NPC Check Interval: ~" .. math.floor(monitor.CHECK_INTERVAL / 60) .. " minutes")
else
    print("NPC Monitor: STOPPED")
end

-- Config
local cfg = config_manager.load()
print("========================================")
print("Configuration:")
print("----------------------------------------")
print("Player Notifications: " .. tostring(cfg.notifications_enabled))
print("  - Check Interval: " .. (cfg.notification_interval_minutes or 5) .. " minutes")
print("  - Message Chance: " .. (cfg.notification_chance_percent or 20) .. "%")
print("NPC Conversations: " .. tostring(cfg.npc_conversations_enabled))
print("  - NPC Interval: " .. (cfg.npc_interval_minutes or 20) .. " minutes")
print("========================================")