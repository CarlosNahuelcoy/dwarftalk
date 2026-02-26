--@module = true
--[=====[

dwarftalk/config_manager
========================
Manages DwarfTalk configuration and settings

]=====]

local json = nil
for _, lib in ipairs({'json', 'dkjson', 'cjson'}) do
    local success, result = pcall(require, lib)
    if success then
        json = result
        break
    end
end

local config = {}

local saves_dir = dfhack.getDFPath() .. '/dwarftalk_saves/'
local config_path = saves_dir .. 'config.json'

-- Default configuration
local DEFAULT_CONFIG = {
    -- Custom prompt
    custom_prompt = "",
    
    -- Notification system
    notifications_enabled = true,
    notification_interval_minutes = 5,
    notification_chance_percent = 20,
    -- NUEVO: Conversaciones NPC
    npc_conversations_enabled = true,
    npc_interval_minutes = 10,
    
    -- Per-dwarf settings (future)
    disabled_dwarves = {},
    
    -- Metadata
    version = "1.0",
    created_at = os.date("%Y-%m-%d %H:%M:%S"),
}

-- ============================================================================
-- LOAD CONFIG
-- ============================================================================

function config.load()
    if not json then
        print("[Config] JSON library not available, using defaults")
        return DEFAULT_CONFIG
    end
    
    local f = io.open(config_path, 'r')
    if not f then
        -- No config exists, create default
        print("[Config] No config found, creating default")
        config.save(DEFAULT_CONFIG)
        return DEFAULT_CONFIG
    end
    
    local json_data = f:read('*all')
    f:close()
    
    if not json_data or json_data == '' then
        return DEFAULT_CONFIG
    end
    
    local ok, loaded = pcall(json.decode, json_data)
    if not ok or not loaded then
        print("[Config] Failed to parse config, using defaults")
        return DEFAULT_CONFIG
    end
    
    -- Merge with defaults (in case new settings added)
    for key, value in pairs(DEFAULT_CONFIG) do
        if loaded[key] == nil then
            loaded[key] = value
        end
    end
    
    print("[Config] Loaded configuration")
    return loaded
end

-- ============================================================================
-- SAVE CONFIG
-- ============================================================================

function config.save(cfg)
    if not json then
        print("[Config] JSON library not available, cannot save")
        return false
    end
    
    cfg.updated_at = os.date("%Y-%m-%d %H:%M:%S")
    
    local json_data = json.encode(cfg)
    
    local f = io.open(config_path, 'w')
    if not f then
        print("[Config] Failed to save config")
        return false
    end
    
    f:write(json_data)
    f:close()
    
    print("[Config] Configuration saved")
    return true
end

-- ============================================================================
-- GETTERS
-- ============================================================================

function config.get_custom_prompt()
    local cfg = config.load()
    return cfg.custom_prompt or ""
end

function config.is_notifications_enabled()
    local cfg = config.load()
    return cfg.notifications_enabled
end

function config.get_notification_interval()
    local cfg = config.load()
    return cfg.notification_interval_minutes or 5
end

function config.get_notification_chance()
    local cfg = config.load()
    return cfg.notification_chance_percent or 20
end

function config.is_dwarf_enabled(dwarf_id)
    local cfg = config.load()
    local disabled = cfg.disabled_dwarves or {}
    
    for _, id in ipairs(disabled) do
        if id == dwarf_id then
            return false
        end
    end
    
    return true
end

-- ============================================================================
-- SETTERS
-- ============================================================================

function config.set_custom_prompt(prompt)
    local cfg = config.load()
    cfg.custom_prompt = prompt
    config.save(cfg)
end

function config.set_notifications_enabled(enabled)
    local cfg = config.load()
    cfg.notifications_enabled = enabled
    config.save(cfg)
end

function config.set_notification_interval(minutes)
    local cfg = config.load()
    cfg.notification_interval_minutes = minutes
    config.save(cfg)
end

function config.set_notification_chance(percent)
    local cfg = config.load()
    cfg.notification_chance_percent = percent
    config.save(cfg)
end

-- ============================================================================
-- PER-DWARF CUSTOM PROMPTS
-- ============================================================================

function config.get_dwarf_prompt(dwarf_id)
    local cfg = config.load()
    local dwarf_prompts = cfg.dwarf_prompts or {}
    
    local id_str = tostring(dwarf_id)
    return dwarf_prompts[id_str] or ""
end

function config.set_dwarf_prompt(dwarf_id, prompt)
    local cfg = config.load()
    
    if not cfg.dwarf_prompts then
        cfg.dwarf_prompts = {}
    end
    
    local id_str = tostring(dwarf_id)
    cfg.dwarf_prompts[id_str] = prompt
    
    config.save(cfg)
end

function config.has_dwarf_prompt(dwarf_id)
    local prompt = config.get_dwarf_prompt(dwarf_id)
    return prompt and prompt ~= ""
end

-- ============================================================================
-- EXPORT
-- ============================================================================

return config