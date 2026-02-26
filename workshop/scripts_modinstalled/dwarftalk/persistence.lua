--@module = true
--[=====[

dwarftalk/persistence
=====================
Save/Load conversation history for dwarves

]=====]

local json = nil
for _, lib in ipairs({'json', 'dkjson', 'cjson'}) do
    local success, result = pcall(require, lib)
    if success then
        json = result
        break
    end
end

local logger = require('debug_logger')  -- ← AGREGAR

local persistence = {}

-- Directory for saved conversations
local save_dir = dfhack.getDFPath() .. '/dwarftalk_saves/'

-- Sanitize functions
local function sanitize_text(text)
    if not text then return "" end
    -- Remove non-ASCII characters
    return text:gsub("[^\32-\126\n\t]", "")
end

local function sanitize_messages(messages)
    if not messages then return {} end
    local clean = {}
    for i, msg in ipairs(messages) do  -- Usa ipairs correctamente
        clean[i] = sanitize_text(msg)
    end
    return clean
end

local function sanitize_history(history)
    if not history then return {} end
    local clean = {}
    for i, entry in ipairs(history) do  -- Usa ipairs correctamente
        clean[i] = {
            role = entry.role,
            content = sanitize_text(entry.content)
        }
    end
    return clean
end

-- Ensure save directory exists
local function ensure_save_dir()
    dfhack.run_command_silent('mkdir "' .. save_dir:gsub('/', '\\') .. '" 2>nul')
end

ensure_save_dir()

function persistence.get_save_path(dwarf_id)
    return save_dir .. 'conversation_' .. tostring(dwarf_id) .. '.json'
end

function persistence.save_conversation(dwarf_id, chat_messages, conversation_history)
    logger.section("PERSISTENCE SAVE")
    logger.log("PERSIST", "Dwarf ID: " .. tostring(dwarf_id))
    logger.log("PERSIST", "Messages: " .. tostring(chat_messages and #chat_messages or "nil"))
    logger.log("PERSIST", "History: " .. tostring(conversation_history and #conversation_history or "nil"))
    
    if not json then 
        logger.log("PERSIST", "ERROR: JSON library not available")
        return false
    end
    
    -- SANITIZE antes de guardar
    local clean_messages = sanitize_messages(chat_messages)
    local clean_history = sanitize_history(conversation_history)
    
    local filepath = persistence.get_save_path(dwarf_id)
    logger.log("PERSIST", "Save path: " .. filepath)
    
    local data = {
        chat_messages = clean_messages,
        conversation_history = clean_history,
        saved_at = os.time(),
        dwarf_id = tonumber(dwarf_id) or dwarf_id,
    }
    
    local ok, json_data = pcall(json.encode, data)
    if not ok then
        logger.log("PERSIST", "ERROR encoding JSON: " .. tostring(json_data))
        return false
    end
    
    logger.log("PERSIST", "Encoded " .. #json_data .. " bytes of JSON")
    
    local f = io.open(filepath, 'w')
    if not f then
        logger.log("PERSIST", "ERROR: Could not open file for writing")
        return false
    end
    
    f:write(json_data)
    f:close()
    
    logger.log("PERSIST", "File written successfully")
    return true
end

function persistence.load_conversation(dwarf_id)
    logger.section("PERSISTENCE LOAD")
    logger.log("PERSIST", "Dwarf ID: " .. tostring(dwarf_id))
    
    if not json then 
        logger.log("PERSIST", "ERROR: JSON library not available")
        return nil, nil
    end
    
    local filepath = persistence.get_save_path(dwarf_id)
    logger.log("PERSIST", "Load path: " .. filepath)
    
    local f = io.open(filepath, 'r')
    if not f then
        logger.log("PERSIST", "File does not exist")
        return nil, nil
    end
    
    logger.log("PERSIST", "File exists, reading...")
    local json_data = f:read('*all')
    f:close()
    
    logger.log("PERSIST", "Read " .. #json_data .. " bytes")
    
    if not json_data or json_data == '' then
        logger.log("PERSIST", "File is empty")
        return nil, nil
    end
    
    logger.log("PERSIST", "Attempting to decode JSON...")
    local ok, data = pcall(json.decode, json_data)
    
    logger.log("PERSIST", "Decode ok: " .. tostring(ok))
    
    if not ok then
        logger.log("PERSIST", "ERROR decoding JSON: " .. tostring(data))
        logger.log("PERSIST", "JSON preview: " .. json_data:sub(1, 100))
        return nil, nil
    end
    
    if not data then
        logger.log("PERSIST", "Data is nil after decode")
        return nil, nil
    end
    
    logger.log("PERSIST", "Successfully decoded")
    logger.log("PERSIST", "Messages: " .. tostring(data.chat_messages and #data.chat_messages or "nil"))
    logger.log("PERSIST", "History: " .. tostring(data.conversation_history and #data.conversation_history or "nil"))
    
    return data.chat_messages, data.conversation_history
end

function persistence.delete_conversation(dwarf_id)
    local filepath = persistence.get_save_path(dwarf_id)
    os.remove(filepath)
end

function persistence.has_conversation(dwarf_id)
    local filepath = persistence.get_save_path(dwarf_id)
    local f = io.open(filepath, 'r')
    if f then
        f:close()
        return true
    end
    return false
end

return persistence