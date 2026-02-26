-- Quick check to auto-start daemon if needed

-- Check if world is loaded
if not dfhack.isWorldLoaded() then 
    return 
end

-- Try to load config
local config_ok, config = pcall(require, 'config_manager')
if not config_ok then 
    print("[DaemonCheck] Could not load config_manager: " .. tostring(config))
    return 
end

-- Check if notifications enabled
if not config.is_notifications_enabled() then 
    return 
end

-- Try to load daemon
local daemon_ok, daemon = pcall(require, 'notification_daemon')
if not daemon_ok then 
    print("[DaemonCheck] Could not load daemon: " .. tostring(daemon))
    return 
end

-- Start if not running
if not daemon.is_running() then
    print("[DaemonCheck] Starting daemon...")
    daemon.start()
end