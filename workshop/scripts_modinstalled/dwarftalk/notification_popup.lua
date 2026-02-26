--@module = true
--[=====[

dwarftalk/notification_popup
============================
Shows notification popup when a dwarf wants to talk

]=====]

local gui = require('gui')
local widgets = require('gui.widgets')

local message_system = require('message_system')
local logger = require('logger')

-- ============================================================================
-- NotificationPopup
-- ============================================================================

NotificationPopup = defclass(NotificationPopup, gui.Screen)
NotificationPopup.ATTRS = {
    focus_path = 'dwarftalk_notification',
    message_data = DEFAULT_NIL,
}

function NotificationPopup:init()
    if not self.message_data then
        self:dismiss()
        return
    end
    
    local msg = self.message_data
    
    -- Wrap message text
    local wrapped_message = self:wrap_text(msg.message, 50)
    
    self:addviews{
        widgets.Window{
            view_id = 'main_window',
            frame = {w = 60, h = 20, l = 20, t = 8},
            frame_title = 'New Message',
            frame_style = gui.GREY_LINE_FRAME,
            subviews = {
                -- Header
                widgets.Label{
                    frame = {l = 1, t = 1},
                    text = {
                        {text = msg.dwarf_name, pen = COLOR_LIGHTCYAN},
                        {text = ' sent you a message:', pen = COLOR_WHITE},
                    },
                },
                
                -- Separator
                widgets.Label{
                    frame = {l = 1, t = 2, r = 1, h = 1},
                    text = string.rep('-', 56),
                    text_pen = COLOR_DARKGRAY,
                },
                
                -- Message content
                widgets.Label{
                    frame = {l = 2, t = 4, r = 2, h = 6},
                    text = {{text = '"' .. wrapped_message .. '"', pen = COLOR_YELLOW}},
                    text_wrap = true,
                },
                
                -- Info
                widgets.Label{
                    frame = {l = 2, t = 11},
                    text = {
                        {text = 'This message has been saved to your chat history.', pen = COLOR_GRAY},
                    },
                },
                
                -- Separator
                widgets.Label{
                    frame = {l = 1, t = 13, r = 1, h = 1},
                    text = string.rep('-', 56),
                    text_pen = COLOR_DARKGRAY,
                },
                
                -- Reply button
                widgets.HotkeyLabel{
                    view_id = 'reply_btn',
                    frame = {l = 2, t = 15, w = 15},
                    label = '[ Reply ]',
                    key = 'SELECT',
                    on_activate = self:callback('open_chat_with_dwarf'),
                    auto_width = false,
                },
                
                -- Dismiss button
                widgets.HotkeyLabel{
                    view_id = 'dismiss_btn',
                    frame = {l = 20, t = 15, w = 15},
                    label = '[ Dismiss ]',
                    key = 'CUSTOM_D',
                    on_activate = self:callback('close_notification'),
                    auto_width = false,
                },
                
                -- Help text
                widgets.Label{
                    frame = {l = 2, t = 17},
                    text = {
                        {text = 'Enter', pen = COLOR_LIGHTGREEN},
                        {text = ': Reply  ', pen = COLOR_GRAY},
                        {text = 'D', pen = COLOR_WHITE},
                        {text = ': Dismiss  ', pen = COLOR_GRAY},
                        {text = 'ESC', pen = COLOR_LIGHTRED},
                        {text = ': Close', pen = COLOR_GRAY},
                    },
                },
            },
        },
    }
end

function NotificationPopup:wrap_text(text, max_width)
    local lines = {}
    local current_line = ""
    
    for word in text:gmatch("%S+") do
        local test_line = current_line == "" and word or current_line .. " " .. word
        
        if #test_line <= max_width then
            current_line = test_line
        else
            if current_line ~= "" then
                table.insert(lines, current_line)
            end
            current_line = word
        end
    end
    
    if current_line ~= "" then
        table.insert(lines, current_line)
    end
    
    return table.concat(lines, '\n')
end

function NotificationPopup:open_chat_with_dwarf()
    logger.log("========================================")
    logger.log("REPLY BUTTON PRESSED!")
    
    local msg = self.message_data
    logger.log("Dwarf ID: " .. tostring(msg.dwarf_id))
    logger.log("Dwarf name: " .. tostring(msg.dwarf_name))
    
    -- Remove message from pending
    message_system.remove_message(msg.dwarf_id)
    logger.log("Message removed from pending")
    
    -- Close this popup
    logger.log("Closing popup...")
    self:dismiss()
    
    -- Open chat using dfhack.run_script (more reliable)
    logger.log("Opening chat via script...")
    dfhack.timeout(5, 'frames', function()
        logger.log("Running dwarftalk/chat_window...")
        
        -- Store dwarf ID and message in global for the script to pick up
        _G.dwarftalk_pending_chat = {
            dwarf_id = msg.dwarf_id,
            initial_message = msg.message,
        }
        
        dfhack.run_script('dwarftalk/chat_window')
        
        logger.log("✓ Chat script executed")
    end)
    
    logger.log("========================================")
end

function NotificationPopup:close_notification()
    local msg = self.message_data
    
    -- Remove message from pending
    message_system.remove_message(msg.dwarf_id)
    
    print("[Notification] Dismissed message from " .. msg.dwarf_name)
    
    self:dismiss()
end

function NotificationPopup:onDismiss()
    -- Check if there are more messages
    local next_msg = message_system.get_next_message()
    
    if next_msg then
        -- Show next message after short delay
        dfhack.timeout(10, 'frames', function()
            show_notification()
        end)
    end
end

function NotificationPopup:onInput(keys)
    if keys.LEAVESCREEN or keys._MOUSE_R then
        self:close_notification()
        return true
    end
    
    if self:inputToSubviews(keys) then
        return true
    end
    
    return false
end

-- ============================================================================
-- Show notification function
-- ============================================================================

function show_notification()
    local msg = message_system.get_next_message()
    
    if not msg then
        print("[Notification] No pending messages")
        return
    end
    
    NotificationPopup{
        message_data = msg,
    }:show()
end

-- ============================================================================
-- Export
-- ============================================================================

return {
    NotificationPopup = NotificationPopup,
    show_notification = show_notification,
}