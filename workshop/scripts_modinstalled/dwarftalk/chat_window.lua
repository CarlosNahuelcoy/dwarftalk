--@module = true
--[=====[

dwarftalk/chat_window
=====================
Beautiful chat interface for talking with dwarves with deep personality analysis

Usage::

    dwarftalk/chat_window
    dwarftalk/chat_window quick

]=====]

local gui = require('gui')
local widgets = require('gui.widgets')

-- Try to load Player2 API module
local player2_api = nil
local api_load_error = nil

-- Add scripts directory to Lua path
local scripts_path = dfhack.getHackPath() .. '/scripts/dwarftalk/'
package.path = package.path .. ';' .. scripts_path .. '?.lua'

local logger = require('debug_logger')

local success, result = pcall(function()
    return require('player2_api')
end)

if success then
    player2_api = result
    print("[DwarfTalk] Player2 API module loaded successfully")
else
    api_load_error = tostring(result)
    print("[DwarfTalk] ERROR loading player2_api: " .. api_load_error)
end

-- Load analyzer module
local analyzer = nil
local analyzer_success, analyzer_result = pcall(function()
    return require('analyze_dwarf')
end)

if analyzer_success then
    analyzer = analyzer_result
    print("[DwarfTalk] Dwarf analyzer loaded successfully")
else
    print("[DwarfTalk] WARNING: Analyzer not loaded: " .. tostring(analyzer_result))
end

-- Load fortress context module
local fortress_context = nil
local context_success, context_result = pcall(function()
    return require('fortress_context')
end)

if context_success then
    fortress_context = context_result
    print("[DwarfTalk] Fortress context module loaded successfully")
else
    print("[DwarfTalk] WARNING: Fortress context not loaded: " .. tostring(context_result))
end

-- Load config manager module
local config_manager = nil
local config_success, config_result = pcall(function()
    return require('config_manager')
end)

if config_success then
    config_manager = config_result
    print("[DwarfTalk] Config manager loaded successfully")
else
    print("[DwarfTalk] WARNING: Config manager not loaded: " .. tostring(config_result))
end

-- Load action engine module
local action_engine = nil
local action_success, action_result = pcall(function()
    return require('action_engine')
end)

if action_success then
    action_engine = action_result
    print("[DwarfTalk] Action engine loaded successfully")
else
    print("[DwarfTalk] WARNING: Action engine not loaded: " .. tostring(action_result))
end

-- Load settings module
local settings_window = nil
pcall(function()
    settings_window = require('settings_window')
end)

-- ============================================================================
-- PERSISTENCE MODULE - Save/Load conversations
-- ============================================================================

local persistence = require('persistence')

-- ============================================================================
-- DWARF DATA MODULE
-- ============================================================================

local dwarf_data = {}

function dwarf_data.get_fortress_dwarves()
    local dwarves = {}
    
    for _, unit in ipairs(df.global.world.units.active) do
        if dfhack.units.isCitizen(unit) and not dfhack.units.isDead(unit) then
            local dwarf_info = dwarf_data.get_dwarf_info(unit)
            if dwarf_info then
                table.insert(dwarves, dwarf_info)
            end
        end
    end
    
    return dwarves
end

function dwarf_data.get_dwarf_info(unit)
    if not unit then return nil end
    
    local name = ''
    if unit.name.has_name then
        if unit.name.first_name ~= '' then
            name = unit.name.first_name
        end
        if unit.name.nickname ~= '' then
            if name ~= '' then name = name .. ' "' else name = '"' end
            name = name .. unit.name.nickname .. '"'
        end
    end
    
    if name == '' then
        name = 'Unnamed Dwarf #' .. tostring(unit.id)
    end
    
    local profession = dfhack.units.getProfessionName(unit)
    if not profession or profession == '' then
        profession = 'No profession'
    end
    
    local dwarf_info = {
        id = unit.id,
        name = name,
        profession = profession,
        unit = unit,
    }
    
    return dwarf_info
end

-- ============================================================================
-- ADVANCED PROMPT BUILDER - Using deep analysis + world context
-- ============================================================================

local prompt_builder = {}

function prompt_builder.build_system_prompt(dwarf_info, analysis)
    local prompt = "You are " .. dwarf_info.name .. ", a dwarf living in a fortress in Dwarf Fortress.\n\n"
    
    -- WORLD CONTEXT
    if fortress_context then
        local ok, ctx = pcall(fortress_context.get_fortress_context)
        
        if ok and ctx then
            local ok2, ctx_text = pcall(fortress_context.context_to_text, ctx)
            
            if ok2 and ctx_text then
                prompt = prompt .. ctx_text .. "\n\n"
                prompt = prompt .. "IMPORTANT: You are aware of these fortress events and conditions.\n"
                prompt = prompt .. "You may naturally reference them in conversation if relevant.\n"
                prompt = prompt .. "React appropriately to deaths, threats, or major changes.\n\n"
            end
        end
    end
    
    -- Basic info
    prompt = prompt .. "YOUR PERSONAL INFO:\n"
    prompt = prompt .. "- Name: " .. dwarf_info.name .. "\n"
    prompt = prompt .. "- Profession: " .. dwarf_info.profession .. "\n"
    
    if analysis then
        if analysis.age then
            prompt = prompt .. "- Age: " .. math.floor(analysis.age) .. " years old\n"
        end
        if analysis.sex then
            prompt = prompt .. "- Sex: " .. analysis.sex .. "\n"
        end
    end
    
    prompt = prompt .. "\n"
    
    -- Personality
    if analysis and analysis.personality then
        prompt = prompt .. "YOUR PERSONALITY:\n"
        
        if analysis.personality.narrative_description and #analysis.personality.narrative_description > 0 then
            for _, desc in ipairs(analysis.personality.narrative_description) do
                prompt = prompt .. "- You " .. desc .. "\n"
            end
        end
        
        if analysis.personality.personality_summary and analysis.personality.personality_summary ~= "" then
            prompt = prompt .. "- Overall: " .. analysis.personality.personality_summary .. "\n"
        end
        
        prompt = prompt .. "\n"
    end
    
    -- Skills
    if analysis and analysis.skills and #analysis.skills > 0 then
        prompt = prompt .. "YOUR TOP SKILLS:\n"
        for i = 1, math.min(5, #analysis.skills) do
            local skill = analysis.skills[i]
            prompt = prompt .. "- " .. skill.name .. " (level " .. skill.level .. ")\n"
        end
        prompt = prompt .. "\n"
    end
    
    -- Current needs
    if analysis and analysis.needs and #analysis.needs > 0 then
        prompt = prompt .. "YOUR CURRENT NEEDS (affect your mood and conversation):\n"
        
        local has_urgent_needs = false
        for _, need in ipairs(analysis.needs) do
            if need.level >= 5 then
                local need_desc = need.type:gsub("([A-Z])", " %1"):lower():gsub("^ ", "")
                prompt = prompt .. "- URGENT: You need to " .. need_desc .. " (level " .. need.level .. "/10)\n"
                has_urgent_needs = true
            end
        end
        
        if has_urgent_needs then
            prompt = prompt .. "\n"
        end
    end
    
    -- Values
    if analysis and analysis.values and analysis.values.cultural_descriptions and #analysis.values.cultural_descriptions > 0 then
        prompt = prompt .. "YOUR VALUES AND BELIEFS:\n"
        for i = 1, math.min(5, #analysis.values.cultural_descriptions) do
            prompt = prompt .. "- " .. analysis.values.cultural_descriptions[i] .. "\n"
        end
        prompt = prompt .. "\n"
    end
    
    -- Current state
    if analysis and analysis.current_state then
        local state = analysis.current_state
        prompt = prompt .. "YOUR CURRENT STATE:\n"
        
        if state.current_job and state.current_job ~= "idle" then
            prompt = prompt .. "- Currently: " .. state.current_job:lower():gsub("_", " ") .. "\n"
        else
            prompt = prompt .. "- Currently idle\n"
        end
        
        if state.stress_level and state.stress_level > 100000 then
            prompt = prompt .. "- Feeling stressed\n"
        end
        
        prompt = prompt .. "\n"
    end
    
    -- CUSTOM PROMPT PER DWARF
    if config_manager then
        local dwarf_prompt = config_manager.get_dwarf_prompt(dwarf_info.id)
        if dwarf_prompt and dwarf_prompt ~= "" then
            prompt = prompt .. "ADDITIONAL CONTEXT (from overseer):\n"
            prompt = prompt .. dwarf_prompt .. "\n\n"
        end
    end
    
    -- GLOBAL CUSTOM PROMPT
    if config_manager then
        local global_prompt = config_manager.get_custom_prompt()
        if global_prompt and global_prompt ~= "" then
            prompt = prompt .. "GENERAL INSTRUCTIONS (from overseer):\n"
            prompt = prompt .. global_prompt .. "\n\n"
        end
    end
    
    -- Instructions
    prompt = prompt .. "CONVERSATION GUIDELINES:\n"
    prompt = prompt .. "- Speak in first person as this dwarf\n"
    prompt = prompt .. "- Use direct dialogue only - NO action descriptions, asterisks, or parenthetical actions\n"
    prompt = prompt .. "- Your personality should strongly influence how you speak and what you say\n"
    prompt = prompt .. "- You may naturally reference fortress events (deaths, threats, visitors) when relevant\n"
    prompt = prompt .. "- If you have urgent needs, you may mention them naturally in conversation\n"
    prompt = prompt .. "- React appropriately to the fortress context (be somber after deaths, nervous during sieges, etc.)\n"
    prompt = prompt .. "- Stay in character - be authentic to dwarven culture and YOUR specific personality\n"
    prompt = prompt .. "- Keep responses relatively brief (2-4 sentences usually)\n"
    prompt = prompt .. "- Show your personality through your words, tone, and what you choose to discuss\n"
    prompt = prompt .. "- Be conversational and natural - you're talking to another dwarf in the fortress\n"
    prompt = prompt .. "- IMPORTANT: Write ONLY dialogue, as if you're speaking directly. No narration or stage directions.\n"
    prompt = prompt .. "\n"
    
	-- ACTION SYSTEM (NUEVO - JSON OBLIGATORIO)
    prompt = prompt .. "\n**CRITICAL RESPONSE FORMAT**:\n"
    prompt = prompt .. "You MUST respond ONLY in this JSON format:\n"
    prompt = prompt .. '{\n'
    prompt = prompt .. '  "dialogue": "your response here",\n'
    prompt = prompt .. '  "action": {"type": "adjust_mood", "amount": 1}\n'
    prompt = prompt .. '}\n\n'

    prompt = prompt .. "Action types:\n"
    prompt = prompt .. "- adjust_mood: amount -3 to +3\n"
    prompt = prompt .. "  * Use POSITIVE (+1 to +3) when player is: encouraging, thanking, complimenting, helping\n"
    prompt = prompt .. "  * Use NEGATIVE (-1 to -3) when player is: rude, dismissive, demanding, insensitive\n"
    prompt = prompt .. "  * Match the action to the INTENT of the player's words\n"
    prompt = prompt .. "- change_job: job=\"miner|cook|mason|carpenter|farmer|brewer|smith\"\n"
    prompt = prompt .. "- refuse_work: reason=\"...\" (only if EXTREMELY stressed and provoked)\n"
    prompt = prompt .. "- create_work_order: item=\"bed\", quantity=5\n"
    prompt = prompt .. "- assign_military: (when agreeing to join military)\n\n"

    prompt = prompt .. "ALWAYS include both dialogue AND action. No exceptions.\n"
    prompt = prompt .. "Your dialogue can show stress/personality, but the ACTION should reflect the player's intent.\n"
    prompt = prompt .. "Example response:\n"
    prompt = prompt .. '{"dialogue": "Thanks... I suppose.", "action": {"type": "adjust_mood", "amount": 1}}\n\n'

	return prompt
end



-- ============================================================================
-- ChatWindow - Main window
-- ============================================================================

ChatWindow = defclass(ChatWindow, gui.Screen)
ChatWindow.ATTRS = {
    focus_path = 'dwarftalk_chat',
    preselected_dwarf = DEFAULT_NIL,
    initial_message = DEFAULT_NIL, 
}

function ChatWindow:init()
    self.selected_dwarf = self.preselected_dwarf
    self.dwarf_analysis = nil
    self.chat_messages = {}
    self.conversation_history = {}
    
    self:addviews{
        widgets.Window{
            view_id = 'main_window',
            frame = {w = 85, h = 35, l = 5, t = 3},
            frame_title = 'DwarfTalk - Chat with Dwarves',
            resizable = true,
            resize_min = {w = 60, h = 25},
            subviews = {
                -- Left panel: Dwarf list
                widgets.Panel{
                    view_id = 'left_panel',
                    frame = {l = 0, t = 0, w = 28, b = 0},
                    frame_style = gui.GREY_LINE_FRAME,
                    frame_title = 'Your Dwarves',
                },
                
                widgets.List{
                    view_id = 'dwarf_list',
                    frame = {l = 1, t = 2, w = 26, b = 2},
                    on_select = self:callback('on_select_dwarf'),
                    on_submit = self:callback('on_select_dwarf'),
                    cursor_pen = COLOR_YELLOW,
                },
				
				widgets.HotkeyLabel{
                    view_id = 'settings_btn',
                    frame = {l = 1, b = 2, w = 26},
                    label = 'Settings',
                    key = 'CUSTOM_SHIFT_S',
                    on_activate = self:callback('open_settings'),
                    auto_width = false,
                },

                widgets.HotkeyLabel{
                view_id = 'npc_history_btn',
                frame = {l = 1, b = 6, w = 26},  -- Justo arriba de Event History
                label = 'NPC Chats',
                key = 'CUSTOM_N',
                on_activate = self:callback('open_npc_history'),
                auto_width = false,
                },
                
                widgets.HotkeyLabel{
                    view_id = 'refresh_btn',
                    frame = {l = 1, b = 0, w = 26},
                    label = 'Refresh',
                    key = 'CUSTOM_R',
                    on_activate = self:callback('refresh_dwarf_list'),
                    auto_width = false,
                },
                
                -- Right panel: Chat
                widgets.Panel{
                    view_id = 'right_panel',
                    frame = {l = 29, t = 0, r = 0, b = 0},
                    frame_style = gui.GREY_LINE_FRAME,
                    frame_title = 'Conversation',
                },
                
                -- Dwarf info (ONE LINE ONLY)
                widgets.Label{
                    view_id = 'dwarf_info',
                    frame = {l = 30, t = 1, r = 1, h = 1},
                    text = 'Select a dwarf from the list...',
                    text_pen = COLOR_GRAY,
                },
                
                -- SEPARATOR
                widgets.Label{
                    frame = {l = 30, t = 2, r = 1, h = 1},
                    text = string.rep('-', 50),
                    text_pen = COLOR_DARKGRAY,
                },
                
                -- CHAT HISTORY
                widgets.Label{
                    view_id = 'chat_history',
                    frame = {l = 30, t = 3, r = 1, h = 22},
                    text = '',
                    text_pen = COLOR_WHITE,
                    auto_height = false,
                    text_wrap = true,
                },
                
                -- Separator above input
                widgets.Label{
                    frame = {l = 30, b = 5, r = 1},
                    text = string.rep('-', 50),
                    text_pen = COLOR_DARKGRAY,
                },
                
                -- Input area
                widgets.Label{
                    frame = {l = 30, b = 4},
                    text = {{text = 'You: ', pen = COLOR_LIGHTCYAN}},
                },
                
                widgets.EditField{
                    view_id = 'input_field',
                    frame = {l = 35, b = 4, r = 11},
                    text = '',
                    on_change = self:callback('on_input_change'),
                    on_submit = self:callback('send_message'),
                    active = false,
                },
				
				widgets.HotkeyLabel{
                    view_id = 'edit_prompt_btn',
                    frame = {l = 47, b = 1, w = 17},
                    label = 'Edit Prompt',
                    key = 'CUSTOM_P',
                    on_activate = self:callback('edit_dwarf_prompt'),
                    auto_width = false,
                    enabled = false,
                },
                
                widgets.HotkeyLabel{
                    view_id = 'send_btn',
                    frame = {r = 1, b = 4, w = 8},
                    label = 'Send',
                    key = 'CUSTOM_S',
                    on_activate = self:callback('send_message'),
                    auto_width = false,
                    enabled = false,
                },
                
                -- Help text
                widgets.Label{
                    frame = {l = 30, b = 2},
                    text = {
                        {text = 'Type to chat  ', pen = COLOR_GRAY},
                        {text = 'Enter', pen = COLOR_LIGHTGREEN}, 
                        {text = ': Send  ', pen = COLOR_GRAY},
                        {text = 'ESC', pen = COLOR_LIGHTRED}, 
                        {text = ': Close', pen = COLOR_GRAY},
                    },
                },
                
                -- Clear chat button
                widgets.HotkeyLabel{
                    view_id = 'clear_chat_btn',
                    frame = {l = 30, b = 1, w = 15},
                    label = 'Clear Chat',
                    key = 'CUSTOM_C',
                    on_activate = self:callback('clear_current_chat'),
                    auto_width = false,
                    enabled = false,
                },
                
                widgets.Label{
                    view_id = 'status_label',
                    frame = {l = 47, b = 1},
                    text = {{text = 'Initializing...', pen = COLOR_YELLOW}},
                },
            },
        },
    }
    
    self:refresh_dwarf_list()
    
    if self.preselected_dwarf then
        self:select_preselected_dwarf()
    end
    
    self:check_player2_status()
end

function ChatWindow:check_player2_status()
    if not player2_api then
        local error_msg = "ERROR: player2_api module not loaded"
        if api_load_error then
            error_msg = error_msg .. "\n" .. api_load_error
        end
        self:set_status(error_msg, COLOR_RED)
        print("[DwarfTalk] " .. error_msg)
        return
    end
    
    -- Don't do automatic health check - it causes false positives
    -- We'll check when actually sending a message
    self:set_status('Ready', COLOR_GREEN)
end

function ChatWindow:refresh_dwarf_list()
    local dwarves = dwarf_data.get_fortress_dwarves()
    local choices = {}
    
    for i, dwarf in ipairs(dwarves) do
        -- Single line format
        local display_text = dwarf.name .. ' - ' .. dwarf.profession
        
        if persistence.has_conversation(dwarf.id) then
            display_text = display_text .. ' 💬'
        end
        
        table.insert(choices, {
            text = display_text,
            dwarf_id = dwarf.id,
            data = dwarf,
        })
    end
    
    self.dwarf_choices = choices
    self.subviews.dwarf_list:setChoices(choices)
    self.subviews.left_panel.frame_title = 'Your Dwarves (' .. #choices .. ')'
end

function ChatWindow:edit_dwarf_prompt()
    if not self.selected_dwarf then return end
    
    local editor = require('dwarf_prompt_editor')
    editor.show_editor(self.selected_dwarf)
end

function ChatWindow:open_settings()
    local settings = require('settings_window')
    settings.show_settings()
end

function ChatWindow:select_preselected_dwarf()
    if not self.preselected_dwarf then return end
    
    for i, choice in ipairs(self.dwarf_choices) do
        if choice.dwarf_id == self.preselected_dwarf.id then
            self.subviews.dwarf_list:setSelected(i)
            self:on_select_dwarf(i, choice)
            break
        end
    end
end

function ChatWindow:on_select_dwarf(idx, choice)
    if not choice then return end
    
    self.selected_dwarf = choice.data
    self.dwarf_analysis = nil
    
    self.subviews.input_field.active = true
    
    local info = choice.data.name .. ' - ' .. choice.data.profession
    self.subviews.dwarf_info:setText(info)
    
    self:analyze_selected_dwarf()
    
    self:load_chat_history(choice.data)
    
    self.subviews.send_btn.enabled = true
    self.subviews.clear_chat_btn.enabled = true
    self.subviews.edit_prompt_btn.enabled = true
    self.subviews.right_panel.frame_title = 'Chat: ' .. choice.data.name
    
    self:set_status('Ready', COLOR_GREEN)
end

function ChatWindow:analyze_selected_dwarf()
    if not analyzer then
        print("[DwarfTalk] Analyzer not available, using basic info")
        return
    end
    
    if not self.selected_dwarf or not self.selected_dwarf.unit then
        return
    end
    
    print("[DwarfTalk] Analyzing " .. self.selected_dwarf.name .. "...")
    self:set_status('Analyzing personality...', COLOR_YELLOW)
    
    -- Perform deep analysis
    local ok, analysis = pcall(analyzer.analyze_dwarf, self.selected_dwarf.unit)
    
    if ok and analysis then
        self.dwarf_analysis = analysis
        print("[DwarfTalk] ✓ Analysis complete!")
        
        -- Show a hint about the personality
        if analysis.personality and analysis.personality.narrative_description and #analysis.personality.narrative_description > 0 then
            print("[DwarfTalk] Personality: " .. analysis.personality.narrative_description[1])
        end
    else
        print("[DwarfTalk] ✗ Analysis failed: " .. tostring(analysis))
        self.dwarf_analysis = nil
    end
end

function ChatWindow:load_chat_history(dwarf)
    logger.section("LOAD CHAT HISTORY")
    logger.log("LOAD", "Loading for dwarf ID: " .. tostring(dwarf.id))
    logger.log("LOAD", "Dwarf name: " .. tostring(dwarf.name))
    
    local saved_messages, saved_history = persistence.load_conversation(dwarf.id)
    
    logger.log("LOAD", "Saved messages: " .. tostring(saved_messages and #saved_messages or "nil"))
    logger.log("LOAD", "Saved history: " .. tostring(saved_history and #saved_history or "nil"))
    
    -- Check if we have an initial message from notification
    local has_initial = self.initial_message and self.initial_message ~= ""
    
    if saved_messages and saved_history then
        logger.log("LOAD", "Found saved conversation - restoring")
        
        -- Restore saved conversation
        self.chat_messages = saved_messages
        self.conversation_history = saved_history
        self:update_chat_display()
        
        logger.log("LOAD", "Chat display updated with " .. #self.chat_messages .. " messages")
        
        if has_initial then
            logger.log("LOAD", "Adding initial message from notification")
            self:add_message(dwarf.name, self.initial_message)
            
            table.insert(self.conversation_history, {
                role = 'assistant',
                content = self.initial_message
            })
            
            self:save_current_conversation()
        end
        
        return
    end
    
    logger.log("LOAD", "No saved conversation - starting fresh")
    
    -- No saved conversation, start fresh
    self.chat_messages = {}
    self.conversation_history = {}
    
    if has_initial then
        self:add_message(dwarf.name, self.initial_message)
        
        table.insert(self.conversation_history, {
            role = 'assistant',
            content = self.initial_message
        })
        
        self:save_current_conversation()
    else
        self:update_chat_display()
    end
end

function ChatWindow:save_current_conversation()
    if self.selected_dwarf then
        logger.log("SAVE", "Attempting to save for dwarf ID: " .. tostring(self.selected_dwarf.id))
        logger.log("SAVE", "Dwarf name: " .. tostring(self.selected_dwarf.name))
        logger.log("SAVE", "Messages count: " .. #self.chat_messages)
        logger.log("SAVE", "History count: " .. #self.conversation_history)
        
        local ok, err = pcall(function()
            persistence.save_conversation(
                self.selected_dwarf.id,
                self.chat_messages,
                self.conversation_history
            )
        end)
        
        if ok then
            logger.log("SAVE", "✓ Save successful")
        else
            logger.log("SAVE", "✗ Save FAILED: " .. tostring(err))
        end
    else
        logger.log("SAVE", "✗ No selected dwarf to save")
    end
end

function ChatWindow:clear_current_chat()
    if not self.selected_dwarf then return end
    
    persistence.delete_conversation(self.selected_dwarf.id)
    
    self.chat_messages = {}
    self.conversation_history = {}
    self:update_chat_display()
    
    self:load_chat_history(self.selected_dwarf)
    
    self:refresh_dwarf_list()
end

function ChatWindow:add_message(speaker, text)
    local max_width = 48
    local wrapped = self:wrap_text(text, max_width)
    
    table.insert(self.chat_messages, speaker .. ': ' .. wrapped)
    self:update_chat_display()
end

function ChatWindow:wrap_text(text, max_width)
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

function ChatWindow:update_chat_display()
    local display_text = table.concat(self.chat_messages, '\n\n')
    self.subviews.chat_history:setText(display_text)
end

function ChatWindow:on_input_change(text)
    self.subviews.send_btn.enabled = #text > 0
end

function ChatWindow:send_message()
    if not self.selected_dwarf then 
        self:set_status('✗ Select a dwarf first', COLOR_RED)
        return 
    end
    
    local msg = self.subviews.input_field.text
    if msg == '' then return end
    
    if not player2_api then
        self:add_message('ERROR', '⚠ Cannot send: Player2 API not loaded')
        self:set_status('✗ API Error', COLOR_RED)
        return
    end
    
    self:add_message('You', msg)
    self.subviews.input_field:setText('')
    self:set_status('⏳ AI is thinking...', COLOR_YELLOW)
    self:send_ai_message(msg)
end

function ChatWindow:send_ai_message(user_msg)
    local dwarf = self.selected_dwarf
    
    logger.section("SEND AI MESSAGE")
    logger.log("SEND", "Dwarf: " .. dwarf.name)
    logger.log("SEND", "User message: " .. user_msg)
    
    -- Build system prompt with deep analysis
    local ok, system_prompt = pcall(prompt_builder.build_system_prompt, dwarf, self.dwarf_analysis)
    local prompt_file = dfhack.getDFPath() .. '/dwarftalk_temp/last_prompt.txt'
    local pf = io.open(prompt_file, 'w')
    if pf then
        pf:write(system_prompt)
        pf:close()
    end
    
    if not ok then
        self:add_message('ERROR', '⚠ Failed to build prompt: ' .. tostring(system_prompt))
        self:set_status('✗ Prompt Error', COLOR_RED)
        return
    end
    
    logger.log("SEND", "Calling player2_api.chat_with_dwarf...")
    
    player2_api.chat_with_dwarf(
        system_prompt,
        self.conversation_history,
        user_msg,
        function(success, response, action)
            logger.section("CHAT CALLBACK")
            logger.log("CALLBACK", "Success: " .. tostring(success))
            logger.log("CALLBACK", "Response length: " .. (response and #response or 0))
            logger.log("CALLBACK", "Action present: " .. tostring(action ~= nil))
            
            if action then
                logger.log("CALLBACK", "Action type: " .. tostring(action.type))
                logger.log("CALLBACK", "Action amount: " .. tostring(action.amount))
            end
            
            if success then
                logger.log("CALLBACK", "Adding to conversation history...")
                
                -- Add user message to history
                table.insert(self.conversation_history, {
                    role = 'user',
                    content = user_msg
                })
                logger.log("CALLBACK", "User message added to history")
                
                -- Add assistant response to history
                table.insert(self.conversation_history, {
                    role = 'assistant',
                    content = response
                })
                logger.log("CALLBACK", "Assistant response added to history")
                
                -- Add to chat display
                self:add_message(dwarf.name, response)
                logger.log("CALLBACK", "Message added to chat display")
                
                -- EXECUTE ACTION IF EXISTS
                if action and action.type then
                    logger.log("CALLBACK", "ACTION DETECTED - About to execute")
                    
                    if action_engine then
                        logger.log("CALLBACK", "Calling action_engine.execute...")
                        local ok, result = pcall(action_engine.execute, dwarf, action)

                        logger.log("CALLBACK", "action_engine.execute returned - ok: " .. tostring(ok))
                        logger.log("CALLBACK", "action_engine.execute returned - result: " .. tostring(result))

                        if ok and result then
                            logger.log("CALLBACK", "Adding system message to chat")
                            logger.log("CALLBACK", "Result to add: " .. tostring(result))
                            
                            local add_ok, add_err = pcall(function()
                                self:add_message('', '~ ' .. tostring(result))
                            end)
                            
                            if not add_ok then
                                logger.log("CALLBACK", "ERROR adding system message: " .. tostring(add_err))
                            else
                                logger.log("CALLBACK", "System message added successfully")
                            end
                        else
                            logger.log("CALLBACK", "Action execution failed: " .. tostring(result))
                        end
                    end
                else
                    logger.log("CALLBACK", "No action to execute")
                end
                
                -- SAVE CONVERSATION
                logger.log("CALLBACK", "About to save conversation...")
                self:save_current_conversation()
                logger.log("CALLBACK", "Conversation save completed")
                
                self:set_status('✓ Ready', COLOR_GREEN)
            else
                logger.log("CALLBACK", "ERROR: " .. tostring(response))
                self:add_message('ERROR', '⚠ Failed to get response from AI')
                self:set_status('✗ Error', COLOR_RED)
            end
        end
    )
end

function ChatWindow:set_status(text, color)
    self.subviews.status_label:setText({{text = text, pen = color or COLOR_WHITE}})
end

function ChatWindow:open_npc_history()
    dfhack.run_command('dwarftalk/npc_history_window')
end

function ChatWindow:onDismiss()
end

function ChatWindow:onInput(keys)
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
-- Exported commands
-- ============================================================================

function command_dwarftalk_chat()
    -- Check if we have a pending chat request from notification
    if _G.dwarftalk_pending_chat then
        local pending = _G.dwarftalk_pending_chat
        _G.dwarftalk_pending_chat = nil  -- Clear it
        
        -- Find the dwarf
        for _, unit in ipairs(df.global.world.units.active) do
            if unit.id == pending.dwarf_id then
                local dwarf_info = dwarf_data.get_dwarf_info(unit)
                if dwarf_info then
                    ChatWindow{
                        preselected_dwarf = dwarf_info,
                        initial_message = pending.initial_message,
                    }:show()
                    return
                end
            end
        end
    end
    
    -- Normal chat window (no pending request)
    ChatWindow{}:show()
end

function command_dwarftalk_quick_chat()
    local unit = dfhack.gui.getSelectedUnit()
    
    if unit and dfhack.units.isCitizen(unit) then
        local dwarf_info = dwarf_data.get_dwarf_info(unit)
        if dwarf_info then
            ChatWindow{
                preselected_dwarf = dwarf_info,
            }:show()
        else
            dfhack.printerr('Could not get dwarf information')
            ChatWindow{}:show()
        end
    else
        dfhack.printerr('Please select a citizen with "v" first')
        ChatWindow{}:show()
    end
end

-- ============================================================================
-- Entry point
-- ============================================================================

if not dfhack_flags.module then
    local args = {...}
    if #args > 0 and args[1] == 'quick' then
        command_dwarftalk_quick_chat()
    else
        command_dwarftalk_chat()
    end
else
    -- Export for use by other modules
    return {
        ChatWindow = ChatWindow,
        dwarf_data = dwarf_data,
    }
end