# 🏔️ DwarfTalk

AI-powered conversations for Dwarf Fortress. Talk to your dwarves, watch them chat with each other, and influence the fortress through natural language.

---

## ✨ Features

- **Chat with individual dwarves** - Each dwarf has personality and memory
- **NPC-to-NPC conversations** - Dwarves talk to each other autonomously
- **Real in-game effects** - Your words affect dwarf moods and behavior
- **Powered by player2.game** - Natural language understanding

---

## 📦 Requirements

- **Dwarf Fortress** (Steam version)
- **[DFHack](https://store.steampowered.com/app/2346660/DFHack__Dwarf_Fortress_Modding_Engine/)** - Modding engine
- **[player2.game](https://player2.game)** - AI platform

---

## 🚀 Quick Install

### Step 1: Subscribe on Steam Workshop
✅ https://steamcommunity.com/sharedfiles/filedetails/?id=3673957650

### Step 2: Download the Bridge
1. Go to [Releases](https://github.com/carlosnahuelcoy/dwarftalk/releases/latest)
2. Download `dwarftalk_bridge.exe`
3. Place it in your Dwarf Fortress directory:
```
   Steam/steamapps/common/Dwarf Fortress/dwarftalk_bridge.exe
```

### Step 3: Add Keybindings (REQUIRED)
**DFHack keybindings must be added manually:**

1. Navigate to: `Dwarf Fortress/dfhack-config/init/`
2. Open `dfhack.init` with a text editor (Notepad works)
3. Add these lines at the end:
```
# DwarfTalk keybindings
keybinding add Ctrl-T dwarftalk/chat_window
keybinding add Ctrl-Shift-S dwarftalk/settings_window
```

4. Save and close

**Alternative keys if Ctrl-T is taken:**
```
keybinding add Alt-T dwarftalk/chat_window
keybinding add Alt-Shift-S dwarftalk/settings_window
```

### Step 4: Start Playing!
1. Run `dwarftalk_bridge.exe` (keep it open)
2. Start Dwarf Fortress
3. Load or create a fortress
4. Press `Ctrl+T` to open the conversation window

---

## 🎮 Usage

### Chat with Dwarves
1. Press `Ctrl+T` to open the conversation window
2. From there you can chat with any dwarf or view NPC conversation history
3. Type your message
4. See the dwarf's response and effects!

### Access Settings
- Press `Ctrl+Shift+S` to configure:
  - Conversation intervals
  - NPC chat frequency
  - Notification chances

### Check Status
Run in DFHack console (backtick key `` ` ``):
```
dwarftalk/status
```

---

## ⚠️ Troubleshooting

**"Nothing happens when I press Ctrl+T"**
- Did you add the keybindings to `dfhack.init`? (See Step 3 above)
- Is DFHack installed and running?

**"Bridge not found" error**
- Ensure `dwarftalk_bridge.exe` is in the DF root directory
- Run the bridge before starting the game

**"Player2 not responding"**
- Is player2.game running?
- Check bridge dashboard: http://localhost:4316

**NPC conversations too frequent/rare**
- Adjust interval in Settings (`Ctrl+Shift+S`)
- System uses probability - it's not exactly every X minutes

---

## 🔧 Building from Source

### Bridge (Go)
```bash
cd bridge
go build -o dwarftalk_bridge.exe
```

**Requirements:**
- Go 1.19+

---

## ⚖️ License & Restrictions

This project is licensed under the MIT License **with one critical restriction**:

### 🔒 Protected GameKey

The player2.game Game Key embedded in this software:
```go
GameKey = "019c23d7-e3e9-7381-b2bd-b186f184ac7b"
```

**MUST NOT be modified, removed, or replaced** under any circumstances.

This includes:
- ❌ Forks and derivatives
- ❌ Redistributions
- ❌ Modified versions
- ❌ Any other use of this code

**Violating this restriction voids all license permissions.**

### Why?

This GameKey is tied to the original author's player2.game account and is required for the software to function properly.

### Can I fork this project?

✅ **Yes!** You can:
- Fork this project
- Modify the code
- Add new features
- Redistribute it
- Use it for any purpose

🔒 **One rule:** Keep the GameKey unchanged.

That's it. Fork freely, improve it, share it - just don't change the GameKey.

See [LICENSE](LICENSE) for full details.

---

## 🤝 Contributing

Issues and pull requests welcome (respecting the GameKey restriction).

---

## 🙏 Credits

- **player2.game** - Natural language AI platform
- **DFHack Team** - Modding framework
- **Bay 12 Games** - Dwarf Fortress
- **DF Community** - Inspiration and support

---

## 📄 Additional Files

- **[QUICK_SETUP.txt](QUICK_SETUP.txt)** - Quick installation guide
- **[LICENSE](LICENSE)** - MIT License with GameKey restriction
- **[workshop/](workshop/)** - Files for Steam Workshop

---

**Questions? [Open an issue](https://github.com/carlosnahuelcoy/dwarftalk/issues)**
