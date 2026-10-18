-- Make sibling DwarfTalk modules require()-able no matter which script runs first
do
    local dir = debug.getinfo(1, 'S').source:match('^@(.+)[/\\][^/\\]+$')
    if dir and not package.path:find(dir .. '/?.lua', 1, true) then
        package.path = package.path .. ';' .. dir .. '/?.lua'
    end
end
-- Intenta cargar diferentes librerías JSON en orden de preferencia
local function load_json()
    -- Opción 1: dkjson (más común en DFHack)
    local success, json = pcall(require, 'dkjson')
    if success then
        print("[JSON] Using dkjson library")
        return json
    end
    
    -- Opción 2: cjson
    success, json = pcall(require, 'cjson')
    if success then
        print("[JSON] Using cjson library")
        return json
    end
    
    -- Opción 3: json (genérico)
    success, json = pcall(require, 'json')
    if success then
        print("[JSON] Using json library")
        return json
    end
    
    error("No JSON library found! Please install dkjson or cjson")
end

return load_json()