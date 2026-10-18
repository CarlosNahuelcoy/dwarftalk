--@module = true
--[=====[

dwarftalk/names
===============
Readable unit names. DF stores first names lowercase and in CP437, and the rest
of DwarfTalk strips non-ASCII bytes, so "kûbuk" used to arrive as "kbuk". This
folds CP437 accented letters to plain ASCII and capitalizes the name.

]=====]

local names = {}

-- CP437 accented letters -> nearest ASCII
local CP437_FOLD = {
    [0x80] = 'C', [0x81] = 'u', [0x82] = 'e', [0x83] = 'a', [0x84] = 'a',
    [0x85] = 'a', [0x86] = 'a', [0x87] = 'c', [0x88] = 'e', [0x89] = 'e',
    [0x8A] = 'e', [0x8B] = 'i', [0x8C] = 'i', [0x8D] = 'i', [0x8E] = 'A',
    [0x8F] = 'A', [0x90] = 'E', [0x91] = 'ae', [0x92] = 'AE', [0x93] = 'o',
    [0x94] = 'o', [0x95] = 'o', [0x96] = 'u', [0x97] = 'u', [0x98] = 'y',
    [0x99] = 'O', [0x9A] = 'U', [0xA0] = 'a', [0xA1] = 'i', [0xA2] = 'o',
    [0xA3] = 'u', [0xA4] = 'n', [0xA5] = 'N',
}

function names.to_ascii(s)
    s = (s or ''):gsub('[\128-\255]', function(c)
        return CP437_FOLD[c:byte()] or ''
    end)
    return s
end

local function capitalize(s)
    return (s:gsub('^%l', string.upper))
end

-- First name (capitalized) plus "nickname", or fallback if the unit has neither.
function names.unit_name(unit, fallback)
    local name = ''
    if unit and unit.name and unit.name.has_name then
        if unit.name.first_name ~= '' then
            name = capitalize(names.to_ascii(unit.name.first_name))
        end
        if unit.name.nickname ~= '' then
            local nick = '"' .. names.to_ascii(unit.name.nickname) .. '"'
            name = name ~= '' and (name .. ' ' .. nick) or nick
        end
    end
    if name == '' then
        name = fallback or ('Unnamed Dwarf #' .. tostring(unit and unit.id))
    end
    return name
end

return names
