-- Debug fortress context generation
local fortress_context = require('fortress_context')

print("===============================================")
print("  DEBUGGING FORTRESS CONTEXT")
print("===============================================")
print("")

-- Test 1: Generate context
print("[Test 1] Generating context...")
local ok, ctx = pcall(fortress_context.generate_context)

if not ok then
    print("✗ ERROR generating context:")
    print(ctx)
    print("")
    return
end

print("✓ Context generated successfully")
print("")

-- Test 2: Show context data
print("[Test 2] Context data:")
print("  - Season: " .. (ctx.season and ctx.season.full or "ERROR"))
print("  - Population: " .. (ctx.population or "ERROR"))
print("  - Mood: " .. (ctx.fortress_mood or "ERROR"))
print("  - Wealth: " .. (ctx.wealth or "ERROR"))
print("  - Deaths: " .. (ctx.recent_deaths and #ctx.recent_deaths or "ERROR"))
print("  - Threats: siege=" .. tostring(ctx.threats and ctx.threats.siege))
print("")

-- Test 3: Convert to text
print("[Test 3] Converting to prompt text...")
local ok2, text = pcall(fortress_context.context_to_text, ctx)

if not ok2 then
    print("✗ ERROR converting to text:")
    print(text)
    print("")
    return
end

print("✓ Text generated successfully")
print("")
print("--- PROMPT TEXT (what AI sees) ---")
print(text)
print("--- END PROMPT TEXT ---")
print("")

-- Test 4: Save and load
print("[Test 4] Testing save/load...")
local save_ok = fortress_context.save_context_to_json(ctx)

if save_ok then
    print("✓ Saved to JSON")
else
    print("✗ Failed to save")
end

local loaded = fortress_context.load_context_from_json()
if loaded then
    print("✓ Loaded from JSON")
else
    print("✗ Failed to load")
end

print("")
print("===============================================")
print("  DEBUG COMPLETE")
print("===============================================")