-- Ventana de historial de conversaciones NPC
local gui = require('gui')
local widgets = require('gui.widgets')
local conversations = require('dwarf_conversations')

NPCHistoryWindow = defclass(NPCHistoryWindow, gui.Screen)
NPCHistoryWindow.ATTRS = {
    focus_path = 'dwarftalk_npc_history',
}

function NPCHistoryWindow:init()
    local history = conversations.load_history()
    
    local choices = {}
    
    for i, conv in ipairs(history) do
    -- Calcular tiempo
    local elapsed = os.time() - conv.timestamp
    local time_str = ""
    
    if elapsed < 60 then
        time_str = "Just now"
    elseif elapsed < 3600 then
        time_str = math.floor(elapsed / 60) .. "m ago"
    elseif elapsed < 86400 then
        time_str = math.floor(elapsed / 3600) .. "h ago"
    else
        time_str = math.floor(elapsed / 86400) .. "d ago"
    end
    
    -- TEXTO SIMPLE - UNA SOLA LÍNEA
    local text = string.format('[%s] %s & %s', time_str, conv.name1, conv.name2)
    
    table.insert(choices, {
        text = text,
        conv = conv
    })
    end
    
    if #choices == 0 then
        table.insert(choices, {
            text = 'No conversations yet...',
            conv = nil
        })
    end
    
    self:addviews{
        widgets.Window{
            frame = {w = 80, h = 40},  -- Más ancho: 70 → 80, más alto: 35 → 40
            frame_title = 'Fortress Conversations (Last 100)',
            resizable = true,
            subviews = {
                widgets.List{
                view_id = 'history_list',
                frame = {l = 1, t = 1, r = 1, b = 3},
                choices = choices,
                on_submit = self:callback('view_conversation'),
                cursor_pen = COLOR_YELLOW,
                text_pen = COLOR_WHITE,
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

function NPCHistoryWindow:view_conversation(idx, choice)
    if not choice or not choice.conv then 
        print("[NPCHistory] No conversation in choice")
        return 
    end
    
    print("[NPCHistory] Viewing conversation: " .. choice.conv.name1 .. " & " .. choice.conv.name2)
    
    -- Mostrar conversación completa
    _G.dwarftalk_pending_npc_conversation = {
        name1 = choice.conv.name1,
        name2 = choice.conv.name2,
        dialogue = choice.conv.dialogue,
        effect1 = choice.conv.effects and choice.conv.effects.effect1,
        effect2 = choice.conv.effects and choice.conv.effects.effect2
    }
    
    dfhack.run_command('dwarftalk/show_npc_popup')
end

function NPCHistoryWindow:onInput(keys)
    if keys.LEAVESCREEN or keys._MOUSE_R then
        self:dismiss()
        return true
    end
    
    return self:inputToSubviews(keys)
end

function show_npc_history()
    NPCHistoryWindow{}:show()
end

if not dfhack_flags.module then
    show_npc_history()
else
    return {show_history = show_npc_history}
end