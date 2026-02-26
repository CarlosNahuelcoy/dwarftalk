--@module = true
--[=====[

dwarftalk/auto_daemon
====================
Auto-start notification daemon when a world is loaded

]=====]

local eventful = require('plugins.eventful')
local config_manager = require('config_manager')

local auto_daemon = {}

local daemon_started = false

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

function auto_daemon.on_world_loaded()
    -- Check if notifications are enabled
    if not config_manager.is_notifications_enabled() then
        print("[DwarfTalk] Notifications disabled, daemon not started")
        return
    end
    
    -- Start daemon
    local daemon = require('notification_daemon')
    
    if not daemon.is_running() then
        print("[DwarfTalk] Auto-starting notification daemon...")
        daemon.start()
        daemon_started = true
    end
end

function auto_daemon.on_world_unloaded()
    -- Stop daemon when world unloads
    local daemon = require('notification_daemon')
    
    if daemon.is_running() then
        print("[DwarfTalk] Stopping notification daemon...")
        daemon.stop()
        daemon_started = false
    end
end

-- ============================================================================
-- SETUP
-- ============================================================================

function auto_daemon.setup()
    -- Register event callbacks
    eventful.onLoadWorld.dwarftalk = auto_daemon.on_world_loaded
    eventful.onUnloadWorld.dwarftalk = auto_daemon.on_world_unloaded
    
    print("[DwarfTalk] Auto-daemon setup complete")
    
    -- If a world is already loaded, start now
    if dfhack.isWorldLoaded() then
        auto_daemon.on_world_loaded()
    end
end

function auto_daemon.cleanup()
    -- Unregister callbacks
    eventful.onLoadWorld.dwarftalk = nil
    eventful.onUnloadWorld.dwarftalk = nil
    
    print("[DwarfTalk] Auto-daemon disabled")
end

-- ============================================================================
-- EXPORT
-- ============================================================================

return auto_daemon