--@module = true
--[=====[

dwarftalk/event_history
=======================
Display narrative event history

]=====]

local gui = require('gui')
local widgets = require('gui.widgets')

-- ============================================================================
-- EventHistoryWindow
-- ============================================================================

EventHistoryWindow = defclass(EventHistoryWindow, gui.Screen)
EventHistoryWindow.ATTRS = {
    focus_path = 'dwarftalk_event_history',
}

function EventHistoryWindow:init()
    -- Load events
    local events = self:load_events()
    local narrative = self:events_to_narrative(events)
    
    self:addviews{
        widgets.Window{
            view_id = 'main_window',
            frame = {w = 80, h = 35, l = 5, t = 2},
            frame_title = 'Fortress Event Chronicle',
            resizable = true,
            resize_min = {w = 70, h = 30},
            subviews = {
                -- Header
                widgets.Label{
                    frame = {l = 1, t = 1},
                    text = {
                        {text = 'The Story of Your Fortress', pen = COLOR_LIGHTCYAN},
                    },
                },
                
                widgets.Label{
                    frame = {l = 1, t = 2},
                    text = 'AI-driven events that shaped your dwarves:',
                    text_pen = COLOR_GRAY,
                },
                
                -- Separator
                widgets.Label{
                    frame = {l = 1, t = 3, r = 1, h = 1},
                    text = string.rep('-', 76),
                    text_pen = COLOR_DARKGRAY,
                },
                
                -- Event list (scrollable)
                widgets.Label{
                    view_id = 'event_list',
                    frame = {l = 1, t = 5, r = 1, b = 3},
                    text = narrative,
                    text_wrap = true,
                },
                
                -- Separator
                widgets.Label{
                    frame = {l = 1, b = 2, r = 1, h = 1},
                    text = string.rep('-', 76),
                    text_pen = COLOR_DARKGRAY,
                },
                
                -- Close button
                widgets.HotkeyLabel{
                    view_id = 'close_btn',
                    frame = {l = 1, b = 0, w = 15},
                    label = '[ Close ]',
                    key = 'LEAVESCREEN',
                    on_activate = self:callback('dismiss'),
                    auto_width = false,
                },
                
                -- Stats
                widgets.Label{
                    view_id = 'stats',
                    frame = {r = 1, b = 0},
                    text = {{text = #events .. ' events recorded', pen = COLOR_GRAY}},
                },
            },
        },
    }
end

-- ============================================================================
-- LOAD EVENTS FROM LOG
-- ============================================================================

function EventHistoryWindow:load_events()
    local log_path = dfhack.getDFPath() .. '/dwarftalk_temp/action_log.txt'
    local events = {}
    
    local f = io.open(log_path, 'r')
    if not f then
        return events
    end
    
    local current_event = nil
    
    for line in f:lines() do
        -- Parse new format: "HH:MM:SS | dwarf_name | action_type"
        local time, dwarf, action_type = line:match("(%d+:%d+:%d+) | (.+) | (%w+)")
        
        if time and dwarf and action_type then
            current_event = {
                time = time,
                type = action_type,
                dwarf = dwarf,
            }
        elseif current_event and line:match("^%s+%->") then
        -- Get result (line starts with "  -> ")
        local result = line:match("->%s*(.+)")
        if result and not result:match("^ERROR") then
            current_event.result = result
            table.insert(events, current_event)
        end
        current_event = nil
        end
    end
    
    f:close()
    
    -- Reverse to show newest first
    local reversed = {}
    for i = #events, 1, -1 do
        table.insert(reversed, events[i])
    end
    
    -- Limit to last 30 events
    local limited = {}
    for i = 1, math.min(30, #reversed) do
        table.insert(limited, reversed[i])
    end
    
    return limited
end

-- ============================================================================
-- CONVERT EVENTS TO NARRATIVE
-- ============================================================================

function EventHistoryWindow:events_to_narrative(events)
    if #events == 0 then
        return {{text = 'No events recorded yet.\n\nStart talking to your dwarves to create stories!', pen = COLOR_GRAY}}
    end
    
    local narrative = {}
    local last_time = nil
    
    for _, event in ipairs(events) do
        -- Add time header if new time period
        if event.time ~= last_time then
            if last_time then
                table.insert(narrative, {text = '\n', pen = COLOR_WHITE})
            end
            table.insert(narrative, {text = '[' .. event.time .. ']\n', pen = COLOR_DARKGRAY})
            last_time = event.time
        end
        
        -- Generate narrative text based on event type
        local story = self:event_to_story(event)
        
        -- Add with color
        local color = self:get_event_color(event.type)
        table.insert(narrative, {text = '  ' .. story .. '\n', pen = color})
    end
    
    -- Add summary at the top
    local summary = self:generate_summary(events)
    if summary then
        table.insert(narrative, 1, {text = summary .. '\n\n', pen = COLOR_YELLOW})
    end
    
    return narrative
end

-- ============================================================================
-- EVENT TO STORY
-- ============================================================================

function EventHistoryWindow:event_to_story(event)
    local templates = {
        adjust_mood = {
            positive = {
                "%s felt encouraged by the conversation.",
                "%s's spirits lifted after a kind word.",
                "%s smiled, feeling appreciated.",
            },
            negative = {
                "%s was hurt by harsh words.",
                "%s's mood darkened after the exchange.",
                "%s felt discouraged and dejected.",
            },
        },
        change_job = {
            "%s decided to pursue a new calling as a %s.",
            "%s embraced their new role: %s.",
            "A career change: %s became a %s.",
        },
        refuse_work = {
            "%s REFUSED to work! The stress was too much.",
            "%s threw down their tools in frustration.",
            "%s could no longer continue. They need rest.",
        },
        assign_military = {
            "%s answered the call to arms.",
            "%s joined the fortress guard.",
            "%s took up weapons to defend the fortress.",
        },
        create_work_order = {
            "%s suggested we produce %s.",
            "%s requested %s for the fortress.",
            "%s recommended crafting %s.",
        },
    }
    
    local template_set = templates[event.type]
    if not template_set then
        return event.dwarf .. " - " .. event.type
    end
    
    -- For adjust_mood, check if positive or negative
    if event.type == "adjust_mood" then
        local is_positive = event.result and event.result:match("%+")
        local options = is_positive and template_set.positive or template_set.negative
        local template = options[math.random(#options)]
        return string.format(template, event.dwarf)
    end
    
    -- For change_job, extract job name
    if event.type == "change_job" then
        local job = event.result and event.result:match("Changed to (%w+)") or "unknown"
        local template = template_set[math.random(#template_set)]
        return string.format(template, event.dwarf, job)
    end
    
    -- For create_work_order, extract item
    if event.type == "create_work_order" then
        local item = event.result and event.result:match("Requested (.+)") or "items"
        local template = template_set[math.random(#template_set)]
        return string.format(template, event.dwarf, item)
    end
    
    -- Default: pick random template
    local template = template_set[math.random(#template_set)]
    return string.format(template, event.dwarf)
end

-- ============================================================================
-- GET EVENT COLOR
-- ============================================================================

function EventHistoryWindow:get_event_color(event_type)
    local colors = {
        adjust_mood = COLOR_LIGHTCYAN,
        change_job = COLOR_YELLOW,
        refuse_work = COLOR_LIGHTRED,
        assign_military = COLOR_RED,
        create_work_order = COLOR_LIGHTBLUE,
    }
    
    return colors[event_type] or COLOR_WHITE
end

-- ============================================================================
-- GENERATE SUMMARY
-- ============================================================================

function EventHistoryWindow:generate_summary(events)
    if #events < 5 then return nil end
    
    -- Count event types
    local counts = {}
    local dwarves = {}
    
    for _, event in ipairs(events) do
        counts[event.type] = (counts[event.type] or 0) + 1
        dwarves[event.dwarf] = true
    end
    
    local summary_parts = {}
    
    -- Mood changes
    if counts.adjust_mood and counts.adjust_mood >= 5 then
        table.insert(summary_parts, counts.adjust_mood .. " mood shifts")
    end
    
    -- Refusals
    if counts.refuse_work and counts.refuse_work >= 2 then
        table.insert(summary_parts, counts.refuse_work .. " work refusals (CRISIS!)")
    end
    
    -- Job changes
    if counts.change_job and counts.change_job >= 3 then
        table.insert(summary_parts, counts.change_job .. " career changes")
    end
    
    if #summary_parts == 0 then return nil end
    
    local dwarf_count = 0
    for _ in pairs(dwarves) do dwarf_count = dwarf_count + 1 end
    
    return "Recent activity: " .. table.concat(summary_parts, ", ") .. 
           " across " .. dwarf_count .. " dwarves."
end

-- ============================================================================
-- INPUT
-- ============================================================================

function EventHistoryWindow:onInput(keys)
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
-- LAUNCH
-- ============================================================================

function show_history()
    EventHistoryWindow{}:show()
end

return {
    EventHistoryWindow = EventHistoryWindow,
    show_history = show_history,
}