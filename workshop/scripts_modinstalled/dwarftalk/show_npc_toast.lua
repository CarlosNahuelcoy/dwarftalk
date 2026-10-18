-- Make sibling DwarfTalk modules require()-able no matter which script runs first
do
    local dir = debug.getinfo(1, 'S').source:match('^@(.+)[/\\][^/\\]+$')
    if dir and not package.path:find(dir .. '/?.lua', 1, true) then
        package.path = package.path .. ';' .. dir .. '/?.lua'
    end
end
local logger = require('debug_logger')

logger.section("NPC ANNOUNCEMENT")
logger.log("ANNOUNCE", "Script started")

local pending = _G.dwarftalk_pending_npc_conversation

if not pending then
    logger.log("ANNOUNCE", "No pending conversation")
    return
end

logger.log("ANNOUNCE", "Showing for: " .. pending.name1 .. " & " .. pending.name2)

-- Notificación simple que NO pausa
dfhack.gui.showAnnouncement(
    "" .. pending.name1 .. " & " .. pending.name2 .. " had a conversation",
    COLOR_CYAN,
    false
)

logger.log("ANNOUNCE", "Announcement shown")