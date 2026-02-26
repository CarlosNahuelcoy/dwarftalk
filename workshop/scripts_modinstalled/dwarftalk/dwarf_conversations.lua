--@module = true

local conversations = {}
local analyzer = require('analyze_dwarf')

-- Guardar conversación en archivo de historial
function conversations.save_to_history(name1, name2, dialogue, timestamp, effects)
    local history_file = dfhack.getDFPath() .. '/dwarftalk_temp/npc_conversations.json'
    
    -- Cargar historial existente
    local history = {}
    local f = io.open(history_file, 'r')
    if f then
        local content = f:read('*all')
        f:close()
        if content and content ~= '' then
            local json = require('json')
            local ok, data = pcall(json.decode, content)
            if ok and data then
                history = data
            end
        end
    end
    
    -- Agregar nueva conversación al inicio
    table.insert(history, 1, {
        timestamp = timestamp or os.time(),
        name1 = name1,
        name2 = name2,
        dialogue = dialogue,
        effects = effects
    })
    
    -- Mantener solo las últimas 100
    while #history > 100 do
        table.remove(history)
    end
    
    -- Guardar
    local json = require('json')
    f = io.open(history_file, 'w')
    if f then
        f:write(json.encode(history))
        f:close()
    end
end

-- Cargar historial
function conversations.load_history()
    local history_file = dfhack.getDFPath() .. '/dwarftalk_temp/npc_conversations.json'
    
    local f = io.open(history_file, 'r')
    if not f then return {} end
    
    local content = f:read('*all')
    f:close()
    
    if not content or content == '' then return {} end
    
    local json = require('json')
    local ok, data = pcall(json.decode, content)
    
    if ok and data then
        return data
    end
    
    return {}
end

-- Encuentra pares de enanos cercanos
function conversations.find_nearby_pairs()
    local citizens = {}
    
    for _, unit in ipairs(df.global.world.units.active) do
        if dfhack.units.isCitizen(unit) and not dfhack.units.isDead(unit) then
            table.insert(citizens, unit)
        end
    end
    
    local pairs = {}
    
    for i = 1, #citizens do
        for j = i + 1, #citizens do
            local u1 = citizens[i]
            local u2 = citizens[j]
            
            if u1.pos.x and u2.pos.x then
                local dx = math.abs(u1.pos.x - u2.pos.x)
                local dy = math.abs(u1.pos.y - u2.pos.y)
                local dz = math.abs(u1.pos.z - u2.pos.z)
                
                -- Mismo nivel, muy cercanos (radio de 3 tiles)
                if dz == 0 and dx <= 3 and dy <= 3 then
                    table.insert(pairs, {u1, u2})
                end
            end
        end
    end
    
    return pairs
end

-- Obtener nombre limpio
function conversations.get_clean_name(unit)
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
        name = 'Unnamed #' .. tostring(unit.id)
    end
    
    -- Sanitizar caracteres especiales
    return name:gsub("[^\32-\126]", "")
end

-- Crear info de enano para action_engine
function conversations.get_dwarf_info(unit)
    return {
        id = unit.id,
        name = conversations.get_clean_name(unit),
        profession = dfhack.units.getProfessionName(unit) or "peasant",
        unit = unit
    }
end

-- Generar contexto para conversación con efectos
function conversations.build_context(unit1, unit2)
    local name1 = conversations.get_clean_name(unit1)
    local name2 = conversations.get_clean_name(unit2)
    
    -- ANÁLISIS PROFUNDO de ambos enanos
    local analysis1 = analyzer.analyze_dwarf(unit1)
    local analysis2 = analyzer.analyze_dwarf(unit2)
    
    local prompt = "Two dwarves encounter each other in the fortress:\n\n"
    
    -- ENANO 1
    prompt = prompt .. "=== " .. name1 .. " ===\n"
    prompt = prompt .. "Profession: " .. (analysis1.profession or "peasant") .. "\n"
    
    if analysis1.personality and analysis1.personality.narrative_description then
        prompt = prompt .. "Personality:\n"
        for i = 1, math.min(3, #analysis1.personality.narrative_description) do
            prompt = prompt .. "- " .. analysis1.personality.narrative_description[i] .. "\n"
        end
    end
    
    if analysis1.current_state then
        if analysis1.current_state.stress_level and analysis1.current_state.stress_level > 100000 then
            prompt = prompt .. "- Currently stressed\n"
        end
        if analysis1.current_state.current_job then
            prompt = prompt .. "- Currently: " .. analysis1.current_state.current_job:lower():gsub("_", " ") .. "\n"
        end
    end
    
    -- ENANO 2
    prompt = prompt .. "\n=== " .. name2 .. " ===\n"
    prompt = prompt .. "Profession: " .. (analysis2.profession or "peasant") .. "\n"
    
    if analysis2.personality and analysis2.personality.narrative_description then
        prompt = prompt .. "Personality:\n"
        for i = 1, math.min(3, #analysis2.personality.narrative_description) do
            prompt = prompt .. "- " .. analysis2.personality.narrative_description[i] .. "\n"
        end
    end
    
    if analysis2.current_state then
        if analysis2.current_state.stress_level and analysis2.current_state.stress_level > 100000 then
            prompt = prompt .. "- Currently stressed\n"
        end
        if analysis2.current_state.current_job then
            prompt = prompt .. "- Currently: " .. analysis2.current_state.current_job:lower():gsub("_", " ") .. "\n"
        end
    end
    
    -- INSTRUCCIONES
    prompt = prompt .. "\n=== TASK ===\n"
    prompt = prompt .. "Generate a brief conversation (3-6 lines) and determine its effects.\n"
    prompt = prompt .. "Their personalities should strongly influence the conversation.\n\n"
    
    prompt = prompt .. "CRITICAL: Respond ONLY with this JSON format:\n"
    prompt = prompt .. '{\n'
    prompt = prompt .. '  "dialogue": "' .. name1 .. ': \\"text\\"\n' .. name2 .. ': \\"text\\"",\n'
    prompt = prompt .. '  "effect1": {"type": "adjust_mood", "amount": 1},\n'
    prompt = prompt .. '  "effect2": {"type": "adjust_mood", "amount": 1}\n'
    prompt = prompt .. '}\n\n'
    
    prompt = prompt .. "Effect types:\n"
    prompt = prompt .. "- adjust_mood: amount -3 to +3 (how conversation affected their mood)\n"
    prompt = prompt .. "- change_job: job=\"miner|cook|mason|carpenter|farmer|brewer|smith\" (if they convince each other)\n"
    prompt = prompt .. "- refuse_work: reason=\"...\" (if argument leads to quitting)\n"
    prompt = prompt .. "- create_work_order: item=\"bed\", quantity=5 (if they discuss needs)\n"
    prompt = prompt .. "- assign_military: (if they decide to enlist together)\n\n"
    
    prompt = prompt .. "Guidelines:\n"
    prompt = prompt .. "- Most conversations are just mood adjustments (+1 or -1)\n"
    prompt = prompt .. "- Dramatic effects (job changes, refusing work) are RARE\n"
    prompt = prompt .. "- Effects should match the conversation content\n"
    prompt = prompt .. "- Keep dialogue brief and authentic\n"
    prompt = prompt .. "- NO narration, ONLY dialogue\n"
    
    return prompt, name1, name2
end

return conversations