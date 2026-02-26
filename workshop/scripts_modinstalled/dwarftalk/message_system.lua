--@module = true
--[=====[

dwarftalk/message_system
========================
Manages pending messages/notifications from dwarves

]=====]

local json = nil
for _, lib in ipairs({'json', 'dkjson', 'cjson'}) do
    local success, result = pcall(require, lib)
    if success then
        json = result
        break
    end
end

local messages = {}

local saves_dir = dfhack.getDFPath() .. '/dwarftalk_saves/'
local messages_dir = saves_dir .. 'messages/'
local pending_path = messages_dir .. 'pending.json'

-- Ensure messages directory exists
local function ensure_messages_dir()
    dfhack.run_command_silent('mkdir "' .. messages_dir:gsub('/', '\\') .. '" 2>nul')
end

ensure_messages_dir()

-- ============================================================================
-- SANITIZE FOR JSON (convert all values to JSON-safe types)
-- ============================================================================

local function sanitize_for_json(data)
    if type(data) == "table" then
        local result = {}
        for k, v in pairs(data) do
            result[sanitize_for_json(k)] = sanitize_for_json(v)
        end
        return result
    elseif type(data) == "string" then
        return data
    elseif type(data) == "number" then
        return data
    elseif type(data) == "boolean" then
        return data
    elseif type(data) == "userdata" then
        -- Try to convert userdata to number
        local num = tonumber(data)
        if num then
            return num
        else
            return tostring(data)
        end
    else
        return tostring(data)
    end
end

-- ============================================================================
-- LOAD PENDING MESSAGES
-- ============================================================================

function messages.load_pending()
    if not json then return {} end
    
    local f = io.open(pending_path, 'r')
    if not f then return {} end
    
    local json_data = f:read('*all')
    f:close()
    
    if not json_data or json_data == '' then return {} end
    
    local ok, data = pcall(json.decode, json_data)
    if not ok or not data then return {} end
    
    return data
end

-- ============================================================================
-- SAVE PENDING MESSAGES
-- ============================================================================

function messages.save_pending(pending_list)
    if not json then return false end
    
    -- Sanitize the entire list before encoding
    local safe_list = sanitize_for_json(pending_list)
    
    local json_data = json.encode(safe_list)
    
    local f = io.open(pending_path, 'w')
    if not f then return false end
    
    f:write(json_data)
    f:close()
    
    return true
end

-- ============================================================================
-- ADD MESSAGE
-- ============================================================================

function messages.add_message(dwarf_id, dwarf_name, message_text)
    local pending = messages.load_pending()
    
    -- Ensure all values are JSON-safe
    local safe_message = {
        dwarf_id = tonumber(dwarf_id) or 0,
        dwarf_name = tostring(dwarf_name),
        message = tostring(message_text),
        timestamp = tonumber(os.time()),
        created_at = tostring(os.date("%Y-%m-%d %H:%M:%S")),
    }
    
    table.insert(pending, safe_message)
    
    messages.save_pending(pending)
    
    print("[MessageSystem] Added message from " .. safe_message.dwarf_name)
    return true
end

-- ============================================================================
-- GET NEXT MESSAGE
-- ============================================================================

function messages.get_next_message()
    local pending = messages.load_pending()
    
    if #pending == 0 then
        return nil
    end
    
    -- Return oldest message (first in list)
    return pending[1]
end

-- ============================================================================
-- REMOVE MESSAGE
-- ============================================================================

function messages.remove_message(dwarf_id)
    local pending = messages.load_pending()
    
    local id_num = tonumber(dwarf_id)
    
    for i, msg in ipairs(pending) do
        if tonumber(msg.dwarf_id) == id_num then
            table.remove(pending, i)
            messages.save_pending(pending)
            print("[MessageSystem] Removed message from dwarf " .. id_num)
            return true
        end
    end
    
    return false
end

-- ============================================================================
-- COUNT PENDING
-- ============================================================================

function messages.count_pending()
    local pending = messages.load_pending()
    return #pending
end

-- ============================================================================
-- CLEAR ALL (for debugging)
-- ============================================================================

function messages.clear_all()
    messages.save_pending({})
    print("[MessageSystem] Cleared all pending messages")
end

-- ============================================================================
-- EXPORT
-- ============================================================================

return messages