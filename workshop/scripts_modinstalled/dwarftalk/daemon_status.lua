-- Show daemon status
local daemon = require('notification_daemon')
local config_manager = require('config_manager')

print("===========================================")
print("  DWARFTALK NOTIFICATION DAEMON STATUS")
print("===========================================")
print("")

if daemon.is_running() then
    print("Status: RUNNING")
    
    local interval = config_manager.get_notification_interval()
    local chance = config_manager.get_notification_chance()
    
    print("Interval: " .. interval .. " minutes")
    print("Chance: " .. chance .. "%")
else
    print("Status: STOPPED")
    
    if not config_manager.is_notifications_enabled() then
        print("Reason: Notifications disabled in settings")
    elseif not dfhack.isWorldLoaded() then
        print("Reason: No world loaded")
    else
        print("Reason: Not started")
    end
end

print("")
print("Commands:")
print("  dwarftalk/start_daemon  - Start manually")
print("  dwarftalk/stop_daemon   - Stop daemon")
print("===========================================")