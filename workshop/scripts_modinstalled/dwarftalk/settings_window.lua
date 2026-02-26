--@module = true
--[=====[

dwarftalk/settings_window
=========================
Settings and configuration UI for DwarfTalk

]=====]

local gui = require('gui')
local widgets = require('gui.widgets')

-- Load config manager
local config_manager = require('config_manager')

-- ============================================================================
-- SettingsWindow
-- ============================================================================

SettingsWindow = defclass(SettingsWindow, gui.Screen)
SettingsWindow.ATTRS = {
    focus_path = 'dwarftalk_settings',
}

function SettingsWindow:init()
    -- Load current config
    local cfg = config_manager.load()
    
    -- Interval options
    self.interval_options = {1, 2, 3, 5, 10, 15, 20, 30}
    
    -- Find current interval index
    local current_interval = cfg.notification_interval_minutes or 5
    self.interval_index = 1
    for i, v in ipairs(self.interval_options) do
        if v == current_interval then
            self.interval_index = i
            break
        end
    end
    
    -- Chance options
    self.chance_options = {5, 10, 15, 20, 25, 30, 40, 50, 75, 100}
    
    -- Find current chance index
    local current_chance = cfg.notification_chance_percent or 20
    self.chance_index = 1
    for i, v in ipairs(self.chance_options) do
        if v == current_chance then
            self.chance_index = i
            break
        end
    end

    -- NPC interval options
    self.npc_interval_options = {5, 10, 15, 20, 30, 45, 60}

    -- Find current NPC interval index
    local current_npc_interval = cfg.npc_interval_minutes or 20
    self.npc_interval_index = 1
    for i, v in ipairs(self.npc_interval_options) do
        if v == current_npc_interval then
            self.npc_interval_index = i
            break
        end
    end
    
    print("[Settings] Loaded config - Interval: " .. current_interval .. "min, Chance: " .. current_chance .. "%")
    
    self:addviews{
        widgets.Window{
            view_id = 'main_window',
            frame = {w = 70, h = 45, l = 10, t = 3},
            frame_title = 'DwarfTalk Settings',
            resizable = true,
            resize_min = {w = 60, h = 28},
            subviews = {
                -- Custom Prompt section
                widgets.Label{
                    frame = {l = 1, t = 1},
                    text = {{text = 'Custom Prompt:', pen = COLOR_LIGHTCYAN}},
                },
                
                widgets.Label{
                    frame = {l = 1, t = 2},
                    text = 'This text will be added to every conversation prompt:',
                    text_pen = COLOR_GRAY,
                },
                
                widgets.TextArea{
                    view_id = 'custom_prompt',
                    frame = {l = 1, t = 3, r = 1, h = 8},
                },
                
                -- Separator
                widgets.Label{
                    frame = {l = 1, t = 12, r = 1, h = 1},
                    text = string.rep('-', 66),
                    text_pen = COLOR_DARKGRAY,
                },
                
                -- Notifications section
                widgets.Label{
                    frame = {l = 1, t = 14},
                    text = {{text = 'Notification System:', pen = COLOR_LIGHTCYAN}},
                },
                
                widgets.ToggleHotkeyLabel{
                    view_id = 'notifications_enabled',
                    frame = {l = 1, t = 15, w = 40},
                    label = 'Enable automatic messages',
                    on_activate = self:callback('toggle_notifications'),
                    initial_option = cfg.notifications_enabled,
                },
                
                -- Interval controls
                widgets.Label{
                    frame = {l = 1, t = 17},
                    text = 'Check interval:',
                    text_pen = COLOR_WHITE,
                },
                
                widgets.Label{
                    view_id = 'interval_display',
                    frame = {l = 18, t = 17},
                    text = {{text = self:get_interval_text(), pen = COLOR_LIGHTGREEN}},
                },
                
                widgets.Label{
                    frame = {l = 1, t = 18},
                    text = '(Click to adjust)',
                    text_pen = COLOR_GRAY,
                },
                
                widgets.Label{
                    view_id = 'interval_minus',
                    frame = {l = 18, t = 18, w = 5},
                    text = {{text = '< - ', pen = COLOR_LIGHTRED}},
                    on_click = self:callback('decrease_interval'),
                },
                
                widgets.Label{
                    view_id = 'interval_plus',
                    frame = {l = 24, t = 18, w = 5},
                    text = {{text = ' + >', pen = COLOR_LIGHTGREEN}},
                    on_click = self:callback('increase_interval'),
                },
                
                -- Chance controls
                widgets.Label{
                    frame = {l = 1, t = 20},
                    text = 'Message chance:',
                    text_pen = COLOR_WHITE,
                },
                
                widgets.Label{
                    view_id = 'chance_display',
                    frame = {l = 18, t = 20},
                    text = {{text = self:get_chance_text(), pen = COLOR_LIGHTGREEN}},
                },
                
                widgets.Label{
                    frame = {l = 1, t = 21},
                    text = '(Click to adjust)',
                    text_pen = COLOR_GRAY,
                },
                
                widgets.Label{
                    view_id = 'chance_minus',
                    frame = {l = 18, t = 21, w = 5},
                    text = {{text = '< - ', pen = COLOR_LIGHTRED}},
                    on_click = self:callback('decrease_chance'),
                },
                
                widgets.Label{
                    view_id = 'chance_plus',
                    frame = {l = 24, t = 21, w = 5},
                    text = {{text = ' + >', pen = COLOR_LIGHTGREEN}},
                    on_click = self:callback('increase_chance'),
                },
                
                -- Info
                widgets.Label{
                    frame = {l = 1, t = 23, r = 1},
                    text = {
                        {text = 'Info: ', pen = COLOR_YELLOW},
                        {text = 'Dwarves with urgent needs or high stress may send', pen = COLOR_GRAY},
                    },
                },
                
                widgets.Label{
                    frame = {l = 1, t = 24, r = 1},
                    text = {
                        {text = 'you messages at the configured interval.', pen = COLOR_GRAY},
                    },
                },
                
                -- Separator
                widgets.Label{
                    frame = {l = 1, t = 26, r = 1, h = 1},
                    text = string.rep('-', 66),
                    text_pen = COLOR_DARKGRAY,
                },

                -- NPC Conversations section
                widgets.Label{
                    frame = {l = 1, t = 28},
                    text = {{text = 'NPC Conversations:', pen = COLOR_LIGHTCYAN}},
                },

                widgets.ToggleHotkeyLabel{
                    view_id = 'npc_enabled',
                    frame = {l = 1, t = 29, w = 40},
                    label = 'Enable dwarf-to-dwarf chats',
                    on_activate = self:callback('toggle_npc'),
                    initial_option = cfg.npc_conversations_enabled,
                },

                -- NPC Interval controls
                widgets.Label{
                    frame = {l = 1, t = 31},
                    text = 'Chat interval:',
                    text_pen = COLOR_WHITE,
                },

                widgets.Label{
                    view_id = 'npc_interval_display',
                    frame = {l = 18, t = 31},
                    text = {{text = self:get_npc_interval_text(), pen = COLOR_LIGHTGREEN}},
                },

                widgets.Label{
                    frame = {l = 1, t = 32},
                    text = '(Click to adjust)',
                    text_pen = COLOR_GRAY,
                },

                widgets.Label{
                    view_id = 'npc_interval_minus',
                    frame = {l = 18, t = 32, w = 5},
                    text = {{text = '< - ', pen = COLOR_LIGHTRED}},
                    on_click = self:callback('decrease_npc_interval'),
                },

                widgets.Label{
                    view_id = 'npc_interval_plus',
                    frame = {l = 24, t = 32, w = 5},
                    text = {{text = ' + >', pen = COLOR_LIGHTGREEN}},
                    on_click = self:callback('increase_npc_interval'),
                },

                -- Info
                widgets.Label{
                    frame = {l = 1, t = 34, r = 1},
                    text = {
                        {text = 'Info: ', pen = COLOR_YELLOW},
                        {text = 'Nearby dwarves may chat with each other and have', pen = COLOR_GRAY},
                    },
                },

                widgets.Label{
                    frame = {l = 1, t = 35, r = 1},
                    text = {
                        {text = 'real effects on their moods and jobs.', pen = COLOR_GRAY},
                    },
                },

                -- Separator
                widgets.Label{
                    frame = {l = 1, t = 37, r = 1, h = 1},
                    text = string.rep('-', 66),
                    text_pen = COLOR_DARKGRAY,
                },
                
                widgets.HotkeyLabel{
                view_id = 'save_btn',
                frame = {l = 1, t = 39, w = 15},
                label = '[ Save ]',
                key = 'CUSTOM_S',
                on_activate = self:callback('save_settings'),
                auto_width = false,
                },

                widgets.HotkeyLabel{
                view_id = 'close_btn',
                frame = {l = 20, t = 39, w = 15},
                label = '[ Close ]',
                key = 'LEAVESCREEN',
                on_activate = self:callback('dismiss'),
                auto_width = false,
                },

                widgets.Label{
                view_id = 'status',
                frame = {l = 1, t = 41},
                text = {{text = 'S: Save | ESC: Close', pen = COLOR_GRAY}},
                },
            },
        },
    }

        -- Load custom prompt text after widget is initialized
    dfhack.timeout(1, 'frames', function()
        if self.subviews.custom_prompt then
            local existing_prompt = cfg.custom_prompt or ""
            if existing_prompt ~= "" then
                self.subviews.custom_prompt:setText(existing_prompt)
                print("[Settings] Loaded existing custom prompt: " .. #existing_prompt .. " chars")
            end
        end
    end)
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

function SettingsWindow:get_interval_text()
    local minutes = self.interval_options[self.interval_index]
    return minutes .. (minutes == 1 and ' minute' or ' minutes')
end

function SettingsWindow:get_chance_text()
    local percent = self.chance_options[self.chance_index]
    return percent .. '%'
end

function SettingsWindow:update_displays()
    self.subviews.interval_display:setText({{text = self:get_interval_text(), pen = COLOR_LIGHTGREEN}})
    self.subviews.chance_display:setText({{text = self:get_chance_text(), pen = COLOR_LIGHTGREEN}})
end

-- ============================================================================
-- INTERVAL CONTROLS
-- ============================================================================

function SettingsWindow:decrease_interval()
    if self.interval_index > 1 then
        self.interval_index = self.interval_index - 1
        self:update_displays()
        print("[Settings] Interval changed to: " .. self:get_interval_text())
    end
end

function SettingsWindow:increase_interval()
    if self.interval_index < #self.interval_options then
        self.interval_index = self.interval_index + 1
        self:update_displays()
        print("[Settings] Interval changed to: " .. self:get_interval_text())
    end
end

-- ============================================================================
-- CHANCE CONTROLS
-- ============================================================================

function SettingsWindow:decrease_chance()
    if self.chance_index > 1 then
        self.chance_index = self.chance_index - 1
        self:update_displays()
        print("[Settings] Chance changed to: " .. self:get_chance_text())
    end
end

function SettingsWindow:increase_chance()
    if self.chance_index < #self.chance_options then
        self.chance_index = self.chance_index + 1
        self:update_displays()
        print("[Settings] Chance changed to: " .. self:get_chance_text())
    end
end

-- ============================================================================
-- NPC INTERVAL CONTROLS
-- ============================================================================

function SettingsWindow:get_npc_interval_text()
    local minutes = self.npc_interval_options[self.npc_interval_index]
    return minutes .. (minutes == 1 and ' minute' or ' minutes')
end

function SettingsWindow:decrease_npc_interval()
    if self.npc_interval_index > 1 then
        self.npc_interval_index = self.npc_interval_index - 1
        self:update_npc_displays()
    end
end

function SettingsWindow:increase_npc_interval()
    if self.npc_interval_index < #self.npc_interval_options then
        self.npc_interval_index = self.npc_interval_index + 1
        self:update_npc_displays()
    end
end

function SettingsWindow:update_npc_displays()
    self.subviews.npc_interval_display:setText({{text = self:get_npc_interval_text(), pen = COLOR_LIGHTGREEN}})
end

function SettingsWindow:toggle_npc()
    -- Handled by widget
end

-- ============================================================================
-- TOGGLE
-- ============================================================================

function SettingsWindow:toggle_notifications()
    -- Handled by the widget itself
end

-- ============================================================================
-- SAVE & CLOSE
-- ============================================================================

-- ============================================================================
-- SAVE (WITHOUT CLOSING)
-- ============================================================================

function SettingsWindow:save_settings()
    print("[Settings] ========================================")
    print("[Settings] SAVING CONFIGURATION...")
    
    -- Get values
    local custom_prompt = self.subviews.custom_prompt:getText()
    local notifications_enabled = self.subviews.notifications_enabled:getOptionValue()
    local interval = self.interval_options[self.interval_index]
    local chance = self.chance_options[self.chance_index]
    
    -- NPC values
    local npc_enabled = self.subviews.npc_enabled:getOptionValue()
    local npc_interval = self.npc_interval_options[self.npc_interval_index]
    
    print("[Settings] - NPC Conversations: " .. tostring(npc_enabled))
    print("[Settings] - NPC Interval: " .. npc_interval .. " minutes")
    
    -- Load and modify config
    local cfg = config_manager.load()
    cfg.custom_prompt = custom_prompt
    cfg.notifications_enabled = notifications_enabled
    cfg.notification_interval_minutes = interval
    cfg.notification_chance_percent = chance
    cfg.npc_conversations_enabled = npc_enabled
    cfg.npc_interval_minutes = npc_interval
    
    -- Save
    local success = config_manager.save(cfg)
    
    if success then
        print("[Settings] ✓ Settings saved!")
        dfhack.gui.showAnnouncement("Settings saved!", COLOR_LIGHTGREEN, false)
        self.subviews.status:setText({{text = 'Settings saved! NPC monitor will update next cycle.', pen = COLOR_LIGHTGREEN}})
    else
        print("[Settings] ✗ Failed to save!")
        dfhack.gui.showAnnouncement("Failed to save!", COLOR_RED, false)
        self.subviews.status:setText({{text = 'Error saving!', pen = COLOR_RED}})
    end
    
    print("[Settings] ========================================")
end

function SettingsWindow:onDismiss()
    if self.on_close then
        self.on_close()
    end
end

function SettingsWindow:onInput(keys)
    if keys.LEAVESCREEN or keys._MOUSE_R then
        self:dismiss()
        return true
    end
    
    if self:inputToSubviews(keys) then
        return true
    end
    
    return false
end

-- ============================================================================
-- Launch function
-- ============================================================================

function show_settings()
    SettingsWindow{}:show()
end

return {
    SettingsWindow = SettingsWindow,
    show_settings = show_settings,
}