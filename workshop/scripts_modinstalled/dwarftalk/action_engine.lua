--@module = true

local action_engine = {}
local logger = require('debug_logger')

-- Log helper
local function log_action(message)
    local log_file = dfhack.getDFPath() .. '/dwarftalk_temp/action_log.txt'
    local f = io.open(log_file, 'a')
    if f then
        f:write(os.date("%H:%M:%S") .. " | " .. message .. "\n")
        f:close()
    end
end

-- ============================================================================
-- EXECUTE ACTION IN WORLD
-- ============================================================================

function action_engine.execute(dwarf_info, action)
    logger.section("ACTION ENGINE EXECUTE")
    logger.log("ACTION", "Type: " .. tostring(action and action.type or "nil"))
    logger.log("ACTION", "Dwarf: " .. tostring(dwarf_info and dwarf_info.name or "nil"))
    
    if not action or not action.type then 
        logger.log("ACTION", "ERROR: No action or type")
        return nil
    end
    
    log_action(dwarf_info.name .. " | " .. action.type)
    logger.log("ACTION", "Logged to action_log.txt")
    
    local handlers = {
        change_job        = action_engine.change_job,
        adjust_mood       = action_engine.adjust_mood,
        create_work_order = action_engine.create_work_order,
        refuse_work       = action_engine.refuse_work,
        assign_military   = action_engine.assign_military,
    }
    
    local handler = handlers[action.type]
    if handler then
        logger.log("ACTION", "Calling handler for: " .. action.type)
        
        local ok, result = pcall(handler, dwarf_info, action)
        
        logger.log("ACTION", "Handler returned - ok: " .. tostring(ok))
        logger.log("ACTION", "Handler returned - result: " .. tostring(result))
        
        if ok and result then
            log_action("  -> " .. tostring(result))
            logger.log("ACTION", "SUCCESS - Returning: " .. tostring(result))
            return result
        else
            logger.log("ACTION", "ERROR in handler: " .. tostring(result))
            return nil
        end
    else
        logger.log("ACTION", "ERROR: Unknown action type")
        return nil
    end
end

-- ============================================================================
-- ADJUST MOOD - Narrative variations
-- ============================================================================

function action_engine.adjust_mood(dwarf_info, action)
    local unit = dwarf_info.unit
    if not unit then return nil end
    
    local change = action.amount or 0
    
    if not unit.status then return nil end
    if not unit.status.current_soul then return nil end
    
    local soul = unit.status.current_soul
    if not soul.personality then return nil end
    
    local old_stress = soul.personality.stress or 0
    local stress_delta = change * -50000
    local new_stress = math.max(-500000, math.min(500000, old_stress + stress_delta))
    soul.personality.stress = math.floor(new_stress)
    
    -- NARRATIVE MESSAGES (no notifications)
    if change > 0 then
        local positive = {
            dwarf_info.name .. " smiled warmly, clearly touched by your words.",
            "A genuine grin spread across " .. dwarf_info.name .. "'s face.",
            dwarf_info.name .. " stood a bit taller, pride evident in their posture.",
            "You could see the weight lift from " .. dwarf_info.name .. "'s shoulders.",
            dwarf_info.name .. "'s eyes brightened with renewed hope.",
            "For a moment, " .. dwarf_info.name .. " forgot their troubles entirely.",
            dwarf_info.name .. " chuckled, a rare sound these days.",
            "The conversation seemed to rekindle " .. dwarf_info.name .. "'s spirits.",
            dwarf_info.name .. " nodded thoughtfully, appearing more at peace.",
            "You caught " .. dwarf_info.name .. " humming as they turned away.",
            dwarf_info.name .. " clasped your shoulder gratefully before heading off.",
            "The tension visibly drained from " .. dwarf_info.name .. "'s expression.",
        }
        return positive[math.random(#positive)]
    else
        local negative = {
            dwarf_info.name .. "'s expression darkened noticeably.",
            "You could see hurt flash across " .. dwarf_info.name .. "'s face.",
            dwarf_info.name .. " looked away, jaw clenched tight.",
            "The joy faded from " .. dwarf_info.name .. "'s eyes.",
            dwarf_info.name .. " muttered something under their breath and walked off.",
            "Your words seemed to strike " .. dwarf_info.name .. " like a hammer blow.",
            dwarf_info.name .. " shook their head, clearly wounded.",
            "You watched " .. dwarf_info.name .. "'s shoulders slump in defeat.",
            dwarf_info.name .. " turned away quickly, but not before you saw the pain.",
            "The conversation left " .. dwarf_info.name .. " visibly upset.",
            dwarf_info.name .. " clenched their fists, struggling to contain frustration.",
            "You could practically feel the mood shift as " .. dwarf_info.name .. " grew bitter.",
        }
        return negative[math.random(#negative)]
    end
end

-- ============================================================================
-- CHANGE JOB - Narrative variations
-- ============================================================================

function action_engine.change_job(dwarf_info, action)
    local unit = dwarf_info.unit
    if not unit then return nil end
    
    local new_job = action.job
    if not new_job then return nil end
    
    local labor_map = {
        miner       = df.unit_labor.MINE,
        woodcutter  = df.unit_labor.CUTWOOD,
        carpenter   = df.unit_labor.CARPENTER,
        mason       = df.unit_labor.MASON,
        farmer      = df.unit_labor.PLANT,
        cook        = df.unit_labor.COOK,
        brewer      = df.unit_labor.BREW,
        smith       = df.unit_labor.SMELT,
        weaponsmith = df.unit_labor.FORGE_WEAPON,
        armorsmith  = df.unit_labor.FORGE_ARMOR,
        doctor      = df.unit_labor.DIAGNOSE,
        fisherdwarf = df.unit_labor.FISH,
    }
    
    local labor = labor_map[new_job:lower()]
    if not labor then return nil end
    
    -- Disable all current jobs, enable new one
    for i = 0, #unit.status.labors - 1 do
        unit.status.labors[i] = false
    end
    unit.status.labors[labor] = true
    
    -- NARRATIVE MESSAGES
    local messages = {
        dwarf_info.name .. " decided to pursue a new calling as a " .. new_job .. ".",
        "After much reflection, " .. dwarf_info.name .. " embraced the path of a " .. new_job .. ".",
        dwarf_info.name .. " felt a spark of excitement at becoming a " .. new_job .. ".",
        "The idea of working as a " .. new_job .. " resonated deeply with " .. dwarf_info.name .. ".",
        dwarf_info.name .. " walked away with new purpose, ready to begin as a " .. new_job .. ".",
        "A career change seemed right - " .. dwarf_info.name .. " would become a " .. new_job .. ".",
        dwarf_info.name .. " nodded firmly, committing to the life of a " .. new_job .. ".",
    }
    
    return messages[math.random(#messages)]
end

-- ============================================================================
-- CREATE WORK ORDER - Narrative variations
-- ============================================================================

function action_engine.create_work_order(dwarf_info, action)
    local item = action.item or "unknown"
    local quantity = action.quantity or 1
    
    local messages = {
        dwarf_info.name .. " suggested producing " .. quantity .. "x " .. item .. " for the fortress.",
        "After some thought, " .. dwarf_info.name .. " recommended crafting " .. quantity .. "x " .. item .. ".",
        dwarf_info.name .. " made a compelling case for " .. quantity .. "x " .. item .. ".",
        "The fortress could really use " .. quantity .. "x " .. item .. ", " .. dwarf_info.name .. " pointed out.",
        dwarf_info.name .. " respectfully requested " .. quantity .. "x " .. item .. " be made.",
        "Perhaps we should produce " .. quantity .. "x " .. item .. "? " .. dwarf_info.name .. " suggested.",
    }
    
    return messages[math.random(#messages)]
end

-- ============================================================================
-- REFUSE WORK - Narrative variations
-- ============================================================================

function action_engine.refuse_work(dwarf_info, action)
    local unit = dwarf_info.unit
    if not unit then return nil end
    
    local reason = action.reason or "unhappy"
    
    -- Increase stress significantly
    if unit.status and unit.status.current_soul then
        local soul = unit.status.current_soul
        if soul.personality then
            local current = soul.personality.stress or 0
            soul.personality.stress = math.min(500000, current + 150000)
        end
    end
    
    -- Disable all jobs
    for i = 0, #unit.status.labors - 1 do
        unit.status.labors[i] = false
    end
    
    -- DRAMATIC NARRATIVE
    local messages = {
        dwarf_info.name .. " threw down their tools and stormed off!",
        "That was the final straw - " .. dwarf_info.name .. " REFUSED to work!",
        dwarf_info.name .. " shouted something about quitting and stalked away.",
        "You've pushed " .. dwarf_info.name .. " too far - they won't work anymore!",
        dwarf_info.name .. " declared they were DONE and abandoned their post!",
        "With a furious glare, " .. dwarf_info.name .. " walked away from all duties.",
        dwarf_info.name .. " couldn't take it anymore - they're refusing all work!",
    }
    
    return messages[math.random(#messages)]
end

-- ============================================================================
-- ASSIGN TO MILITARY - Narrative variations
-- ============================================================================

function action_engine.assign_military(dwarf_info, action)
    local unit = dwarf_info.unit
    if not unit then return nil end
    
    -- Enable military labor
    unit.status.labors[df.unit_labor.MILITARY] = true
    
    -- Keep only essential + military
    local essential = {
        [df.unit_labor.HAUL_FOOD] = true,
        [df.unit_labor.HAUL_WATER] = true,
        [df.unit_labor.MILITARY] = true,
    }
    
    for i = 0, #unit.status.labors - 1 do
        if not essential[i] then
            unit.status.labors[i] = false
        end
    end
    
    -- HEROIC NARRATIVE
    local messages = {
        dwarf_info.name .. " answered the call to arms with determination.",
        "A fire lit in " .. dwarf_info.name .. "'s eyes - they joined the fortress guard!",
        dwarf_info.name .. " took up weapons, ready to defend the fortress.",
        "The fortress needed defenders, and " .. dwarf_info.name .. " stepped forward.",
        dwarf_info.name .. " enlisted in the military, oath of protection sworn.",
        "From this day forward, " .. dwarf_info.name .. " serves as a soldier.",
        dwarf_info.name .. " felt the weight of duty - they would become a warrior.",
    }
    
    return messages[math.random(#messages)]
end

return action_engine