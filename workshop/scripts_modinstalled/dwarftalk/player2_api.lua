--@module = true

local json = nil
for _, lib in ipairs({'json', 'dkjson', 'cjson'}) do
    local success, result = pcall(require, lib)
    if success then
        json = result
        break
    end
end

local player2_api = {}

local df_path = dfhack.getDFPath()
local temp_dir = df_path .. '/dwarftalk_temp/'
local request_file = temp_dir .. 'request.json'
local response_file = temp_dir .. 'response.json'

player2_api.MAX_RETRIES = 3
player2_api.DEBUG = false

-- ============================================================================
-- SANITIZE TEXT - Remove invalid unicode characters
-- ============================================================================

local function sanitize_text(text)
    if not text then return "" end
    
    -- Replace problematic UTF-8 bytes with ASCII equivalents
    local replacements = {
        ["\194"] = "", -- UTF-8 prefix
        ["\195"] = "", -- UTF-8 prefix
        ["\226"] = "'", -- Smart quotes
        ["\128"] = "",
        ["\153"] = "",
        ["\156"] = "",
    }
    
    for bad, good in pairs(replacements) do
        text = text:gsub(bad, good)
    end
    
    -- Keep only printable ASCII + newlines + tabs
    text = text:gsub("[^\32-\126\n\t]", "")
    
    return text
end

-- ============================================================================
-- Simple file-based communication
-- ============================================================================

local function make_request(command, messages, callback)
    local logger = require('debug_logger')
    
    logger.section("PLAYER2 API REQUEST")
    logger.log("API", "Command: " .. command)
    logger.log("API", "Request file: " .. request_file)
    logger.log("API", "Response file: " .. response_file)
    
    -- Build request
    local request = {command = command}
    if messages then
        request.messages = messages
    end
    
    -- Delete old response
    os.remove(response_file)
    logger.log("API", "Deleted old response file")
    
    -- Write request
    local f = io.open(request_file, 'w')
    if not f then
        logger.log("API", "ERROR: Could not write request")
        callback(nil, "Could not write request")
        return
    end
    f:write(json.encode(request))
    f:close()
    
    logger.log("API", "Request written, starting poll...")
    
    local poll_count = 0
    local max_polls = 300  -- 300 frames ≈ 30 segundos a 10 FPS

    local function poll()
        poll_count = poll_count + 1
        
        logger.log("API", "Poll attempt " .. poll_count .. "/" .. max_polls)
        
        local f = io.open(response_file, 'r')
        if f then
            logger.log("API", "Response file exists!")
            local data = f:read('*all')
            f:close()
            
            logger.log("API", "Response data length: " .. #data)
            
            if #data > 0 then
                logger.log("API", "Response received successfully")
                os.remove(response_file)
                
                local ok, response = pcall(json.decode, data)
                if ok then
                    logger.log("API", "Response parsed successfully")
                    callback(response)
                else
                    logger.log("API", "ERROR: Failed to parse response JSON")
                    logger.log("API", "Parse error: " .. tostring(response))
                    callback(nil, "Invalid response")
                end
                return
            else
                logger.log("API", "Response file empty")
            end
        else
            logger.log("API", "Response file not found yet")
        end
        
        if poll_count >= max_polls then
            logger.log("API", "ERROR: Timeout reached")
            callback(nil, "Timeout - is dwarftalk_bridge.exe running?")
            return
        end
        
        dfhack.timeout(10, 'frames', poll)  -- Poll cada ~1 segundo (10 frames)
    end

    dfhack.timeout(10, 'frames', poll)  -- Iniciar poll
end

-- ============================================================================
-- API Functions
-- ============================================================================

function player2_api.check_health(callback)
    make_request("health", nil, function(response, err)
        if response then
            callback(response.success, response.message)
        else
            callback(false, err or "Request failed")
        end
    end)
end

function player2_api.build_messages(system_prompt, conversation_history, user_message)
    local messages = {}
    
    -- Sanitize system prompt
    if system_prompt and system_prompt ~= "" then
        local clean_prompt = sanitize_text(system_prompt)
        table.insert(messages, {role = "system", content = clean_prompt})
        print("[Player2API] System prompt sanitized: " .. #system_prompt .. " -> " .. #clean_prompt .. " bytes")
    end
    
    -- Sanitize conversation history
    if conversation_history then
        for _, entry in ipairs(conversation_history) do
            local clean_content = sanitize_text(entry.content)
            table.insert(messages, {role = entry.role, content = clean_content})
        end
    end
    
    -- Sanitize user message
    local clean_user_msg = sanitize_text(user_message)
    table.insert(messages, {role = "user", content = clean_user_msg})
    
    return messages
end

function player2_api.send_chat_request(messages, callback)
    make_request("chat", messages, function(response, err)
        print("[Player2API] send_chat_request callback received")
        print("[Player2API] Response:", response and "YES" or "NO")
        print("[Player2API] Error:", err or "NONE")
        
        if response then
            print("[Player2API] Response.success:", response.success)
            print("[Player2API] Response.message length:", response.message and #response.message or 0)
        end
        
        if response and response.success then
            local dialogue, action = player2_api.parse_response(response.message)
            callback(true, dialogue, action)
        else
            callback(false, err or response.message or "Unknown error", nil)
        end
    end)
end

function player2_api.parse_response(text)
    -- GUARDAR RESPUESTA RAW
    local raw_file = dfhack.getDFPath() .. '/dwarftalk_temp/last_response.txt'
    local rf = io.open(raw_file, 'w')
    if rf then
        rf:write(text or "NULL")
        rf:close()
    end
    
    print("[Player2API] ========================================")
    print("[Player2API] parse_response called")
    
    if not text then 
        print("[Player2API] No text to parse")
        return "", nil 
    end
    
    -- INTENTO 1: Parsear como JSON puro
    local ok, parsed = pcall(json.decode, text)
    if ok and parsed and parsed.dialogue and parsed.action then
        print("[Player2API] ✓✓✓ Parsed as pure JSON")
        print("[Player2API] Action type:", parsed.action.type)
        return parsed.dialogue, parsed.action
    end
    
    -- INTENTO 2: Buscar JSON dentro del texto
    local json_start = text:find("{")
    if json_start then
        local json_text = text:sub(json_start)
        local ok2, parsed2 = pcall(json.decode, json_text)
        if ok2 and parsed2 and parsed2.dialogue and parsed2.action then
            print("[Player2API] ✓✓✓ Parsed JSON from text")
            print("[Player2API] Action type:", parsed2.action.type)
            return parsed2.dialogue, parsed2.action
        end
    end
    
    -- INTENTO 3: Buscar ACTION: (formato antiguo)
    local dialogue = text
    local action = nil
    
    local action_start = text:find("ACTION:")
    if action_start then
        print("[Player2API] Found ACTION: format")
        local action_line = text:sub(action_start + 7)
        local json_start = action_line:find("{")
        
        if json_start then
            local brace_count = 0
            local json_end = nil
            
            for i = json_start, #action_line do
                local char = action_line:sub(i, i)
                if char == "{" then
                    brace_count = brace_count + 1
                elseif char == "}" then
                    brace_count = brace_count - 1
                    if brace_count == 0 then
                        json_end = i
                        break
                    end
                end
            end
            
            if json_end then
                local action_json = action_line:sub(json_start, json_end)
                local ok3, parsed3 = pcall(json.decode, action_json)
                if ok3 and parsed3 then
                    action = parsed3
                    print("[Player2API] ✓ Parsed ACTION from old format")
                    dialogue = text:sub(1, action_start - 1)
                end
            end
        end
    end
    
    -- Limpiar diálogo
    dialogue = dialogue:match("^%s*(.-)%s*$")
    dialogue = dialogue:gsub("%[OOC:.-]", "")
    dialogue = dialogue:gsub("%*[^%*]*%*", "")
    
    print("[Player2API] Final - Dialogue:", dialogue and "YES" or "NO")
    print("[Player2API] Final - Action:", action and "YES" or "NO")
    print("[Player2API] ========================================")
    
    return dialogue, action
end

function player2_api.chat_with_dwarf(system_prompt, conversation_history, user_message, callback)
    print("[Player2API] ========================================")
    print("[Player2API] chat_with_dwarf called")
    print("[Player2API] System prompt length:", #system_prompt)
    print("[Player2API] Conversation history entries:", #conversation_history)
    print("[Player2API] User message:", user_message)
    
    -- Build messages array
    local messages = player2_api.build_messages(system_prompt, conversation_history, user_message)
    
    print("[Player2API] Total messages:", #messages)
    
    -- Send request
    player2_api.send_chat_request(messages, callback)
    
    print("[Player2API] ========================================")
end

local npc_request_file = temp_dir .. 'npc_request.json'
local npc_response_file = temp_dir .. 'npc_response.json'

function player2_api.generate_npc_conversation(prompt, callback)
    local logger = require('debug_logger')
    
    logger.section("NPC API REQUEST")
    
    -- Sanitizar prompt
    local clean_prompt = sanitize_text(prompt)
    
    -- Construir request
    local request = {
        command = "chat",
        messages = {{role = "user", content = clean_prompt}}
    }
    
    -- USAR ARCHIVOS NPC SEPARADOS
    os.remove(npc_response_file)
    logger.log("NPC_API", "Using separate NPC files")
    
    -- Escribir request
    local f = io.open(npc_request_file, 'w')
    if not f then
        callback(false, nil)
        return
    end
    f:write(json.encode(request))
    f:close()
    
    logger.log("NPC_API", "Request written to npc_request.json")
    
    -- Poll para respuesta
    local poll_count = 0
    local max_polls = 300
    
    local function poll()
        poll_count = poll_count + 1
        
        local f = io.open(npc_response_file, 'r')
        if f then
            local data = f:read('*all')
            f:close()
            
            if #data > 0 then
                logger.log("NPC_API", "Response received")
                os.remove(npc_response_file)
                
                local ok, response = pcall(json.decode, data)
                if ok and response and response.success then
                    local text = response.message
                    
                    -- Limpiar y parsear JSON
                    local clean = text:gsub("```json", ""):gsub("```", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    
                    local ok2, result = pcall(json.decode, clean)
                    if ok2 and result and result.dialogue then
                        callback(true, result)
                    else
                        -- Buscar JSON embebido
                        local json_start = clean:find("{")
                        if json_start then
                            local json_text = clean:sub(json_start)
                            local ok3, result2 = pcall(json.decode, json_text)
                            if ok3 and result2 and result2.dialogue then
                                callback(true, result2)
                                return
                            end
                        end
                        callback(false, nil)
                    end
                else
                    callback(false, nil)
                end
                return
            end
        end
        
        if poll_count >= max_polls then
            logger.log("NPC_API", "Timeout")
            callback(false, nil)
            return
        end
        
        dfhack.timeout(10, 'frames', poll)
    end
    
    dfhack.timeout(10, 'frames', poll)
end

return player2_api