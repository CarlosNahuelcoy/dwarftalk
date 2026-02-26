--@module = true
--[=====[

dwarftalk/autostart_check
=========================
Periodic check to auto-start daemon if needed

]=====]

-- Only check if world is loaded
if not dfhack.isWorldLoaded() then
    return
end

-- Load modules
local config_ok, config_manager = pcall(require, 'config_manager')
if not config_ok then return end

local daemon_ok, daemon = pcall(require, 'notification_daemon')
if not daemon_ok then return end

-- Check if should be running but isn't
local should_run = config_manager.is_notifications_enabled()
local is_running = daemon.is_running()

if should_run and not is_running then
    -- Start daemon
    print("[DwarfTalk] Auto-starting notification daemon...")
    daemon.start()
end