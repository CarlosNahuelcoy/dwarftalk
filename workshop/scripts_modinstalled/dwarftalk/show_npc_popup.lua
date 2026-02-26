local gui = require('gui')
local widgets = require('gui.widgets')

NPCPopup = defclass(NPCPopup, gui.Screen)
NPCPopup.ATTRS = {
    focus_path = 'dwarftalk_npc_popup',
}

function NPCPopup:init()
    local pending = _G.dwarftalk_pending_npc_conversation
    if not pending then
        print("[NPCPopup] No pending conversation")
        self:dismiss()
        return
    end
    
    print("[NPCPopup] Showing: " .. pending.name1 .. " & " .. pending.name2)
    
    -- Formatear diálogo
    local content = pending.dialogue or "..."
    
    -- Agregar efectos
    if pending.effect1 then
        content = content .. '\n\n~ ' .. pending.effect1
    end
    
    if pending.effect2 then
        content = content .. '\n\n~ ' .. pending.effect2
    end
    
    self:addviews{
        widgets.Window{
            frame = {w = 70, h = 30},
            frame_title = 'Conversation: ' .. pending.name1 .. ' & ' .. pending.name2,
            resizable = true,
            subviews = {
                widgets.Label{
                    frame = {l = 1, t = 1, r = 1, b = 3},
                    text = content,
                    text_pen = COLOR_WHITE,
                    auto_height = false,
                    text_wrap = true,
                },
                widgets.HotkeyLabel{
                    frame = {l = 1, b = 0},
                    label = 'Close',
                    key = 'LEAVESCREEN',
                    on_activate = self:callback('dismiss'),
                },
            }
        }
    }
end

function NPCPopup:onInput(keys)
    if keys.LEAVESCREEN or keys._MOUSE_R or keys.SELECT then
        self:dismiss()
        return true
    end
    
    return self:inputToSubviews(keys)
end

NPCPopup{}:show()