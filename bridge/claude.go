package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"time"
)

// ============================================================
// PROVEEDOR: CLAUDE CODE (CLI, uses your Claude subscription)
// ============================================================

// findClaudeCLI returns the path to a usable `claude` binary.
// Order: config override → PATH → ~/.local/bin → ~/.claude/local → newest
// copy bundled with the Claude desktop app. Uses claude.exe on Windows.
func findClaudeCLI() string {
	configMu.Lock()
	override := currentConfig.ClaudePath
	configMu.Unlock()
	if override != "" {
		return override
	}
	if p, err := exec.LookPath("claude"); err == nil {
		return p
	}
	exe := "claude"
	if runtime.GOOS == "windows" {
		exe = "claude.exe"
	}
	home, _ := os.UserHomeDir()
	for _, p := range []string{
		filepath.Join(home, ".local", "bin", exe), // native installer (all OSes)
		filepath.Join(home, ".claude", "local", exe),
	} {
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p
		}
	}
	// Copy bundled with the Claude desktop app: ~/.config/Claude on Linux,
	// %APPDATA%\Claude on Windows, ~/Library/Application Support/Claude on macOS.
	if cfgDir, err := os.UserConfigDir(); err == nil {
		matches, _ := filepath.Glob(filepath.Join(cfgDir, "Claude", "claude-code-vm", "*", exe))
		sort.Strings(matches)
		if len(matches) > 0 {
			return matches[len(matches)-1]
		}
	}
	return ""
}

// flattenForCLI turns an OpenAI-style message list into a system prompt and a
// single user prompt containing the prior conversation as a transcript.
func flattenForCLI(rawMessages []map[string]interface{}) (string, string) {
	var system []string
	var turns []map[string]interface{}
	for _, m := range rawMessages {
		if role, _ := m["role"].(string); role == "system" {
			c, _ := m["content"].(string)
			system = append(system, c)
		} else {
			turns = append(turns, m)
		}
	}
	if len(turns) == 1 {
		c, _ := turns[0]["content"].(string)
		return strings.Join(system, "\n\n"), c
	}
	var b strings.Builder
	b.WriteString("<conversation_so_far>\n")
	for i, m := range turns {
		role, _ := m["role"].(string)
		c, _ := m["content"].(string)
		if i == len(turns)-1 {
			b.WriteString("</conversation_so_far>\n\nReply to this latest message from the player:\n")
			b.WriteString(c)
			break
		}
		if role == "assistant" {
			b.WriteString("[you]: ")
		} else {
			b.WriteString("[player]: ")
		}
		b.WriteString(c)
		b.WriteString("\n")
	}
	return strings.Join(system, "\n\n"), b.String()
}

func handleClaudeCodeChat(messages json.RawMessage) Response {
	bin := findClaudeCLI()
	if bin == "" {
		return Response{false, "Claude Code CLI not found. Install it from https://claude.com/claude-code and run: claude auth login"}
	}
	var rawMessages []map[string]interface{}
	if err := json.Unmarshal(messages, &rawMessages); err != nil {
		return Response{false, "Failed to parse messages"}
	}
	system, prompt := flattenForCLI(rawMessages)
	model := resolveModel(currentConfig.Model, "claude_code")

	args := []string{
		"-p",
		"--output-format", "json",
		"--model", model,
		"--tools", "",
		"--strict-mcp-config",
		"--setting-sources", "",
		"--no-session-persistence",
	}
	if system != "" {
		args = append(args, "--system-prompt", system)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*Timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, args...)
	// Run from an empty dir so no CLAUDE.md / project context leaks into the dwarf.
	cmd.Dir = os.TempDir()
	cmd.Stdin = strings.NewReader(prompt)
	// Don't inherit nested-session markers if the bridge was started from inside Claude Code.
	cmd.Env = filterEnv(os.Environ(), "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()

	var result struct {
		Result  string `json:"result"`
		IsError bool   `json:"is_error"`
	}
	if jerr := json.Unmarshal(out, &result); jerr != nil {
		if err != nil {
			return Response{false, fmt.Sprintf("claude CLI failed: %v %s", err, strings.TrimSpace(stderr.String()))}
		}
		return Response{false, "Could not parse claude CLI output"}
	}
	if result.IsError {
		return Response{false, "Claude: " + result.Result}
	}
	log.Printf("Claude Code response: %d chars", len(result.Result))
	return Response{true, result.Result}
}

func filterEnv(env []string, drop ...string) []string {
	var out []string
outer:
	for _, kv := range env {
		for _, d := range drop {
			if strings.HasPrefix(kv, d+"=") {
				continue outer
			}
		}
		out = append(out, kv)
	}
	return out
}

// checkClaudeCodeStatus runs a cheap `claude auth status` to see if the CLI is logged in.
var claudeStatusCache struct {
	at  time.Time
	ok  bool
	msg string
}

func checkClaudeCodeStatus() (bool, string) {
	if time.Since(claudeStatusCache.at) < 60*time.Second {
		return claudeStatusCache.ok, claudeStatusCache.msg
	}
	ok, msg := func() (bool, string) {
		bin := findClaudeCLI()
		if bin == "" {
			return false, "claude CLI not found"
		}
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, bin, "auth", "status")
		cmd.Env = filterEnv(os.Environ(), "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION")
		out, _ := cmd.CombinedOutput()
		var st struct {
			LoggedIn bool `json:"loggedIn"`
		}
		if json.Unmarshal(out, &st) == nil && !st.LoggedIn {
			return false, "claude CLI not logged in — run: claude auth login"
		}
		return true, "Ready (model: " + resolveModel(currentConfig.Model, "claude_code") + ")"
	}()
	claudeStatusCache.at, claudeStatusCache.ok, claudeStatusCache.msg = time.Now(), ok, msg
	return ok, msg
}

// ============================================================
// PROVEEDOR: ANTHROPIC API (pay-as-you-go API key)
// ============================================================

func handleAnthropicChat(messages json.RawMessage) Response {
	configMu.Lock()
	key := currentConfig.AnthropicKey
	configMu.Unlock()
	if key == "" {
		key = os.Getenv("ANTHROPIC_API_KEY")
	}
	if key == "" {
		return Response{false, "No Anthropic API key configured"}
	}
	var rawMessages []map[string]interface{}
	if err := json.Unmarshal(messages, &rawMessages); err != nil {
		return Response{false, "Failed to parse messages"}
	}
	var system []string
	var msgs []map[string]string
	for _, m := range rawMessages {
		role, _ := m["role"].(string)
		content, _ := m["content"].(string)
		if role == "system" {
			system = append(system, content)
			continue
		}
		if role != "assistant" {
			role = "user"
		}
		// The Messages API requires alternating roles; merge consecutive ones.
		if n := len(msgs); n > 0 && msgs[n-1]["role"] == role {
			msgs[n-1]["content"] += "\n\n" + content
			continue
		}
		msgs = append(msgs, map[string]string{"role": role, "content": content})
	}
	if len(msgs) == 0 || msgs[0]["role"] != "user" {
		msgs = append([]map[string]string{{"role": "user", "content": "(The player approaches.)"}}, msgs...)
	}
	body := map[string]interface{}{
		"model":      resolveModel(currentConfig.Model, "anthropic"),
		"max_tokens": 1024,
		"messages":   msgs,
	}
	if len(system) > 0 {
		body["system"] = strings.Join(system, "\n\n")
	}
	payload, _ := json.Marshal(body)
	req, err := http.NewRequest("POST", "https://api.anthropic.com/v1/messages", bytes.NewBuffer(payload))
	if err != nil {
		return Response{false, "Failed to create request: " + err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", key)
	req.Header.Set("anthropic-version", "2023-06-01")
	client := &http.Client{Timeout: Timeout}
	resp, err := client.Do(req)
	if err != nil {
		return Response{false, "Anthropic request failed: " + err.Error()}
	}
	defer resp.Body.Close()
	respBody, _ := ioutil.ReadAll(resp.Body)
	var ar struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(respBody, &ar); err != nil {
		return Response{false, fmt.Sprintf("HTTP %d from Anthropic", resp.StatusCode)}
	}
	if ar.Error != nil {
		return Response{false, "Anthropic error: " + ar.Error.Message}
	}
	var text strings.Builder
	for _, c := range ar.Content {
		if c.Type == "text" {
			text.WriteString(c.Text)
		}
	}
	log.Printf("Anthropic response: %d chars", text.Len())
	return Response{true, text.String()}
}

// ============================================================
// RESPONSE CLEANUP
// ============================================================

var codeFenceRe = regexp.MustCompile("(?s)^\\s*```[a-zA-Z]*\\s*\n(.*?)\n?```\\s*$")

var asciiReplacer = strings.NewReplacer(
	"‘", "'", "’", "'", "‚", "'", "‛", "'",
	"“", "\"", "”", "\"", "„", "\"",
	"–", "-", "—", " - ", "―", "-", "−", "-",
	"…", "...", " ", " ", "•", "*",
)

// cleanModelText strips markdown code fences and replaces typographic
// punctuation with ASCII. The Lua side strips every non-ASCII byte (DF renders
// CP437), so without this "don't" would arrive as "dont".
func cleanModelText(s string) string {
	if m := codeFenceRe.FindStringSubmatch(s); m != nil {
		s = m[1]
	}
	return strings.TrimSpace(asciiReplacer.Replace(s))
}
