--@module = true
--[=====[

dwarftalk/message_generator
===========================
Generates messages from dwarves using AI

]=====]

local player2_api = require('player2_api')
local analyzer = require('analyze_dwarf')
local fortress_context = require('fortress_context')
local config_manager = require('config_manager')

local generator = {}

-- ============================================================================
-- BUILD PROMPT FOR MESSAGE GENERATION
-- ============================================================================

function generator.build_message_prompt(dwarf_info, analysis)
    local prompt = "You are " .. dwarf_info.name .. ", a dwarf in a fortress.\n\n"
    
    -- Personality
    if analysis and analysis.personality then
        prompt = prompt .. "YOUR PERSONALITY:\n"
        if analysis.personality.narrative_description and #analysis.personality.narrative_description > 0 then
            for _, desc in ipairs(analysis.personality.narrative_description) do
                prompt = prompt .. "- You " .. desc .. "\n"
            end
        end
        prompt = prompt .. "\n"
    end
    
    -- Urgent needs
    if analysis and analysis.needs and #analysis.needs > 0 then
        prompt = prompt .. "URGENT NEEDS:\n"
        for _, need in ipairs(analysis.needs) do
            if need.level >= 8 then
                local need_desc = need.type:gsub("([A-Z])", " %1"):lower():gsub("^ ", "")
                prompt = prompt .. "- You desperately need to " .. need_desc .. " (level " .. need.level .. "/10)\n"
            end
        end
        prompt = prompt .. "\n"
    end
    
    -- Context
    local ctx = fortress_context.get_fortress_context()
    if ctx then
        prompt = prompt .. "FORTRESS STATUS:\n"
        prompt = prompt .. "- Population: " .. ctx.population .. " dwarves\n"
        prompt = prompt .. "- Mood: " .. ctx.fortress_mood .. "\n"
        
        if ctx.recent_deaths and #ctx.recent_deaths > 0 then
            prompt = prompt .. "- Recent death: " .. ctx.recent_deaths[1].name .. " died\n"
        end
        
        if ctx.threats and (ctx.threats.siege or ctx.threats.ambush) then
            prompt = prompt .. "- DANGER: Fortress under attack!\n"
        end
        
        prompt = prompt .. "\n"
    end
    
    -- Instructions
    prompt = prompt .. "TASK:\n"
    prompt = prompt .. "Write a SHORT message (2-3 sentences) to the fortress overseer.\n"
    prompt = prompt .. "You want to tell them something important or just chat.\n"
    prompt = prompt .. "Be authentic to your personality and current needs.\n"
    prompt = prompt .. "Write ONLY the message text, nothing else.\n"
    
    return prompt
end

-- ============================================================================
-- GENERATE MESSAGE
-- ============================================================================

function generator.generate_message(unit, callback)
    -- Get dwarf info
    local function get_dwarf_name(u)
        local name = "Unknown Dwarf"
        if u.name.has_name then
            if u.name.first_name ~= '' then
                name = u.name.first_name
            end
            if u.name.nickname ~= '' then
                if name ~= "Unknown Dwarf" then
                    name = name .. ' "' .. u.name.nickname .. '"'
                else
                    name = '"' .. u.name.nickname .. '"'
                end
            end
        end
        return name
    end
    
    local dwarf_info = {
        id = tonumber(unit.id),
        name = get_dwarf_name(unit),
        profession = dfhack.units.getProfessionName(unit) or "Dwarf",
        unit = unit,
    }
    
    -- NUEVO: Cargar conversaciones previas para contexto
    local persistence = require('persistence')
    local chat_messages, conversation_history = persistence.load_conversation(dwarf_info.id)
    
    if not conversation_history then
        conversation_history = {}
    end
    
    -- Analyze dwarf
    local ok, analysis = pcall(require('analyze_dwarf').analyze_dwarf, unit)
    if not ok then
        analysis = nil
    end
    
    -- Build prompt
    local system_prompt = generator.build_message_prompt(dwarf_info, analysis)
    
    -- NUEVO: Agregar contexto de conversaciones previas
    if #conversation_history > 0 then
        system_prompt = system_prompt .. "\nPREVIOUS CONVERSATIONS:\n"
        system_prompt = system_prompt .. "You've talked with the overseer before. Here's a summary:\n"
        
        -- Últimos 4 mensajes (2 intercambios)
        local recent_count = math.min(4, #conversation_history)
        local start_idx = #conversation_history - recent_count + 1
        
        for i = start_idx, #conversation_history do
            local msg = conversation_history[i]
            if msg.role == "user" then
                system_prompt = system_prompt .. "- Overseer said: " .. msg.content:sub(1, 100) .. "\n"
            else
                system_prompt = system_prompt .. "- You said: " .. msg.content:sub(1, 100) .. "\n"
            end
        end
        
        system_prompt = system_prompt .. "\nYour new message should naturally continue from this context.\n"
    end
    
    -- Add custom prompt if exists
    local custom = config_manager.get_custom_prompt()
    if custom and custom ~= "" then
        system_prompt = system_prompt .. "\n" .. custom .. "\n"
    end
    
    print("[MessageGenerator] Generating message for " .. dwarf_info.name .. " (history: " .. #conversation_history .. " messages)")
    
    -- Call AI
    local player2_api = require('player2_api')
    player2_api.chat_with_dwarf(
        system_prompt,
        {}, -- No enviamos historial aquí porque ya está en el prompt del sistema
        "Generate a message.", 
        function(success, dialogue, action)
            if success and dialogue then
                print("[MessageGenerator] ✓ Generated message: " .. dialogue:sub(1, 50) .. "...")
                
                -- Save message directly to chat history
                generator.save_to_chat_history(dwarf_info.id, dwarf_info.name, dialogue)
                
                callback(true, dwarf_info, dialogue)
            else
                print("[MessageGenerator] ✗ Failed: " .. tostring(dialogue))
                callback(false, dwarf_info, dialogue or "Error generating message")
            end
        end
    )
end

-- ============================================================================
-- SAVE TO CHAT HISTORY
-- ============================================================================

function generator.save_to_chat_history(dwarf_id, dwarf_name, message)
    local persistence = require('persistence')
    
    -- Load existing conversation
    local chat_messages, conversation_history = persistence.load_conversation(dwarf_id)
    
    if not chat_messages then
        chat_messages = {}
    end
    
    if not conversation_history then
        conversation_history = {}
    end
    
    -- Wrap message text
    local function wrap_text(text, max_width)
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
    
    local wrapped = wrap_text(message, 48)
    
    -- Add dwarf's message
    table.insert(chat_messages, dwarf_name .. ': ' .. wrapped)
    
    table.insert(conversation_history, {
        role = 'assistant',
        content = message
    })
    
    -- Save back
    local success = persistence.save_conversation(dwarf_id, chat_messages, conversation_history)
    
    if success then
        print("[MessageGenerator] ✓ Message saved to chat history for dwarf " .. dwarf_id)
    else
        print("[MessageGenerator] ✗ Failed to save message to chat history")
    end
end
-- ============================================================================
-- EXPORT
-- ============================================================================

return generator