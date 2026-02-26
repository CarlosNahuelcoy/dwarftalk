--@module = true
--[=====[

dwarftalk/dwarf_prompt_editor
=============================
Edit custom prompt for a specific dwarf

]=====]

local gui = require('gui')
local widgets = require('gui.widgets')
local config_manager = require('config_manager')

-- ============================================================================
-- DwarfPromptEditor
-- ============================================================================

DwarfPromptEditor = defclass(DwarfPromptEditor, gui.Screen)
DwarfPromptEditor.ATTRS = {
    focus_path = 'dwarftalk_dwarf_prompt',
    dwarf_info = DEFAULT_NIL,
}

function DwarfPromptEditor:init()
    if not self.dwarf_info then
        self:dismiss()
        return
    end
    
    self:addviews{
        widgets.Window{
            view_id = 'main_window',
            frame = {w = 70, h = 25, l = 10, t = 5},
            frame_title = 'Custom Prompt: ' .. self.dwarf_info.name,
            resizable = true,
            resize_min = {w = 60, h = 20},
            subviews = {
                widgets.Label{
                    frame = {l = 1, t = 1},
                    text = {{text = 'Custom Prompt for ' .. self.dwarf_info.name .. ':', pen = COLOR_LIGHTCYAN}},
                },
                
                widgets.Label{
                    frame = {l = 1, t = 2},
                    text = 'This prompt will be added only to conversations with this dwarf:',
                    text_pen = COLOR_GRAY,
                },
                
                widgets.TextArea{
                    view_id = 'prompt_field',
                    frame = {l = 1, t = 3, r = 1, h = 12},
                },
                
                widgets.Panel{
                    frame = {l = 0, t = 16, r = 0, h = 1},
                    frame_background = COLOR_DARKGRAY,
                },
                
                widgets.HotkeyLabel{
                    view_id = 'save_btn',
                    frame = {l = 1, t = 18, w = 15},
                    label = 'Save',
                    key = 'SELECT',
                    on_activate = self:callback('save_prompt'),
                    auto_width = false,
                },
                
                widgets.HotkeyLabel{
                    view_id = 'clear_btn',
                    frame = {l = 18, t = 18, w = 15},
                    label = 'Clear',
                    key = 'CUSTOM_C',
                    on_activate = self:callback('clear_prompt'),
                    auto_width = false,
                },
                
                widgets.HotkeyLabel{
                    view_id = 'cancel_btn',
                    frame = {l = 35, t = 18, w = 15},
                    label = 'Cancel',
                    key = 'LEAVESCREEN',
                    on_activate = self:callback('dismiss'),
                    auto_width = false,
                },
                
                widgets.Label{
                    frame = {l = 1, t = 20},
                    text = {{text = 'Press Enter to save, C to clear, ESC to cancel', pen = COLOR_GRAY}},
                },
            },
        },
    }
    
    -- Cargar el texto existente después de que el widget esté inicializado
    dfhack.timeout(1, 'frames', function()
        if self.subviews.prompt_field then
            local existing_prompt = config_manager.get_dwarf_prompt(self.dwarf_info.id)
            if existing_prompt and existing_prompt ~= "" then
                self.subviews.prompt_field:setText(existing_prompt)
                print("[DwarfPromptEditor] Loaded existing prompt for " .. self.dwarf_info.name)
            end
        end
    end)
end

function DwarfPromptEditor:save_prompt()
    local prompt = self.subviews.prompt_field:getText()
    config_manager.set_dwarf_prompt(self.dwarf_info.id, prompt)
    
    print("[DwarfPromptEditor] Saved custom prompt for " .. self.dwarf_info.name)
    
    self:dismiss()
end

function DwarfPromptEditor:clear_prompt()
    config_manager.set_dwarf_prompt(self.dwarf_info.id, "")
    
    print("[DwarfPromptEditor] Cleared custom prompt for " .. self.dwarf_info.name)
    
    self:dismiss()
end

function DwarfPromptEditor:onInput(keys)
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

function show_editor(dwarf_info)
    DwarfPromptEditor{
        dwarf_info = dwarf_info,
    }:show()
end

return {
    DwarfPromptEditor = DwarfPromptEditor,
    show_editor = show_editor,
}