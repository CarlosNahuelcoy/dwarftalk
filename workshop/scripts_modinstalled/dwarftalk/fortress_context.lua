--@module = true
--[=====[

dwarftalk/fortress_context
===========================
Extracts and caches fortress world context for AI conversations
Cache stored in dwarftalk_saves/ alongside conversation data

]=====]

local json = nil
for _, lib in ipairs({'json', 'dkjson', 'cjson'}) do
    local success, result = pcall(require, lib)
    if success then
        json = result
        break
    end
end

local context = {}

-- Configuration
local CACHE_TTL = 30 -- Cache valid for 30 seconds
local saves_dir = dfhack.getDFPath() .. '/dwarftalk_saves/'
local context_cache_path = saves_dir .. 'fortress_context.json'

-- Safe field access helper
local function safe_get(obj, ...)
    local current = obj
    for _, key in ipairs({...}) do
        if not current then return nil end
        local ok, value = pcall(function() return current[key] end)
        if not ok then return nil end
        current = value
    end
    return current
end

-- ============================================================================
-- RECENT DEATHS
-- ============================================================================

function context.get_recent_deaths(days)
    days = days or 7
    local deaths = {}
    
    local ok = pcall(function()
        local current_time = df.global.cur_year * 403200 + df.global.cur_year_tick
        local cutoff_time = current_time - (days * 1200)
        
        for _, unit in ipairs(df.global.world.units.active) do
            if dfhack.units.isDead(unit) and dfhack.units.isCitizen(unit) then
                local incident_id = safe_get(unit, 'counters', 'death_id')
                
                if not incident_id or incident_id == -1 then goto continue end
                
                local death_event = df.incident.find(incident_id)
                if not death_event then goto continue end
                
                local death_time = death_event.event_year * 403200 + death_event.event_time
                
                if death_time >= cutoff_time then
                    local name = "Unknown Dwarf"
                    if unit.name and unit.name.has_name and unit.name.first_name ~= '' then
                        name = unit.name.first_name
                    end
                    
                    local profession = "Dwarf"
                    local prof_ok, prof = pcall(dfhack.units.getProfessionName, unit)
                    if prof_ok and prof then
                        profession = prof
                    end
                    
                    table.insert(deaths, {
                        name = name,
                        profession = profession,
                        days_ago = math.floor((current_time - death_time) / 1200)
                    })
                end
                
                ::continue::
            end
        end
    end)
    
    if not ok then
        return {}
    end
    
    table.sort(deaths, function(a, b) return a.days_ago < b.days_ago end)
    
    return deaths
end

-- ============================================================================
-- FORTRESS MOOD
-- ============================================================================

function context.get_fortress_mood()
    local stressed = 0
    local happy = 0
    local total = 0
    
    local ok = pcall(function()
        for _, unit in ipairs(df.global.world.units.active) do
            if dfhack.units.isCitizen(unit) and not dfhack.units.isDead(unit) then
                local soul = safe_get(unit, 'status', 'current_soul')
                if soul then
                    total = total + 1
                    local stress = safe_get(soul, 'personality', 'stress') or 0
                    
                    if stress > 100000 then
                        stressed = stressed + 1
                    elseif stress < 0 then
                        happy = happy + 1
                    end
                end
            end
        end
    end)
    
    if not ok or total == 0 then return "unknown" end
    
    local stress_ratio = stressed / total
    local happy_ratio = happy / total
    
    if stress_ratio > 0.3 then
        return "stressed and unhappy"
    elseif stress_ratio > 0.15 then
        return "somewhat stressed"
    elseif happy_ratio > 0.5 then
        return "content and happy"
    else
        return "stable"
    end
end

-- ============================================================================
-- CURRENT SEASON
-- ============================================================================

function context.get_current_season()
    local season_names = {"Spring", "Summer", "Autumn", "Winter"}
    
    local ok, result = pcall(function()
        local season = df.global.cur_season
        local year = df.global.cur_year
        
        return {
            name = season_names[season + 1] or "Unknown",
            year = year,
            full = season_names[season + 1] .. " of year " .. year
        }
    end)
    
    if ok then
        return result
    else
        return {
            name = "Unknown",
            year = 0,
            full = "Unknown season"
        }
    end
end

-- ============================================================================
-- FORTRESS WEALTH (safe version)
-- ============================================================================

function context.get_fortress_wealth()
    -- Try multiple possible fields for wealth
    local wealth = safe_get(df.global, 'created_item_value')
    
    if not wealth then
        wealth = safe_get(df.global, 'world', 'world_data', 'created_item_value')
    end
    
    if not wealth then
        -- Try counting items as fallback
        local item_count = 0
        local ok = pcall(function()
            for _, item in ipairs(df.global.world.items.all) do
                item_count = item_count + 1
            end
        end)
        
        if ok and item_count > 0 then
            -- Rough estimate based on item count
            if item_count < 500 then
                return "poor"
            elseif item_count < 2000 then
                return "modest"
            elseif item_count < 5000 then
                return "prosperous"
            elseif item_count < 10000 then
                return "wealthy"
            else
                return "incredibly wealthy"
            end
        end
        
        return "unknown"
    end
    
    -- Use actual wealth value if found
    if wealth < 5000 then
        return "poor"
    elseif wealth < 25000 then
        return "modest"
    elseif wealth < 100000 then
        return "prosperous"
    elseif wealth < 500000 then
        return "wealthy"
    else
        return "incredibly wealthy"
    end
end

-- ============================================================================
-- POPULATION
-- ============================================================================

function context.get_population()
    local count = 0
    
    local ok = pcall(function()
        for _, unit in ipairs(df.global.world.units.active) do
            if dfhack.units.isCitizen(unit) and not dfhack.units.isDead(unit) then
                count = count + 1
            end
        end
    end)
    
    if not ok then
        return 0
    end
    
    return count
end

-- ============================================================================
-- CURRENT THREATS
-- ============================================================================

function context.check_current_threats()
    local threats = {
        siege = false,
        ambush = false,
        invaders_count = 0,
    }
    
    local ok = pcall(function()
        for _, unit in ipairs(df.global.world.units.active) do
            if safe_get(unit, 'flags1', 'hidden_ambusher') then
                threats.ambush = true
            end
            
            if dfhack.units.isInvader(unit) then
                threats.siege = true
                threats.invaders_count = threats.invaders_count + 1
            end
        end
    end)
    
    return threats
end

-- ============================================================================
-- GENERATE FULL CONTEXT
-- ============================================================================

function context.generate_context()
    local ctx = {
        season = context.get_current_season(),
        population = context.get_population(),
        fortress_mood = context.get_fortress_mood(),
        wealth = context.get_fortress_wealth(),
        recent_deaths = context.get_recent_deaths(7),
        threats = context.check_current_threats(),
        generated_at = os.date("%Y-%m-%d %H:%M:%S"),
        generated_timestamp = os.time(),
    }
    
    return ctx
end

-- ============================================================================
-- SAVE TO JSON
-- ============================================================================

function context.save_context_to_json(ctx)
    if not json then return false end
    
    local json_data = json.encode(ctx)
    
    local f = io.open(context_cache_path, 'w')
    if not f then return false end
    
    f:write(json_data)
    f:close()
    
    return true
end

-- ============================================================================
-- LOAD FROM JSON
-- ============================================================================

function context.load_context_from_json()
    if not json then return nil end
    
    local f = io.open(context_cache_path, 'r')
    if not f then return nil end
    
    local json_data = f:read('*all')
    f:close()
    
    if not json_data or json_data == '' then return nil end
    
    local ok, ctx = pcall(json.decode, json_data)
    if not ok or not ctx then return nil end
    
    return ctx
end

-- ============================================================================
-- GET CONTEXT (with smart caching)
-- ============================================================================

function context.get_fortress_context()
    -- Try to load from cache
    local cached = context.load_context_from_json()
    
    if cached and cached.generated_timestamp then
        local age = os.time() - cached.generated_timestamp
        
        if age < CACHE_TTL then
            return cached
        end
    end
    
    -- Generate fresh context
    local ctx = context.generate_context()
    
    -- Save to cache
    context.save_context_to_json(ctx)
    
    return ctx
end

-- ============================================================================
-- CONTEXT TO TEXT (for AI prompts)
-- ============================================================================

function context.context_to_text(ctx)
    if not ctx then return "" end
    
    local lines = {}
    
    table.insert(lines, "=== FORTRESS CONTEXT ===")
    table.insert(lines, "")
    
    table.insert(lines, "TIME & STATUS:")
    table.insert(lines, "- Current time: " .. (ctx.season.full or "Unknown"))
    table.insert(lines, "- Population: " .. (ctx.population or 0) .. " dwarves")
    
    if ctx.fortress_mood and ctx.fortress_mood ~= "unknown" then
        table.insert(lines, "- Overall mood: " .. ctx.fortress_mood)
    end
    
    if ctx.wealth and ctx.wealth ~= "unknown" then
        table.insert(lines, "- Fortress wealth: " .. ctx.wealth)
    end
    
    if ctx.recent_deaths and #ctx.recent_deaths > 0 then
        table.insert(lines, "")
        table.insert(lines, "RECENT TRAGIC LOSSES:")
        for i = 1, math.min(3, #ctx.recent_deaths) do
            local death = ctx.recent_deaths[i]
            local days_text = death.days_ago == 0 and "today" or death.days_ago == 1 and "yesterday" or (death.days_ago .. " days ago")
            table.insert(lines, "- " .. death.name .. " (" .. death.profession .. ") died " .. days_text)
        end
    end
    
    if ctx.threats and (ctx.threats.siege or ctx.threats.ambush) then
        table.insert(lines, "")
        table.insert(lines, "! CURRENT THREATS:") -- ⚠ cambiado a !
        if ctx.threats.siege then
            local invader_text = ctx.threats.invaders_count > 0 and (" (" .. ctx.threats.invaders_count .. " invaders)") or ""
            table.insert(lines, "- The fortress is under SIEGE!" .. invader_text)
        end
        if ctx.threats.ambush then
            table.insert(lines, "- Hidden ambushers detected nearby!")
        end
    end
    
    table.insert(lines, "")
    table.insert(lines, "========================")
    
    return table.concat(lines, "\n")
end
-- ============================================================================
-- EXPORT
-- ============================================================================

return context