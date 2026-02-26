--@module = true
--[=====[

dwarftalk/analyze_dwarf
=======================
Deep analysis of dwarf data for better AI conversations

Usage::

    dwarftalk/analyze_dwarf         - Analyze selected dwarf
    dwarftalk/analyze_dwarf all     - Analyze all dwarves
    dwarftalk/analyze_dwarf random  - Analyze random dwarf

]=====]

-- Load JSON
local json = nil
for _, lib in ipairs({'json', 'dkjson', 'cjson'}) do
    local success, result = pcall(require, lib)
    if success then
        json = result
        break
    end
end

if not json then
    qerror("No JSON library found! Cannot save analysis.")
end

local analyzer = {}

-- Safe field access
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
-- BASIC INFO
-- ============================================================================

function analyzer.get_name(unit)
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
    
    return name
end

-- ============================================================================
-- PERSONALITY - COMPLETE WITH NARRATIVE DESCRIPTIONS
-- ============================================================================

function analyzer.generate_personality_narrative(traits)
    local narratives = {}
    
    -- Fear and bravery
    if traits.bravery then
        if traits.bravery < 15 then
            table.insert(narratives, "is a coward, completely overwhelmed by fear when confronted with danger")
        elseif traits.bravery < 35 then
            table.insert(narratives, "is nervous and fearful in dangerous situations")
        elseif traits.bravery > 85 then
            table.insert(narratives, "is utterly fearless when confronted with danger")
        elseif traits.bravery > 65 then
            table.insert(narratives, "is brave in the face of imminent danger")
        end
    end
    
    -- Abstract thinking
    if traits.abstract_inclined then
        if traits.abstract_inclined > 75 then
            table.insert(narratives, "strongly prefers discussions of ideas and abstract concepts over handling specific practical issues")
        elseif traits.abstract_inclined < 25 then
            table.insert(narratives, "strongly dislikes abstract discussions and would much rather focus on practical examples")
        end
    end
    
    -- Social preferences
    if traits.gregariousness then
        if traits.gregariousness > 75 then
            table.insert(narratives, "loves to be in crowds and around others")
        elseif traits.gregariousness < 25 then
            table.insert(narratives, "tends to avoid crowds and prefers to be alone")
        end
    end
    
    -- Anxiety
    if traits.anxiety_propensity then
        if traits.anxiety_propensity > 75 then
            table.insert(narratives, "is constantly nervous and jittery")
        elseif traits.anxiety_propensity < 25 then
            table.insert(narratives, "is very calm and rarely feels anxious")
        end
    end
    
    -- Anger
    if traits.anger_propensity then
        if traits.anger_propensity > 75 then
            table.insert(narratives, "is very quick to anger")
        elseif traits.anger_propensity < 25 then
            table.insert(narratives, "is very slow to anger")
        end
    end
    
    -- Politeness
    if traits.politeness then
        if traits.politeness > 75 then
            table.insert(narratives, "is quite polite and tends to be very courteous")
        elseif traits.politeness < 25 then
            table.insert(narratives, "is very rude and inconsiderate of others' feelings")
        end
    end
    
    -- Confidence
    if traits.confidence then
        if traits.confidence > 75 then
            table.insert(narratives, "has a great sense of self-confidence")
        elseif traits.confidence < 25 then
            table.insert(narratives, "lacks confidence in their abilities")
        end
    end
    
    -- Pride
    if traits.pride then
        if traits.pride > 75 then
            table.insert(narratives, "is very proud and egotistical")
        elseif traits.pride < 25 then
            table.insert(narratives, "is quite humble")
        end
    end
    
    -- Dutifulness
    if traits.dutifulness then
        if traits.dutifulness > 75 then
            table.insert(narratives, "has a strong sense of duty")
        elseif traits.dutifulness < 25 then
            table.insert(narratives, "finds obligations confining")
        end
    end
    
    -- Orderliness
    if traits.orderliness then
        if traits.orderliness > 75 then
            table.insert(narratives, "is very organized and likes to keep things orderly")
        elseif traits.orderliness < 25 then
            table.insert(narratives, "is sloppy and disorganized")
        end
    end
    
    -- Trust
    if traits.trust then
        if traits.trust > 75 then
            table.insert(narratives, "trusts others easily")
        elseif traits.trust < 25 then
            table.insert(narratives, "is very suspicious of others")
        end
    end
    
    -- Perfectionist
    if traits.perfectionist then
        if traits.perfectionist > 75 then
            table.insert(narratives, "is obsessed with details and will often get in their own way")
        elseif traits.perfectionist < 25 then
            table.insert(narratives, "doesn't try to get things done perfectly")
        end
    end
    
    -- Singleminded
    if traits.singleminded then
        if traits.singleminded > 75 then
            table.insert(narratives, "can be very single-minded")
        elseif traits.singleminded < 25 then
            table.insert(narratives, "tends to be somewhat scatterbrained")
        end
    end
    
    -- Discord vs Harmony
    if traits.discord then
        if traits.discord > 75 then
            table.insert(narratives, "finds merrymaking and partying worthwhile activities")
        elseif traits.discord < 25 then
            table.insert(narratives, "finds merrymaking and partying worthwhile activities") 
        end
    end
    
    -- Cheerfulness
    if traits.cheer_propensity then
        if traits.cheer_propensity > 75 then
            table.insert(narratives, "often feels cheerful")
        elseif traits.cheer_propensity < 25 then
            table.insert(narratives, "is often sad and dejected")
        end
    end
    
    -- Cruelty
    if traits.cruelty then
        if traits.cruelty > 75 then
            table.insert(narratives, "is deliberately cruel to those who annoy them")
        elseif traits.cruelty < 25 then
            table.insert(narratives, "is repelled by cruelty")
        end
    end
    
    -- Ambition
    if traits.ambition then
        if traits.ambition > 75 then
            table.insert(narratives, "is quite ambitious")
        elseif traits.ambition < 25 then
            table.insert(narratives, "lacks ambition")
        end
    end
    
    return narratives
end

function analyzer.get_personality_deep(unit)
    local personality = {
        raw_traits = {},
        personality_summary = "",
        narrative_description = {},
        key_traits = {},
        social_style = "",
        work_style = "",
        emotional_style = "",
    }
    
    local soul = safe_get(unit, 'status', 'current_soul')
    if not soul then return personality end
    
    local p = safe_get(soul, 'personality', 'traits')
    if not p then return personality end
    
    -- Collect all traits
    local traits = {}
    for i = 0, 49 do
        local value = safe_get(p, i)
        if value then
            local trait_name = df.personality_facet_type[i]
            if trait_name then
                local name_str = tostring(trait_name):lower()
                traits[name_str] = value
            end
        end
    end
    
    personality.raw_traits = traits
    
    -- Generate narrative descriptions (like DF does)
    personality.narrative_description = analyzer.generate_personality_narrative(traits)
    
    -- Analyze emotional style
    local emotional_traits = {}
    if traits.anxiety_propensity then
        if traits.anxiety_propensity > 65 then
            table.insert(emotional_traits, "very anxious and worried")
        elseif traits.anxiety_propensity < 35 then
            table.insert(emotional_traits, "calm and unflappable")
        end
    end
    
    if traits.anger_propensity then
        if traits.anger_propensity > 65 then
            table.insert(emotional_traits, "quick-tempered")
        elseif traits.anger_propensity < 35 then
            table.insert(emotional_traits, "slow to anger")
        end
    end
    
    if traits.cheer_propensity then
        if traits.cheer_propensity > 65 then
            table.insert(emotional_traits, "cheerful and optimistic")
        elseif traits.cheer_propensity < 35 then
            table.insert(emotional_traits, "pessimistic and gloomy")
        end
    end
    
    if traits.depression_propensity then
        if traits.depression_propensity > 65 then
            table.insert(emotional_traits, "prone to depression")
        end
    end
    
    personality.emotional_style = table.concat(emotional_traits, ", ")
    
    -- Analyze social style
    local social_traits = {}
    if traits.friendliness then
        if traits.friendliness > 65 then
            table.insert(social_traits, "warm and friendly")
        elseif traits.friendliness < 35 then
            table.insert(social_traits, "cold and unfriendly")
        end
    end
    
    if traits.gregariousness then
        if traits.gregariousness > 65 then
            table.insert(social_traits, "loves socializing")
        elseif traits.gregariousness < 35 then
            table.insert(social_traits, "prefers solitude")
        end
    end
    
    if traits.assertiveness then
        if traits.assertiveness > 65 then
            table.insert(social_traits, "assertive and commanding")
        elseif traits.assertiveness < 35 then
            table.insert(social_traits, "passive and submissive")
        end
    end
    
    if traits.politeness then
        if traits.politeness > 65 then
            table.insert(social_traits, "polite and courteous")
        elseif traits.politeness < 35 then
            table.insert(social_traits, "rude and abrasive")
        end
    end
    
    personality.social_style = table.concat(social_traits, ", ")
    
    -- Analyze work style
    local work_traits = {}
    if traits.dutifulness then
        if traits.dutifulness > 65 then
            table.insert(work_traits, "dutiful and reliable")
        elseif traits.dutifulness < 35 then
            table.insert(work_traits, "shirks duties")
        end
    end
    
    if traits.ambition then
        if traits.ambition > 65 then
            table.insert(work_traits, "ambitious and driven")
        elseif traits.ambition < 35 then
            table.insert(work_traits, "unmotivated")
        end
    end
    
    if traits.orderliness then
        if traits.orderliness > 65 then
            table.insert(work_traits, "organized and methodical")
        elseif traits.orderliness < 35 then
            table.insert(work_traits, "messy and chaotic")
        end
    end
    
    if traits.perfectionist then
        if traits.perfectionist > 65 then
            table.insert(work_traits, "perfectionist")
        end
    end
    
    personality.work_style = table.concat(work_traits, ", ")
    
    -- Key standout traits
    for trait_name, value in pairs(traits) do
        if value > 75 or value < 25 then
            table.insert(personality.key_traits, {
                trait = trait_name,
                value = value,
                extreme = value > 75 and "very high" or "very low"
            })
        end
    end
    
    -- Generate summary
    local summary_parts = {}
    if personality.emotional_style ~= "" then
        table.insert(summary_parts, personality.emotional_style)
    end
    if personality.social_style ~= "" then
        table.insert(summary_parts, personality.social_style)
    end
    if personality.work_style ~= "" then
        table.insert(summary_parts, personality.work_style)
    end
    
    personality.personality_summary = table.concat(summary_parts, ". ")
    
    return personality
end

-- ============================================================================
-- PREFERENCES - COMPLETE AND DETAILED
-- ============================================================================

function analyzer.get_preferences_detailed(unit)
    local prefs = {
        likes_material = {},
        likes_creature = {},
        likes_color = {},
        likes_food = {},
        likes_item = {},
        likes_plant = {},
        dislikes = {},
        count = 0
    }
    
    local soul = safe_get(unit, 'status', 'current_soul')
    if not soul then return prefs end
    
    local preferences = safe_get(soul, 'preferences')
    if not preferences then return prefs end
    
    for _, pref in ipairs(preferences) do
        prefs.count = prefs.count + 1
        
        local active = safe_get(pref, 'active')
        if active == false then
            goto continue
        end
        
        local pref_type_raw = safe_get(pref, 'type')
        if not pref_type_raw then goto continue end
        
        local pref_type = nil
        local pref_type_enum = safe_get(df, 'unit_preference', 'T_type')
        if pref_type_enum then
            pref_type = pref_type_enum[pref_type_raw]
        end
        
        if not pref_type then goto continue end
        
        local pref_type_str = tostring(pref_type)
        
        -- Check if it's a dislike
        local dislikes = safe_get(pref, 'dislikes')
        
        -- Material preference
        if pref_type_str == "LikeMaterial" then
            local mat_type = safe_get(pref, 'mat_type')
            local mat_index = safe_get(pref, 'mat_index')
            if mat_type and mat_type >= 0 then
                local ok, mat = pcall(dfhack.matinfo.decode, mat_type, mat_index)
                if ok and mat then
                    local mat_name = mat:toString()
                    if dislikes then
                        table.insert(prefs.dislikes, mat_name)
                    else
                        table.insert(prefs.likes_material, mat_name)
                    end
                end
            end
        
        -- Creature preference
        elseif pref_type_str == "LikeCreature" then
            local creature_id = safe_get(pref, 'creature_id')
            if creature_id and creature_id >= 0 and creature_id < #df.global.world.raws.creatures.all then
                local creature = df.global.world.raws.creatures.all[creature_id]
                if creature and creature.name then
                    local creature_name = creature.name[0]
                    if dislikes then
                        table.insert(prefs.dislikes, creature_name)
                    else
                        table.insert(prefs.likes_creature, creature_name)
                    end
                end
            end
        
        -- Color preference
        elseif pref_type_str == "LikeColor" then
            local color_id = safe_get(pref, 'color_id')
            if color_id then
                local color_name = df.descriptor_color[color_id]
                if color_name then
                    local color_str = tostring(color_name):lower()
                    if dislikes then
                        table.insert(prefs.dislikes, "the color " .. color_str)
                    else
                        table.insert(prefs.likes_color, color_str)
                    end
                end
            end
        
        -- Plant preference
        elseif pref_type_str == "LikePlant" then
            local plant_id = safe_get(pref, 'plant_id')
            if plant_id and plant_id >= 0 and plant_id < #df.global.world.raws.plants.all then
                local plant = df.global.world.raws.plants.all[plant_id]
                if plant and plant.name then
                    local plant_name = plant.name
                    if dislikes then
                        table.insert(prefs.dislikes, plant_name)
                    else
                        table.insert(prefs.likes_plant, plant_name)
                    end
                end
            end
        
        -- Food preferences
        elseif pref_type_str:find("Food") or pref_type_str:find("Drink") then
            local detail = pref_type_str:gsub("Like", ""):lower()
            if dislikes then
                table.insert(prefs.dislikes, detail)
            else
                table.insert(prefs.likes_food, detail)
            end
        
        -- Item preferences
        elseif pref_type_str:find("Item") then
            local item_type = safe_get(pref, 'item_type')
            if item_type then
                local item_name = df.item_type[item_type]
                if item_name then
                    local item_str = tostring(item_name):lower():gsub("_", " ")
                    if dislikes then
                        table.insert(prefs.dislikes, item_str)
                    else
                        table.insert(prefs.likes_item, item_str)
                    end
                end
            end
        end
        
        ::continue::
    end
    
    return prefs
end

-- ============================================================================
-- VALUES AND BELIEFS - COMPLETE
-- ============================================================================

function analyzer.get_values_complete(unit)
    local values = {
        strong_values = {},
        all_values = {},
        cultural_descriptions = {}
    }
    
    local soul = safe_get(unit, 'status', 'current_soul')
    if not soul then return values end
    
    local personality_values = safe_get(soul, 'personality', 'values')
    if not personality_values then return values end
    
    -- Value type descriptions
    local value_descriptions = {
        LAW = {pos = "has a great deal of respect for the law", neg = "does not respect the law"},
        LOYALTY = {pos = "values loyalty", neg = "does not value loyalty"},
        FAMILY = {pos = "values family greatly", neg = "does not care about family"},
        FRIENDSHIP = {pos = "values friendship", neg = "does not care much about friendship"},
        POWER = {pos = "values power over others", neg = "sees power over others as corrupt"},
        TRUTH = {pos = "values honesty", neg = "finds blind honesty foolish"},
        CUNNING = {pos = "values cunning", neg = "is disgusted by guile and cunning"},
        ELOQUENCE = {pos = "values eloquence", neg = "finds eloquence off-putting"},
        HARD_WORK = {pos = "values hard work", neg = "sees working hard as a foolish waste"},
        CRAFTSMANSHIP = {pos = "holds craftsmanship to be of the highest ideals", neg = "could not care less about craftsmanship"},
        MARTIAL_PROWESS = {pos = "deeply respects those that take up the martial arts", neg = "sees war and violence as senseless"},
        SKILL = {pos = "respects those who take time to master a skill", neg = "doesn't respect the development of skill"},
        COMPETITION = {pos = "values competition", neg = "dislikes competition"},
        PERSEVERANCE = {pos = "respects perseverance", neg = "sees perseverance in the face of adversity as bull-headed"},
        LEISURE_TIME = {pos = "values leisure time", neg = "finds leisure time wasteful"},
        COMMERCE = {pos = "respects commerce", neg = "finds trade and commerce distasteful"},
        ROMANCE = {pos = "sees romance as one of the finer things in life", neg = "is somewhat disgusted by romance"},
        NATURE = {pos = "has a deep respect for nature", neg = "finds nature somewhat disturbing"},
        PEACE = {pos = "values peace over war", neg = "believes the idea of peace is laughable"},
        KNOWLEDGE = {pos = "values knowledge", neg = "finds the pursuit of knowledge to be of the very lowest priority"},
    }
    
    for i = 0, 49 do
        local value = safe_get(personality_values, i)
        if value then
            local value_num = tonumber(value)
            if value_num and value_num ~= 0 then
                local value_type = df.value_type[i]
                if value_type then
                    local value_name = tostring(value_type)
                    values.all_values[value_name:lower()] = value_num
                    
                    -- Generate descriptions
                    local desc_info = value_descriptions[value_name]
                    if desc_info then
                        if value_num > 10 then
                            table.insert(values.cultural_descriptions, desc_info.pos)
                        elseif value_num < -10 then
                            table.insert(values.cultural_descriptions, desc_info.neg)
                        end
                    end
                    
                    -- Strong values (>30 or <-30)
                    if value_num > 30 or value_num < -30 then
                        table.insert(values.strong_values, {
                            value = value_name:lower(),
                            strength = value_num,
                            attitude = value_num > 0 and "highly values" or "strongly opposes"
                        })
                    end
                end
            end
        end
    end
    
    return values
end

-- ============================================================================
-- EQUIPMENT
-- ============================================================================

function analyzer.get_equipment(unit)
    local equipment = {
        worn = {},
        wielded = {},
        count = 0
    }
    
    local inventory = safe_get(unit, 'inventory')
    if not inventory then return equipment end
    
    for _, item in ipairs(inventory) do
        local item_obj = safe_get(item, 'item')
        if item_obj then
            local ok, item_name = pcall(dfhack.items.getDescription, item_obj, 0)
            if not ok then
                item_name = "unknown item"
            end
            
            local mode = safe_get(item, 'mode')
            if mode then
                local mode_enum = safe_get(df, 'unit_inventory_item', 'T_mode')
                if mode_enum then
                    local mode_name = mode_enum[mode]
                    if mode_name then
                        local mode_str = tostring(mode_name)
                        
                        if mode_str == "Weapon" then
                            table.insert(equipment.wielded, item_name)
                        elseif mode_str == "Worn" then
                            table.insert(equipment.worn, item_name)
                        end
                    end
                end
            end
            
            equipment.count = equipment.count + 1
        end
    end
    
    return equipment
end

-- ============================================================================
-- SKILLS
-- ============================================================================

function analyzer.get_skills(unit)
    local skills = {}
    local soul = safe_get(unit, 'status', 'current_soul')
    if not soul then return skills end
    
    for _, skill in ipairs(soul.skills or {}) do
        local skill_name = df.job_skill[skill.id]
        if skill_name then
            table.insert(skills, {
                name = tostring(skill_name):lower():gsub('_', ' '),
                level = skill.rating,
                experience = skill.experience,
                rusty = skill.rusty or 0,
            })
        end
    end
    
    table.sort(skills, function(a, b)
        if a.level == b.level then
            return a.experience > b.experience
        end
        return a.level > b.level
    end)
    
    return skills
end

-- ============================================================================
-- NEEDS
-- ============================================================================

function analyzer.get_needs(unit)
    local needs = {}
    local soul = safe_get(unit, 'status', 'current_soul')
    if not soul then return needs end
    
    local needs_list = safe_get(soul, 'personality', 'needs')
    if not needs_list then return needs end
    
    for _, need in ipairs(needs_list) do
        local need_type = df.need_type[need.id]
        if need_type then
            table.insert(needs, {
                type = tostring(need_type),
                level = need.need_level,
                focus = need.focus_level or 0,
            })
        end
    end
    
    table.sort(needs, function(a, b) return a.level > b.level end)
    
    return needs
end

-- ============================================================================
-- THOUGHTS (Recent memories)
-- ============================================================================

function analyzer.get_recent_thoughts(unit)
    local thoughts = {}
    
    local soul = safe_get(unit, 'status', 'current_soul')
    if not soul then return thoughts end
    
    local thought_list = safe_get(soul, 'personality', 'thoughts')
    if not thought_list then return thoughts end
    
    for i = math.max(0, #thought_list - 10), #thought_list - 1 do
        local thought = safe_get(thought_list, i)
        if thought then
            local thought_type = df.unit_thought_type[thought.type]
            if thought_type then
                table.insert(thoughts, {
                    type = tostring(thought_type),
                    age = thought.age or 0,
                })
            end
        end
    end
    
    return thoughts
end

-- ============================================================================
-- RELATIONSHIPS
-- ============================================================================

function analyzer.get_relationships(unit)
    local rels = {
        friends_count = 0,
        family = {}
    }
    
    local relationships = safe_get(unit, 'hist_figure_id')
    if relationships then
        rels.hist_figure_id = relationships
    end
    
    return rels
end

-- ============================================================================
-- CURRENT STATE
-- ============================================================================

function analyzer.get_current_state(unit)
    local state = {}
    
    local current_job = safe_get(unit, 'job', 'current_job')
    if current_job then
        local job_type = df.job_type[current_job.job_type]
        state.current_job = tostring(job_type)
    else
        state.current_job = "idle"
    end
    
    local body = safe_get(unit, 'body')
    if body and body.wounds then
        state.wounds = #body.wounds
    else
        state.wounds = 0
    end
    
    state.exhaustion = safe_get(unit, 'counters', 'exhaustion') or 0
    state.hunger = safe_get(unit, 'counters2', 'hunger_timer') or 0
    state.thirst = safe_get(unit, 'counters2', 'thirst_timer') or 0
    
    local soul = safe_get(unit, 'status', 'current_soul')
    if soul then
        state.stress_level = safe_get(soul, 'personality', 'stress') or 0
    else
        state.stress_level = 0
    end
    
    return state
end

-- ============================================================================
-- PHYSICAL APPEARANCE
-- ============================================================================

function analyzer.get_appearance(unit)
    local appearance = {
        height = 0,
        size = 0,
    }
    
    local height = safe_get(unit, 'body', 'size_info', 'height_cur')
    if height then
        appearance.height = height
    end
    
    local size = safe_get(unit, 'body', 'size_info', 'size_cur')
    if size then
        appearance.size = size
    end
    
    return appearance
end

-- ============================================================================
-- COMPLETE ANALYSIS
-- ============================================================================

function analyzer.analyze_dwarf(unit)
    if not unit then return nil end
    
    local name = analyzer.get_name(unit)
    local profession = dfhack.units.getProfessionName(unit) or "No profession"
    
    print("[DwarfTalk] Analyzing: " .. name .. " (" .. profession .. ")")
    
    local analysis = {
        -- Basic info
        id = unit.id,
        name = name,
        nickname = unit.name.nickname or "",
        profession = profession,
        age = dfhack.units.getAge(unit) or 0,
        sex = unit.sex == 0 and "female" or "male",
        
        -- Detailed data
        personality = analyzer.get_personality_deep(unit),
        preferences = analyzer.get_preferences_detailed(unit),
        values = analyzer.get_values_complete(unit),
        equipment = analyzer.get_equipment(unit),
        skills = analyzer.get_skills(unit),
        needs = analyzer.get_needs(unit),
        recent_thoughts = analyzer.get_recent_thoughts(unit),
        relationships = analyzer.get_relationships(unit),
        current_state = analyzer.get_current_state(unit),
        appearance = analyzer.get_appearance(unit),
        
        -- Metadata
        analyzed_at = os.date("%Y-%m-%d %H:%M:%S"),
    }
    
    return analysis
end

-- ============================================================================
-- SAVE ANALYSIS
-- ============================================================================

function analyzer.save_analysis(analysis, filename)
    local output_dir = dfhack.getDFPath() .. '/dwarftalk_analysis/'
    dfhack.run_command_silent('mkdir "' .. output_dir:gsub('/', '\\') .. '" 2>nul')
    
    local filepath = output_dir .. filename
    local f = io.open(filepath, 'w')
    
    if not f then
        qerror("Could not write to: " .. filepath)
    end
    
    f:write(json.encode(analysis))
    f:close()
    
    print("[DwarfTalk] ✓ Analysis saved to: " .. filepath)
    print("[DwarfTalk]")
    print("[DwarfTalk] Summary for " .. analysis.name .. ":")
    print("[DwarfTalk] - " .. analysis.personality.personality_summary)
    if #analysis.personality.narrative_description > 0 then
        print("[DwarfTalk] - " .. analysis.personality.narrative_description[1])
    end
    if #analysis.values.cultural_descriptions > 0 then
        print("[DwarfTalk] - " .. analysis.values.cultural_descriptions[1])
    end
    
    return filepath
end

-- ============================================================================
-- COMMANDS
-- ============================================================================

function command_analyze_selected()
    local unit = dfhack.gui.getSelectedUnit()
    
    if not unit or not dfhack.units.isCitizen(unit) then
        qerror("Please select a citizen dwarf first (use 'v' key)")
    end
    
    local analysis = analyzer.analyze_dwarf(unit)
    local filename = "dwarf_" .. unit.id .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    analyzer.save_analysis(analysis, filename)
    
    print("\n✓ Analysis complete!")
end

function command_analyze_all()
    print("[DwarfTalk] Analyzing all fortress dwarves...")
    
    local all_analysis = {}
    local count = 0
    
    for _, unit in ipairs(df.global.world.units.active) do
        if dfhack.units.isCitizen(unit) and not dfhack.units.isDead(unit) then
            local analysis = analyzer.analyze_dwarf(unit)
            if analysis then
                table.insert(all_analysis, analysis)
                count = count + 1
            end
        end
    end
    
    local filename = "all_dwarves_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    analyzer.save_analysis(all_analysis, filename)
    
    print("\n✓ Analyzed " .. count .. " dwarves!")
end

function command_analyze_random()
    local dwarves = {}
    
    for _, unit in ipairs(df.global.world.units.active) do
        if dfhack.units.isCitizen(unit) and not dfhack.units.isDead(unit) then
            table.insert(dwarves, unit)
        end
    end
    
    if #dwarves == 0 then
        qerror("No dwarves found in fortress!")
    end
    
    local random_dwarf = dwarves[math.random(#dwarves)]
    local analysis = analyzer.analyze_dwarf(random_dwarf)
    local filename = "dwarf_" .. random_dwarf.id .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    analyzer.save_analysis(analysis, filename)
    
    print("\n✓ Random dwarf analysis complete!")
end

-- ============================================================================
-- ENTRY POINT
-- ============================================================================

-- Module export
return analyzer