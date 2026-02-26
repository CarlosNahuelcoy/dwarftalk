-- Test notification system with a fake message
local message_system = require('message_system')
local persistence = require('persistence')

-- Get a random dwarf from the fortress
local test_dwarf = nil
for _, unit in ipairs(df.global.world.units.active) do
    if dfhack.units.isCitizen(unit) and not dfhack.units.isDead(unit) then
        test_dwarf = unit
        break
    end
end

if not test_dwarf then
    print("No dwarves found in fortress!")
    return
end

-- Get dwarf info properly
local name = "Unknown Dwarf"
if test_dwarf.name.has_name then
    if test_dwarf.name.first_name ~= '' then
        name = test_dwarf.name.first_name
    end
    if test_dwarf.name.nickname ~= '' then
        if name ~= "Unknown Dwarf" then
            name = name .. ' "' .. test_dwarf.name.nickname .. '"'
        else
            name = '"' .. test_dwarf.name.nickname .. '"'
        end
    end
end

local dwarf_id = tonumber(test_dwarf.id)

-- Create test messages
local test_messages = {
    "I really need to pray soon. Haven't been able to focus on my work lately.",
    "Those goblins at the gates have me terrified. I can barely sleep at night.",
    "I haven't had a proper drink in days! My throat is parched.",
    "Just wanted to say the new dining hall looks amazing. Great work!",
    "I've been feeling pretty stressed lately. Could we talk about it?",
    "Have you seen how beautiful the sky is today? Makes me happy to be alive.",
    "I'm worried about the food stores. Are we going to have enough for winter?",
    "That artifact I made last week... I'm still proud of it!",
}

-- Pick random message
local message = test_messages[math.random(#test_messages)]

-- ============================================================================
-- SAVE TO CHAT HISTORY (same as message_generator)
-- ============================================================================

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
table.insert(chat_messages, name .. ': ' .. wrapped)

table.insert(conversation_history, {
    role = 'assistant',
    content = message
})

-- Save to chat history
local success = persistence.save_conversation(dwarf_id, chat_messages, conversation_history)

if success then
    print("[TestNotification] ✓ Message saved to chat history")
else
    print("[TestNotification] ✗ Failed to save to chat history")
end

-- ============================================================================
-- ADD TO PENDING NOTIFICATIONS
-- ============================================================================

-- Add to pending
message_system.add_message(dwarf_id, name, message)

print("===========================================")
print("TEST NOTIFICATION CREATED")
print("===========================================")
print("From: " .. name)
print("ID: " .. dwarf_id)
print("Message: " .. message)
print("")
print("Run: dwarftalk/show_notification")
print("===========================================")