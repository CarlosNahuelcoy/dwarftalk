package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
	"time"
)

const (
	Player2LocalEndpoint = "http://127.0.0.1:4315"
	Player2WebAPI        = "https://api.player2.game"
	GameClientID         = "019c23d7-e3e9-7381-b2bd-b186f184ac7b"
	ServerPort           = ":4316"
	Timeout              = 60 * time.Second
	Version              = "1.2.0"
	PollInterval         = 500 * time.Millisecond
)

// Player2 Device Authorization Flow endpoints
const (
	Player2DeviceNewURL    = "https://api.player2.game/v1/login/device/new"
	Player2DeviceTokenURL  = "https://api.player2.game/v1/login/device/token"
	Player2DeviceGrantType = "urn:ietf:params:oauth:grant-type:device_code"
)

var DEBUG_MODE = false

// ============================================================
// TIPOS PRINCIPALES
// ============================================================

type Request struct {
	Command  string          `json:"command"`
	Messages json.RawMessage `json:"messages"`
}

type Response struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

type Status struct {
	Running        bool   `json:"running"`
	Provider       string `json:"provider"`
	ProviderOK     bool   `json:"provider_ok"`
	ProviderMsg    string `json:"provider_msg"`
	RequestCount   int    `json:"request_count"`
	Uptime         string `json:"uptime"`
	LastActivity   string `json:"last_activity"`
	Player2UserKey bool   `json:"player2_user_key"`
}

// ============================================================
// PROVIDER CONFIGURATION
// ============================================================

type ProviderConfig struct {
	Provider      string `json:"provider"`
	OpenAIKey     string `json:"openai_key"`
	OpenRouterKey string `json:"openrouter_key"`
	GeminiKey     string `json:"gemini_key"`
	CustomURL     string `json:"custom_url"`
	CustomKey     string `json:"custom_key"`
	Model         string `json:"model"`
	Player2P2Key  string `json:"player2_p2key"`
}

var defaultConfig = ProviderConfig{Provider: "player2"}
var currentConfig ProviderConfig
var configMu sync.Mutex

func defaultModelForProvider(provider string) string {
	switch provider {
	case "openai":
		return "gpt-4o-mini"
	case "openrouter":
		return "openai/gpt-4o-mini"
	case "gemini":
		return "gemini-2.0-flash"
	case "custom":
		return "gpt-4o-mini"
	default:
		return ""
	}
}

func loadConfig() {
	configPath := filepath.Join(dfRootDir, "dwarftalk_config.json")
	currentConfig = defaultConfig
	data, err := ioutil.ReadFile(configPath)
	if err != nil {
		log.Println("  No config found, using defaults (Player2)")
		return
	}
	if err := json.Unmarshal(data, &currentConfig); err != nil {
		log.Println("  Could not parse config, using defaults:", err)
		currentConfig = defaultConfig
	} else {
		log.Printf("  Config loaded — provider: %s", currentConfig.Provider)
		if currentConfig.Player2P2Key != "" {
			log.Println("  Player2 OAuth key loaded")
		}
	}
}

func saveConfig(cfg ProviderConfig) error {
	configPath := filepath.Join(dfRootDir, "dwarftalk_config.json")
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return ioutil.WriteFile(configPath, data, 0644)
}

// ============================================================
// ESTADO GLOBAL
// ============================================================

var (
	requestCounter = 0
	serverStart    = time.Now()
	lastActivity   = "Server started"
	providerOK     = false
	providerMsg    = "Checking..."
	tempDir        string
	dfRootDir      string
)

// ============================================================
// DEVICE AUTHORIZATION FLOW — State
// ============================================================

type DeviceAuthStatus string

const (
	DeviceAuthIdle    DeviceAuthStatus = "idle"
	DeviceAuthPending DeviceAuthStatus = "pending"
	DeviceAuthDone    DeviceAuthStatus = "done"
	DeviceAuthError   DeviceAuthStatus = "error"
)

type DeviceAuthState struct {
	Status          DeviceAuthStatus
	UserCode        string
	VerificationURI string
	KeyHint         string
	ErrorMsg        string
}

var (
	deviceAuth   = DeviceAuthState{Status: DeviceAuthIdle}
	deviceAuthMu sync.Mutex
)

func debugLog(format string, v ...interface{}) {
	if DEBUG_MODE {
		log.Printf("[DEBUG] "+format, v...)
	}
}

// ============================================================
// MAIN
// ============================================================

func main() {
	log.Println("╔════════════════════════════════════════╗")
	log.Println("║   DwarfTalk Bridge Server v" + Version + "      ║")
	log.Println("║   Multi-Provider + Player2 OAuth       ║")
	log.Println("╚════════════════════════════════════════╝")
	log.Println()

	exePath, _ := os.Executable()
	dfRootDir = filepath.Dir(exePath)
	log.Println("Dwarf Fortress directory:", dfRootDir)
	log.Println()

	if err := setupDirectories(); err != nil {
		log.Fatal("Failed to create directories:", err)
	}
	loadConfig()
	log.Println()

	go pollRequestFile()
	go pollNPCRequestFile()

	http.HandleFunc("/", handleDashboard)
	http.HandleFunc("/api/status", handleStatus)
	http.HandleFunc("/api/config", handleConfigEndpoint)
	http.HandleFunc("/api/player2/getkey", handlePlayer2GetKey)
	http.HandleFunc("/api/player2/clearkey", handlePlayer2ClearKey)
	http.HandleFunc("/api/player2/pollauth", handlePlayer2PollAuth)

	go func() {
		for {
			checkProviderStatus()
			time.Sleep(10 * time.Second)
		}
	}()

	go func() {
		time.Sleep(1 * time.Second)
		openBrowser("http://localhost:4316")
	}()

	log.Println("Server started — http://localhost:4316")
	log.Printf("Active provider: %s", currentConfig.Provider)
	log.Println()
	log.Println("Press Ctrl+C to stop")
	log.Println()

	if err := http.ListenAndServe(ServerPort, nil); err != nil {
		log.Fatal("Server error:", err)
	}
}

// ============================================================
// DIRECTORIOS
// ============================================================

func setupDirectories() error {
	dirs := map[string]string{
		"temp":     "dwarftalk_temp",
		"saves":    "dwarftalk_saves",
		"analysis": "dwarftalk_analysis",
	}
	log.Println("Creating necessary directories...")
	for name, dir := range dirs {
		fullPath := filepath.Join(dfRootDir, dir)
		if _, err := os.Stat(fullPath); os.IsNotExist(err) {
			if err := os.MkdirAll(fullPath, 0755); err != nil {
				return fmt.Errorf("failed to create %s: %v", name, err)
			}
			log.Printf("  Created: %s", fullPath)
		} else {
			log.Printf("  Exists:  %s", fullPath)
		}
		if name == "temp" {
			tempDir = fullPath
		}
	}
	return nil
}

// ============================================================
// POLLING DE ARCHIVOS
// ============================================================

func pollRequestFile() {
	requestPath := filepath.Join(tempDir, "request.json")
	responsePath := filepath.Join(tempDir, "response.json")
	log.Println("Polling request files...")
	for {
		time.Sleep(PollInterval)
		if _, err := os.Stat(requestPath); os.IsNotExist(err) {
			continue
		}
		data, err := ioutil.ReadFile(requestPath)
		if err != nil {
			continue
		}
		os.Remove(requestPath)
		log.Println("📥 REQUEST")
		var req Request
		if err := json.Unmarshal(data, &req); err != nil {
			writeResponse(responsePath, Response{false, "Invalid request format"})
			continue
		}
		t := time.Now()
		var resp Response
		switch req.Command {
		case "health":
			resp = handleHealthCheck()
		case "chat":
			resp = dispatchChat(req.Messages)
		default:
			resp = Response{false, "Unknown command: " + req.Command}
		}
		writeResponse(responsePath, resp)
		log.Printf("📤 SENT (took %v)", time.Since(t))
		log.Println()
	}
}

func pollNPCRequestFile() {
	requestPath := filepath.Join(tempDir, "npc_request.json")
	responsePath := filepath.Join(tempDir, "npc_response.json")
	log.Println("Polling NPC request files...")
	for {
		time.Sleep(PollInterval)
		if _, err := os.Stat(requestPath); os.IsNotExist(err) {
			continue
		}
		data, err := ioutil.ReadFile(requestPath)
		if err != nil {
			continue
		}
		os.Remove(requestPath)
		log.Println("📥 NPC REQUEST")
		var req Request
		if err := json.Unmarshal(data, &req); err != nil {
			writeResponse(responsePath, Response{false, "Invalid request format"})
			continue
		}
		t := time.Now()
		var resp Response
		switch req.Command {
		case "chat":
			resp = dispatchChat(req.Messages)
		default:
			resp = Response{false, "Unknown command: " + req.Command}
		}
		writeResponse(responsePath, resp)
		log.Printf("📤 NPC SENT (took %v)", time.Since(t))
		log.Println()
	}
}

func writeResponse(path string, resp Response) {
	data, _ := json.Marshal(resp)
	ioutil.WriteFile(path, data, 0644)
}

// ============================================================
// DISPATCHER
// ============================================================

func dispatchChat(messages json.RawMessage) Response {
	requestCounter++
	lastActivity = fmt.Sprintf("Chat via %s", currentConfig.Provider)
	log.Printf("🤖 Chat → %s", currentConfig.Provider)
	switch currentConfig.Provider {
	case "player2":
		return handlePlayer2Chat(messages)
	case "openai":
		return handleOpenAICompatibleChat(messages, "https://api.openai.com/v1/chat/completions", currentConfig.OpenAIKey, currentConfig.Model)
	case "openrouter":
		return handleOpenRouterChat(messages)
	case "gemini":
		return handleGeminiChat(messages)
	case "custom":
		return handleOpenAICompatibleChat(messages, currentConfig.CustomURL, currentConfig.CustomKey, currentConfig.Model)
	default:
		return Response{false, "Unknown provider: " + currentConfig.Provider}
	}
}

// ============================================================
// PROVEEDOR: PLAYER2
// ============================================================

func handlePlayer2Chat(messages json.RawMessage) Response {
	// Attempt 1: local app (fast, no p2Key needed)
	if resp := tryPlayer2Local(messages); resp.Success {
		return resp
	}
	log.Println("Player2 local not available, trying Web API...")

	// Intento 2: Web API con p2Key OAuth
	configMu.Lock()
	p2Key := currentConfig.Player2P2Key
	configMu.Unlock()
	if p2Key == "" {
		return Response{false, "Player2 app not running and no OAuth key saved. Use the dashboard to get a key."}
	}
	return tryPlayer2WebAPI(messages, p2Key)
}

func tryPlayer2Local(messages json.RawMessage) Response {
	client := &http.Client{Timeout: 3 * time.Second}
	payload, _ := json.Marshal(map[string]interface{}{"messages": json.RawMessage(messages)})
	req, err := http.NewRequest("POST", Player2LocalEndpoint+"/v1/chat/completions", bytes.NewBuffer(payload))
	if err != nil {
		return Response{false, err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("player2-game-key", GameClientID)
	resp, err := client.Do(req)
	if err != nil {
		return Response{false, err.Error()}
	}
	defer resp.Body.Close()
	return extractOpenAIResponse(resp)
}

func tryPlayer2WebAPI(messages json.RawMessage, p2Key string) Response {
	client := &http.Client{Timeout: Timeout}
	payload, _ := json.Marshal(map[string]interface{}{"messages": json.RawMessage(messages)})
	req, err := http.NewRequest("POST", Player2WebAPI+"/v1/chat/completions", bytes.NewBuffer(payload))
	if err != nil {
		return Response{false, "Failed to create request: " + err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+p2Key)
	req.Header.Set("player2-game-key", GameClientID)
	resp, err := client.Do(req)
	if err != nil {
		return Response{false, "Player2 Web API failed: " + err.Error()}
	}
	defer resp.Body.Close()
	return extractOpenAIResponse(resp)
}

// ============================================================
// PLAYER2 — GET KEY (local app → Device Authorization Flow)
// ============================================================

func handlePlayer2GetKey(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// Fast path: local app running
	key, err := getKeyFromLocalApp()
	if err == nil && key != "" {
		log.Println("Got Player2 key from local app")
		configMu.Lock()
		currentConfig.Player2P2Key = key
		cfg := currentConfig
		configMu.Unlock()
		saveConfig(cfg)
		deviceAuthMu.Lock()
		deviceAuth = DeviceAuthState{Status: DeviceAuthDone, KeyHint: keyHint(key)}
		deviceAuthMu.Unlock()
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "ok", "method": "local_app", "key_hint": keyHint(key),
		})
		return
	}
	log.Println("Local app not available, starting Device Authorization Flow...")

	// Start Device flow in background, return quickly so dashboard can show the user code
	go runDeviceAuthFlow()

	// Wait briefly for the user code to be fetched before responding
	time.Sleep(1500 * time.Millisecond)

	deviceAuthMu.Lock()
	state := deviceAuth
	deviceAuthMu.Unlock()

	if state.Status == DeviceAuthError {
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "error", "message": state.ErrorMsg,
		})
		return
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":           "pending",
		"user_code":        state.UserCode,
		"verification_uri": state.VerificationURI,
	})
}

func runDeviceAuthFlow() {
	deviceAuthMu.Lock()
	deviceAuth = DeviceAuthState{Status: DeviceAuthPending}
	deviceAuthMu.Unlock()

	// Step 1: Start device flow
	payload, _ := json.Marshal(map[string]string{"client_id": GameClientID})
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Post(Player2DeviceNewURL, "application/json", bytes.NewBuffer(payload))
	if err != nil {
		log.Println("Device flow start failed:", err)
		deviceAuthMu.Lock()
		deviceAuth = DeviceAuthState{Status: DeviceAuthError, ErrorMsg: "Could not reach Player2: " + err.Error()}
		deviceAuthMu.Unlock()
		return
	}
	defer resp.Body.Close()
	body, _ := ioutil.ReadAll(resp.Body)
	debugLog("Device flow start (%d): %s", resp.StatusCode, string(body))

	var startResp struct {
		DeviceCode              string `json:"deviceCode"`
		ExpiresIn               int    `json:"expiresIn"`
		Interval                int    `json:"interval"`
		UserCode                string `json:"userCode"`
		VerificationUri         string `json:"verificationUri"`
		VerificationUriComplete string `json:"verificationUriComplete"`
	}
	if err := json.Unmarshal(body, &startResp); err != nil || startResp.DeviceCode == "" {
		log.Println("Invalid device flow response:", string(body))
		deviceAuthMu.Lock()
		deviceAuth = DeviceAuthState{Status: DeviceAuthError, ErrorMsg: "Invalid response from Player2: " + string(body)}
		deviceAuthMu.Unlock()
		return
	}

	log.Printf("Device flow started — user code: %s", startResp.UserCode)
	log.Printf("Verification URL: %s", startResp.VerificationUriComplete)

	deviceAuthMu.Lock()
	deviceAuth = DeviceAuthState{
		Status:          DeviceAuthPending,
		UserCode:        startResp.UserCode,
		VerificationURI: startResp.VerificationUri,
	}
	deviceAuthMu.Unlock()

	// Open browser to the complete URL (user code pre-filled)
	openBrowser(startResp.VerificationUriComplete)

	// Step 2: Poll for the key
	pollInterval := time.Duration(startResp.Interval) * time.Second
	if pollInterval < 3*time.Second {
		pollInterval = 5 * time.Second
	}
	expiresAt := time.Now().Add(time.Duration(startResp.ExpiresIn) * time.Second)

	for time.Now().Before(expiresAt) {
		time.Sleep(pollInterval)

		pollPayload, _ := json.Marshal(map[string]string{
			"client_id":   GameClientID,
			"device_code": startResp.DeviceCode,
			"grant_type":  Player2DeviceGrantType,
		})
		pollResp, err := client.Post(Player2DeviceTokenURL, "application/json", bytes.NewBuffer(pollPayload))
		if err != nil {
			log.Println("Device poll error:", err)
			continue
		}
		pollBody, _ := ioutil.ReadAll(pollResp.Body)
		pollResp.Body.Close()
		debugLog("Device poll (%d): %s", pollResp.StatusCode, string(pollBody))

		var tokenResp map[string]interface{}
		if err := json.Unmarshal(pollBody, &tokenResp); err != nil {
			continue
		}

		if errCode, ok := tokenResp["error"].(string); ok {
			if errCode == "authorization_pending" {
				continue
			}
			if errCode == "slow_down" {
				pollInterval += 5 * time.Second
				continue
			}
			log.Printf("Device flow error: %s", errCode)
			deviceAuthMu.Lock()
			deviceAuth = DeviceAuthState{Status: DeviceAuthError, ErrorMsg: "Player2 error: " + errCode}
			deviceAuthMu.Unlock()
			return
		}

		if p2Key, ok := tokenResp["p2Key"].(string); ok && p2Key != "" {
			log.Printf("Device flow: key obtained (%s)", keyHint(p2Key))
			configMu.Lock()
			currentConfig.Player2P2Key = p2Key
			cfg := currentConfig
			configMu.Unlock()
			saveConfig(cfg)
			deviceAuthMu.Lock()
			deviceAuth = DeviceAuthState{Status: DeviceAuthDone, KeyHint: keyHint(p2Key)}
			deviceAuthMu.Unlock()
			return
		}
	}

	log.Println("Device flow expired")
	deviceAuthMu.Lock()
	deviceAuth = DeviceAuthState{Status: DeviceAuthError, ErrorMsg: "Login timed out. Please try again."}
	deviceAuthMu.Unlock()
}

func handlePlayer2PollAuth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	deviceAuthMu.Lock()
	state := deviceAuth
	deviceAuthMu.Unlock()
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    string(state.Status),
		"user_code": state.UserCode,
		"key_hint":  state.KeyHint,
		"error":     state.ErrorMsg,
	})
}

func getKeyFromLocalApp() (string, error) {
	client := &http.Client{Timeout: 2 * time.Second}
	u := fmt.Sprintf("%s/v1/login/web/%s", Player2LocalEndpoint, GameClientID)
	resp, err := client.Post(u, "application/json", nil)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := ioutil.ReadAll(resp.Body)
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("invalid local app response")
	}
	key, ok := result["p2Key"].(string)
	if !ok || key == "" {
		return "", fmt.Errorf("no p2Key in response")
	}
	return key, nil
}

func handlePlayer2ClearKey(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	configMu.Lock()
	currentConfig.Player2P2Key = ""
	cfg := currentConfig
	configMu.Unlock()
	if err := saveConfig(cfg); err != nil {
		w.WriteHeader(500)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	log.Println("Player2 user key cleared")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// ============================================================
// PROVEEDOR: OPENAI-COMPATIBLE
// ============================================================

func handleOpenAICompatibleChat(messages json.RawMessage, endpoint, apiKey, model string) Response {
	if endpoint == "" {
		return Response{false, "No endpoint configured"}
	}
	if apiKey == "" {
		return Response{false, "No API key configured"}
	}
	model = resolveModel(model, currentConfig.Provider)
	var rawMessages []map[string]interface{}
	if err := json.Unmarshal(messages, &rawMessages); err != nil {
		return Response{false, "Failed to parse messages"}
	}
	payload, _ := json.Marshal(map[string]interface{}{"model": model, "messages": rawMessages})
	req, err := http.NewRequest("POST", endpoint, bytes.NewBuffer(payload))
	if err != nil {
		return Response{false, "Failed to create request: " + err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)
	client := &http.Client{Timeout: Timeout}
	resp, err := client.Do(req)
	if err != nil {
		return Response{false, "Request failed: " + err.Error()}
	}
	defer resp.Body.Close()
	return extractOpenAIResponse(resp)
}

// ============================================================
// PROVEEDOR: OPENROUTER
// ============================================================

func handleOpenRouterChat(messages json.RawMessage) Response {
	if currentConfig.OpenRouterKey == "" {
		return Response{false, "No OpenRouter API key configured"}
	}
	model := resolveModel(currentConfig.Model, "openrouter")
	var rawMessages []map[string]interface{}
	if err := json.Unmarshal(messages, &rawMessages); err != nil {
		return Response{false, "Failed to parse messages"}
	}
	payload, _ := json.Marshal(map[string]interface{}{"model": model, "messages": rawMessages})
	req, err := http.NewRequest("POST", "https://openrouter.ai/api/v1/chat/completions", bytes.NewBuffer(payload))
	if err != nil {
		return Response{false, "Failed to create request: " + err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+currentConfig.OpenRouterKey)
	req.Header.Set("HTTP-Referer", "https://github.com/dwarftalk")
	req.Header.Set("X-Title", "DwarfTalk")
	client := &http.Client{Timeout: Timeout}
	resp, err := client.Do(req)
	if err != nil {
		return Response{false, "OpenRouter request failed: " + err.Error()}
	}
	defer resp.Body.Close()
	return extractOpenAIResponse(resp)
}

// ============================================================
// PROVEEDOR: GEMINI
// ============================================================

type GeminiPart struct {
	Text string `json:"text"`
}
type GeminiContent struct {
	Role  string       `json:"role,omitempty"`
	Parts []GeminiPart `json:"parts"`
}
type GeminiRequest struct {
	SystemInstruction *GeminiContent `json:"system_instruction,omitempty"`
	Contents          []GeminiContent `json:"contents"`
}
type GeminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []GeminiPart `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	Error *struct {
		Message string `json:"message"`
		Code    int    `json:"code"`
	} `json:"error,omitempty"`
}

func handleGeminiChat(messages json.RawMessage) Response {
	if currentConfig.GeminiKey == "" {
		return Response{false, "No Gemini API key configured"}
	}
	model := resolveModel(currentConfig.Model, "gemini")
	var rawMessages []map[string]interface{}
	if err := json.Unmarshal(messages, &rawMessages); err != nil {
		return Response{false, "Failed to parse messages"}
	}
	geminiReq := GeminiRequest{}
	for _, msg := range rawMessages {
		role, _ := msg["role"].(string)
		content, _ := msg["content"].(string)
		switch role {
		case "system":
			geminiReq.SystemInstruction = &GeminiContent{Parts: []GeminiPart{{Text: content}}}
		case "user":
			geminiReq.Contents = append(geminiReq.Contents, GeminiContent{Role: "user", Parts: []GeminiPart{{Text: content}}})
		case "assistant":
			geminiReq.Contents = append(geminiReq.Contents, GeminiContent{Role: "model", Parts: []GeminiPart{{Text: content}}})
		}
	}
	payloadBytes, _ := json.Marshal(geminiReq)
	apiURL := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", model, currentConfig.GeminiKey)
	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(payloadBytes))
	if err != nil {
		return Response{false, "Failed to create Gemini request: " + err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: Timeout}
	resp, err := client.Do(req)
	if err != nil {
		return Response{false, "Gemini request failed: " + err.Error()}
	}
	defer resp.Body.Close()
	body, _ := ioutil.ReadAll(resp.Body)
	var geminiResp GeminiResponse
	if err := json.Unmarshal(body, &geminiResp); err != nil {
		return Response{false, "Failed to parse Gemini response: " + err.Error()}
	}
	if geminiResp.Error != nil {
		return Response{false, fmt.Sprintf("Gemini error %d: %s", geminiResp.Error.Code, geminiResp.Error.Message)}
	}
	if len(geminiResp.Candidates) == 0 || len(geminiResp.Candidates[0].Content.Parts) == 0 {
		return Response{false, "No content in Gemini response"}
	}
	content := geminiResp.Candidates[0].Content.Parts[0].Text
	log.Printf("Gemini response: %d chars", len(content))
	return Response{true, content}
}

// ============================================================
// HELPERS
// ============================================================

func resolveModel(model, provider string) string {
	if model == "" {
		return defaultModelForProvider(provider)
	}
	return model
}

func extractOpenAIResponse(resp *http.Response) Response {
	body, _ := ioutil.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		log.Printf("HTTP error %d from provider", resp.StatusCode)
		var errResp map[string]interface{}
		if json.Unmarshal(body, &errResp) == nil {
			if errObj, ok := errResp["error"]; ok {
				if errMap, ok := errObj.(map[string]interface{}); ok {
					if msg, ok := errMap["message"].(string); ok {
						return Response{false, "API error: " + msg}
					}
				}
			}
		}
		return Response{false, fmt.Sprintf("HTTP %d from provider", resp.StatusCode)}
	}
	var apiResp map[string]interface{}
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return Response{false, "Invalid JSON from provider"}
	}
	choices, ok := apiResp["choices"].([]interface{})
	if !ok || len(choices) == 0 {
		return Response{false, "No choices in API response"}
	}
	choice, ok := choices[0].(map[string]interface{})
	if !ok {
		return Response{false, "Invalid choice structure"}
	}
	message, ok := choice["message"].(map[string]interface{})
	if !ok {
		return Response{false, "Invalid message structure"}
	}
	content, ok := message["content"].(string)
	if !ok {
		return Response{false, "Invalid content type"}
	}
	log.Printf("Response: %d chars", len(content))
	return Response{true, content}
}

func keyHint(key string) string {
	if len(key) < 8 {
		return ""
	}
	return "••••" + key[len(key)-4:]
}

// ============================================================
// HEALTH CHECK / STATUS
// ============================================================

func handleHealthCheck() Response {
	requestCounter++
	lastActivity = "Health check"
	checkProviderStatus()
	if providerOK {
		return Response{true, "Provider available: " + currentConfig.Provider}
	}
	return Response{false, providerMsg}
}

func checkProviderStatus() {
	switch currentConfig.Provider {
	case "player2":
		checkPlayer2Status()
	case "openai":
		if currentConfig.OpenAIKey == "" {
			providerOK = false; providerMsg = "No API key set"
		} else {
			providerOK = true; providerMsg = "Ready (model: " + resolveModel(currentConfig.Model, "openai") + ")"
		}
	case "openrouter":
		if currentConfig.OpenRouterKey == "" {
			providerOK = false; providerMsg = "No API key set"
		} else {
			providerOK = true; providerMsg = "Ready (model: " + resolveModel(currentConfig.Model, "openrouter") + ")"
		}
	case "gemini":
		if currentConfig.GeminiKey == "" {
			providerOK = false; providerMsg = "No API key set"
		} else {
			providerOK = true; providerMsg = "Ready (model: " + resolveModel(currentConfig.Model, "gemini") + ")"
		}
	case "custom":
		if currentConfig.CustomURL == "" {
			providerOK = false; providerMsg = "No URL set"
		} else {
			providerOK = true; providerMsg = "Ready (" + currentConfig.CustomURL + ")"
		}
	default:
		providerOK = false; providerMsg = "Unknown provider"
	}
}

func checkPlayer2Status() {
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(Player2LocalEndpoint + "/v1/health")
	if err == nil {
		defer resp.Body.Close()
		body, _ := ioutil.ReadAll(resp.Body)
		var health map[string]interface{}
		if json.Unmarshal(body, &health) == nil {
			if version, ok := health["client_version"]; ok {
				providerOK = true
				providerMsg = fmt.Sprintf("Local app v%v connected", version)
				return
			}
		}
	}
	configMu.Lock()
	hasKey := currentConfig.Player2P2Key != ""
	configMu.Unlock()
	if hasKey {
		providerOK = true
		providerMsg = "Web API (OAuth key saved)"
	} else {
		providerOK = false
		providerMsg = "App not detected · No OAuth key"
	}
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	uptime := time.Since(serverStart)
	uptimeStr := fmt.Sprintf("%dm", int(uptime.Minutes()))
	if uptime.Hours() >= 1 {
		uptimeStr = fmt.Sprintf("%.1fh", uptime.Hours())
	}
	configMu.Lock()
	hasP2Key := currentConfig.Player2P2Key != ""
	configMu.Unlock()
	status := Status{
		Running:        true,
		Provider:       currentConfig.Provider,
		ProviderOK:     providerOK,
		ProviderMsg:    providerMsg,
		RequestCount:   requestCounter,
		Uptime:         uptimeStr,
		LastActivity:   lastActivity,
		Player2UserKey: hasP2Key,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

func handleConfigEndpoint(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method == "GET" {
		configMu.Lock()
		cfg := currentConfig
		configMu.Unlock()
		json.NewEncoder(w).Encode(map[string]interface{}{
			"provider":            cfg.Provider,
			"model":               cfg.Model,
			"openai_key_hint":     keyHint(cfg.OpenAIKey),
			"openrouter_key_hint": keyHint(cfg.OpenRouterKey),
			"gemini_key_hint":     keyHint(cfg.GeminiKey),
			"custom_url":          cfg.CustomURL,
			"custom_key_hint":     keyHint(cfg.CustomKey),
			"player2_key_hint":    keyHint(cfg.Player2P2Key),
			"player2_key_set":     cfg.Player2P2Key != "",
		})
		return
	}
	if r.Method == "POST" {
		var incoming map[string]string
		body, _ := ioutil.ReadAll(r.Body)
		if err := json.Unmarshal(body, &incoming); err != nil {
			w.WriteHeader(400)
			json.NewEncoder(w).Encode(map[string]string{"error": "Invalid JSON"})
			return
		}
		configMu.Lock()
		if v, ok := incoming["provider"]; ok {
			currentConfig.Provider = v
		}
		if v, ok := incoming["model"]; ok {
			currentConfig.Model = v
		}
		if v, ok := incoming["openai_key"]; ok && v != "" {
			currentConfig.OpenAIKey = v
		}
		if v, ok := incoming["openrouter_key"]; ok && v != "" {
			currentConfig.OpenRouterKey = v
		}
		if v, ok := incoming["gemini_key"]; ok && v != "" {
			currentConfig.GeminiKey = v
		}
		if v, ok := incoming["custom_url"]; ok {
			currentConfig.CustomURL = v
		}
		if v, ok := incoming["custom_key"]; ok && v != "" {
			currentConfig.CustomKey = v
		}
		cfg := currentConfig
		configMu.Unlock()
		if err := saveConfig(cfg); err != nil {
			w.WriteHeader(500)
			json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}
		go checkProviderStatus()
		log.Printf("Config updated — provider: %s", cfg.Provider)
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "provider": cfg.Provider})
		return
	}
	w.WriteHeader(405)
}

// ============================================================
// DASHBOARD
// ============================================================

func handleDashboard(w http.ResponseWriter, r *http.Request) {
	html := `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DwarfTalk Bridge</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;background:linear-gradient(135deg,#1a1a2e,#16213e,#0f3460);padding:20px;min-height:100vh;color:#e0e0e0}
.container{max-width:860px;margin:0 auto}

/* header */
.header{background:linear-gradient(135deg,#533483,#0f3460);border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;border:1px solid rgba(255,255,255,.1)}
.header h1{font-size:2.2em;color:#fff;letter-spacing:1px}
.header p{color:rgba(255,255,255,.7);margin-top:6px}
.badge{display:inline-block;background:rgba(255,255,255,.15);padding:3px 10px;border-radius:20px;font-size:.75em;margin-top:8px;color:rgba(255,255,255,.8)}

/* panels */
.panel{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);border-top:none;padding:24px 32px}
.panel:last-child{border-radius:0 0 16px 16px}
.panel-title{font-size:.8em;text-transform:uppercase;letter-spacing:2px;color:rgba(255,255,255,.4);margin-bottom:16px}

/* status */
.status-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px}
.stat-card{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);border-radius:10px;padding:16px}
.stat-card h3{font-size:.72em;text-transform:uppercase;letter-spacing:1px;color:rgba(255,255,255,.4);margin-bottom:8px}
.stat-value{font-size:1.3em;font-weight:600;color:#fff;display:flex;align-items:center;gap:8px}
.dot{width:10px;height:10px;border-radius:50%;flex-shrink:0}
.dot-green{background:#4ade80;box-shadow:0 0 6px #4ade80}
.dot-red{background:#f87171;box-shadow:0 0 6px #f87171}
.dot-yellow{background:#facc15;box-shadow:0 0 6px #facc15}

/* player2 auth */
.p2-card{background:rgba(83,52,131,.15);border:1px solid rgba(124,58,237,.3);border-radius:12px;padding:20px 24px;margin-bottom:4px}
.p2-card h3{font-size:.9em;font-weight:600;color:#c4b5fd;margin-bottom:6px}
.p2-card p{font-size:.82em;color:rgba(255,255,255,.5);margin-bottom:14px;line-height:1.5}
.p2-row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.btn{padding:9px 18px;border-radius:8px;border:none;cursor:pointer;font-size:.88em;font-weight:600;transition:all .2s}
.btn-primary{background:#7c3aed;color:#fff}
.btn-primary:hover{background:#6d28d9}
.btn-primary:disabled{background:#444;cursor:not-allowed}
.btn-danger{background:rgba(248,113,113,.15);color:#f87171;border:1px solid rgba(248,113,113,.3)}
.btn-danger:hover{background:rgba(248,113,113,.25)}
.key-badge{font-size:.8em;padding:4px 10px;border-radius:6px;font-family:monospace}
.key-ok{background:rgba(74,222,128,.1);color:#4ade80;border:1px solid rgba(74,222,128,.3)}
.key-none{color:rgba(255,255,255,.35)}
.feedback{margin-top:10px;font-size:.82em;min-height:18px;transition:color .3s}
@keyframes spin{to{transform:rotate(360deg)}}
.spinner{display:inline-block;width:14px;height:14px;border:2px solid rgba(255,255,255,.3);border-top-color:#fff;border-radius:50%;animation:spin .7s linear infinite;vertical-align:middle;margin-right:6px}

/* tabs */
.tabs{display:flex;gap:6px;margin-bottom:20px;flex-wrap:wrap}
.tab{padding:8px 16px;border-radius:8px;border:1px solid rgba(255,255,255,.15);background:rgba(255,255,255,.04);color:rgba(255,255,255,.6);cursor:pointer;font-size:.88em;transition:all .2s}
.tab:hover{background:rgba(255,255,255,.1);color:#fff}
.tab.active{background:#533483;border-color:#7c3aed;color:#fff}
.ppanel{display:none}
.ppanel.active{display:block}

/* form */
.fg{margin-bottom:14px}
.fg label{display:block;font-size:.82em;color:rgba(255,255,255,.5);margin-bottom:6px;text-transform:uppercase;letter-spacing:.5px}
.fg input{width:100%;padding:10px 14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);border-radius:8px;color:#fff;font-size:.9em;outline:none;transition:border-color .2s}
.fg input:focus{border-color:#7c3aed}
.fg input::placeholder{color:rgba(255,255,255,.25)}
.row2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.hint{font-size:.78em;color:rgba(255,255,255,.35);margin-top:4px}
.khint{font-size:.78em;color:#4ade80;margin-top:4px}
.info{background:rgba(83,52,131,.2);border:1px solid rgba(124,58,237,.3);border-radius:8px;padding:12px 16px;font-size:.83em;color:rgba(255,255,255,.6);margin-bottom:16px;line-height:1.5}
.btn-save{padding:10px 24px;background:#7c3aed;color:#fff;border:none;border-radius:8px;cursor:pointer;font-size:.9em;font-weight:600;transition:background .2s}
.btn-save:hover{background:#6d28d9}
.btn-save:disabled{background:#444;cursor:not-allowed}
.save-st{display:inline-block;margin-left:12px;font-size:.85em;opacity:0;transition:opacity .3s}
.save-st.visible{opacity:1}
.footer{text-align:center;padding:16px;color:rgba(255,255,255,.2);font-size:.8em}
</style>
</head>
<body>
<div class="container">

<div class="header">
  <h1>🏔️ DwarfTalk Bridge</h1>
  <p>AI-Powered Dwarf Conversations</p>
  <span class="badge">v` + Version + ` · Multi-Provider</span>
</div>

<!-- STATUS -->
<div class="panel">
  <div class="panel-title">Status</div>
  <div class="status-grid">
    <div class="stat-card"><h3>Bridge</h3><div class="stat-value"><span class="dot dot-green"></span>Running</div></div>
    <div class="stat-card"><h3>Provider</h3><div class="stat-value" id="pname">—</div></div>
    <div class="stat-card"><h3>Status</h3><div class="stat-value"><span class="dot dot-yellow" id="pdot"></span><span id="pmsg" style="font-size:.75em">Checking...</span></div></div>
    <div class="stat-card"><h3>Requests</h3><div class="stat-value" id="rcount">0</div></div>
    <div class="stat-card"><h3>Uptime</h3><div class="stat-value" id="utime">0m</div></div>
  </div>
</div>

<!-- PLAYER2 AUTH -->
<div class="panel">
  <div class="panel-title">Player2 — Authentication</div>
  <div class="p2-card">
    <h3>🔑 Player2 User Key</h3>
    <p>
      Generate a personal Player2 key without needing the app open.
      The bridge will try the local app first (port 4315). If unavailable,
      it will open the Player2 approval page in your browser — just click Allow.
    </p>
    <div class="p2-row">
      <button class="btn btn-primary" id="btn-getkey" onclick="getP2Key()">Get Player2 Key</button>
      <button class="btn btn-danger" id="btn-clear" onclick="clearP2Key()" style="display:none">🗑 Remove Key</button>
      <span class="key-badge key-none" id="key-display">No key saved</span>
    </div>
    <!-- Device flow user code display -->
    <div id="p2-device-box" style="display:none;margin-top:14px;background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.1);border-radius:10px;padding:14px 18px;">
      <div style="font-size:.8em;color:rgba(255,255,255,.45);margin-bottom:8px;text-transform:uppercase;letter-spacing:1px">Waiting for approval in browser</div>
      <div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap;">
        <div id="p2-usercode" style="font-family:monospace;font-size:1.6em;letter-spacing:4px;color:#c4b5fd;font-weight:700"></div>
        <div style="font-size:.8em;color:rgba(255,255,255,.4)">Enter this code if prompted at<br><a id="p2-verif-link" href="#" target="_blank" style="color:#7c3aed"></a></div>
      </div>
    </div>
    <div class="feedback" id="p2fb"></div>
  </div>
</div>

<!-- CONFIG LLM -->
<div class="panel">
  <div class="panel-title">LLM Provider</div>
  <div class="tabs">
    <button class="tab" data-p="player2" onclick="selTab('player2')">🎮 Player2</button>
    <button class="tab" data-p="openai" onclick="selTab('openai')">OpenAI</button>
    <button class="tab" data-p="openrouter" onclick="selTab('openrouter')">OpenRouter</button>
    <button class="tab" data-p="gemini" onclick="selTab('gemini')">Gemini</button>
    <button class="tab" data-p="custom" onclick="selTab('custom')">⚙️ Custom</button>
  </div>

  <div class="ppanel" id="pp-player2">
    <div class="info">Player2 uses the local app (port 4315) if running, or the Web API with the OAuth key generated above. No additional configuration needed.</div>
  </div>
  <div class="ppanel" id="pp-openai">
    <div class="info">Official OpenAI API. Get your key at <strong>platform.openai.com</strong>.</div>
    <div class="row2">
      <div class="fg"><label>API Key</label><input type="password" id="oai-key" placeholder="sk-..."><div class="khint" id="oai-khint"></div></div>
      <div class="fg"><label>Model</label><input type="text" id="oai-model" placeholder="gpt-4o-mini"><div class="hint">Default: gpt-4o-mini</div></div>
    </div>
  </div>
  <div class="ppanel" id="pp-openrouter">
    <div class="info">Access Claude, Llama, Mistral and more with one key. Sign up at <strong>openrouter.ai</strong>.</div>
    <div class="row2">
      <div class="fg"><label>API Key</label><input type="password" id="or-key" placeholder="sk-or-..."><div class="khint" id="or-khint"></div></div>
      <div class="fg"><label>Model</label><input type="text" id="or-model" placeholder="openai/gpt-4o-mini"><div class="hint">e.g. anthropic/claude-3-haiku</div></div>
    </div>
  </div>
  <div class="ppanel" id="pp-gemini">
    <div class="info">Google Gemini API. Get your key at <strong>aistudio.google.com</strong>.</div>
    <div class="row2">
      <div class="fg"><label>API Key</label><input type="password" id="gem-key" placeholder="AIza..."><div class="khint" id="gem-khint"></div></div>
      <div class="fg"><label>Model</label><input type="text" id="gem-model" placeholder="gemini-2.0-flash"><div class="hint">Default: gemini-2.0-flash</div></div>
    </div>
  </div>
  <div class="ppanel" id="pp-custom">
    <div class="info">Any OpenAI-compatible endpoint: LM Studio, Ollama, vLLM, Together AI, etc.</div>
    <div class="fg"><label>Endpoint URL</label><input type="text" id="cu-url" placeholder="http://localhost:1234/v1/chat/completions"><div class="hint">Must be compatible with /v1/chat/completions</div></div>
    <div class="row2">
      <div class="fg"><label>API Key (optional)</label><input type="password" id="cu-key" placeholder="Leave blank if not required"><div class="khint" id="cu-khint"></div></div>
      <div class="fg"><label>Model</label><input type="text" id="cu-model" placeholder="model-name"></div>
    </div>
  </div>

  <div style="margin-top:8px">
    <button class="btn-save" onclick="saveConfig()">💾 Save & Apply</button>
    <span class="save-st" id="savest"></span>
  </div>
</div>

<div class="footer">DwarfTalk Bridge v` + Version + ` · Keep this window open or minimized</div>
</div>

<script>
let activeTab = 'player2';

function selTab(p) {
  activeTab = p;
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.p === p));
  document.querySelectorAll('.ppanel').forEach(pp => pp.classList.toggle('active', pp.id === 'pp-'+p));
}

// ── Player2 key ─────────────────────────────────────────────
let p2PollTimer = null;

function getP2Key() {
  const btn = document.getElementById('btn-getkey');
  const fb = document.getElementById('p2fb');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span>Connecting...';
  fb.style.color = 'rgba(255,255,255,.5)';
  fb.textContent = 'Trying Player2 local app...';
  document.getElementById('p2-device-box').style.display = 'none';

  fetch('/api/player2/getkey')
  .then(r => r.json())
  .then(d => {
    if (d.status === 'ok') {
      // Local app success
      fb.style.color = '#4ade80';
      fb.textContent = '✓ Key obtained via local app';
      setKeyDisplay(true, d.key_hint || '••••');
      btn.disabled = false;
      btn.textContent = 'Get Player2 Key';
    } else if (d.status === 'pending') {
      // Device flow started — show user code and start polling
      fb.style.color = 'rgba(255,255,255,.5)';
      fb.textContent = '🌐 Browser opened — click Allow on the Player2 page';
      showDeviceCode(d.user_code, d.verification_uri);
      startP2Polling();
      btn.innerHTML = '<span class="spinner"></span>Waiting for approval...';
    } else {
      fb.style.color = '#f87171';
      fb.textContent = '✗ ' + (d.message || 'Unknown error');
      btn.disabled = false;
      btn.textContent = 'Get Player2 Key';
    }
  })
  .catch(e => {
    fb.style.color = '#f87171';
    fb.textContent = '✗ Error: ' + e.message;
    btn.disabled = false;
    btn.textContent = 'Get Player2 Key';
  });
}

function showDeviceCode(userCode, verificationUri) {
  const box = document.getElementById('p2-device-box');
  document.getElementById('p2-usercode').textContent = userCode || '';
  const link = document.getElementById('p2-verif-link');
  link.textContent = verificationUri || '';
  link.href = verificationUri || '#';
  box.style.display = userCode ? 'block' : 'none';
}

function startP2Polling() {
  if (p2PollTimer) clearInterval(p2PollTimer);
  p2PollTimer = setInterval(() => {
    fetch('/api/player2/pollauth')
    .then(r => r.json())
    .then(d => {
      if (d.status === 'done') {
        clearInterval(p2PollTimer);
        p2PollTimer = null;
        document.getElementById('p2-device-box').style.display = 'none';
        document.getElementById('p2fb').style.color = '#4ade80';
        document.getElementById('p2fb').textContent = '✓ Key obtained — you can close the browser tab';
        setKeyDisplay(true, d.key_hint || '••••');
        const btn = document.getElementById('btn-getkey');
        btn.disabled = false;
        btn.textContent = 'Get Player2 Key';
      } else if (d.status === 'error') {
        clearInterval(p2PollTimer);
        p2PollTimer = null;
        document.getElementById('p2-device-box').style.display = 'none';
        document.getElementById('p2fb').style.color = '#f87171';
        document.getElementById('p2fb').textContent = '✗ ' + (d.error || 'Unknown error');
        const btn = document.getElementById('btn-getkey');
        btn.disabled = false;
        btn.textContent = 'Get Player2 Key';
      }
      // if pending, keep polling
    })
    .catch(() => {});
  }, 3000);
}

function clearP2Key() {
  if (!confirm('Remove the saved Player2 key?')) return;
  fetch('/api/player2/clearkey', {method:'POST'})
  .then(r => r.json())
  .then(() => {
    setKeyDisplay(false, '');
    document.getElementById('p2fb').textContent = '';
  });
}

function setKeyDisplay(has, hint) {
  const d = document.getElementById('key-display');
  const c = document.getElementById('btn-clear');
  if (has) {
    d.className = 'key-badge key-ok';
    d.textContent = 'Saved: ' + hint;
    c.style.display = 'inline-block';
  } else {
    d.className = 'key-badge key-none';
    d.textContent = 'No key saved';
    c.style.display = 'none';
  }
}

// ── Config ───────────────────────────────────────────────────
function showSave(ok, msg) {
  const el = document.getElementById('savest');
  el.textContent = (ok ? '✓ ' : '✗ ') + msg;
  el.style.color = ok ? '#4ade80' : '#f87171';
  el.classList.add('visible');
  setTimeout(() => el.classList.remove('visible'), 3000);
}

function saveConfig() {
  const p = {provider: activeTab};
  if (activeTab==='openai')      { const k=document.getElementById('oai-key').value.trim(); if(k) p.openai_key=k; p.model=document.getElementById('oai-model').value.trim(); }
  if (activeTab==='openrouter')  { const k=document.getElementById('or-key').value.trim();  if(k) p.openrouter_key=k; p.model=document.getElementById('or-model').value.trim(); }
  if (activeTab==='gemini')      { const k=document.getElementById('gem-key').value.trim(); if(k) p.gemini_key=k; p.model=document.getElementById('gem-model').value.trim(); }
  if (activeTab==='custom')      { p.custom_url=document.getElementById('cu-url').value.trim(); const k=document.getElementById('cu-key').value.trim(); if(k) p.custom_key=k; p.model=document.getElementById('cu-model').value.trim(); }
  const btn = document.querySelector('.btn-save');
  btn.disabled=true; btn.textContent='Saving...';
  fetch('/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(p)})
  .then(r=>r.json()).then(d=>{ if(d.status==='ok') showSave(true,'Settings applied'); else showSave(false,d.error||'Error'); })
  .catch(()=>showSave(false,'Network error'))
  .finally(()=>{ btn.disabled=false; btn.textContent='💾 Save & Apply'; });
}

// ── Init ─────────────────────────────────────────────────────
function loadConfig() {
  fetch('/api/config').then(r=>r.json()).then(d=>{
    selTab(d.provider||'player2');
    if(d.openai_key_hint)     document.getElementById('oai-khint').textContent  = 'Saved: '+d.openai_key_hint;
    if(d.openrouter_key_hint) document.getElementById('or-khint').textContent   = 'Saved: '+d.openrouter_key_hint;
    if(d.gemini_key_hint)     document.getElementById('gem-khint').textContent  = 'Saved: '+d.gemini_key_hint;
    if(d.custom_key_hint)     document.getElementById('cu-khint').textContent   = 'Saved: '+d.custom_key_hint;
    if(d.custom_url)          document.getElementById('cu-url').value = d.custom_url;
    const m = d.model||'';
    if(d.provider==='openai')     document.getElementById('oai-model').value = m;
    if(d.provider==='openrouter') document.getElementById('or-model').value  = m;
    if(d.provider==='gemini')     document.getElementById('gem-model').value = m;
    if(d.provider==='custom')     document.getElementById('cu-model').value  = m;
    setKeyDisplay(d.player2_key_set, d.player2_key_hint||'');
  }).catch(()=>{});
}

function updateStatus() {
  fetch('/api/status').then(r=>r.json()).then(d=>{
    document.getElementById('pname').textContent  = d.provider||'—';
    document.getElementById('rcount').textContent = d.request_count;
    document.getElementById('utime').textContent  = d.uptime;
    document.getElementById('pmsg').textContent   = d.provider_msg||'—';
    document.getElementById('pdot').className = 'dot '+(d.provider_ok?'dot-green':'dot-red');
  }).catch(()=>{});
}

loadConfig();
updateStatus();
setInterval(updateStatus, 3000);
</script>
</body>
</html>`
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(html))
}

// ============================================================
// UTILS
// ============================================================

func openBrowser(u string) {
	var err error
	switch runtime.GOOS {
	case "windows":
		err = exec.Command("rundll32", "url.dll,FileProtocolHandler", u).Start()
	case "darwin":
		err = exec.Command("open", u).Start()
	default:
		err = exec.Command("xdg-open", u).Start()
	}
	if err != nil {
		log.Println("Please open:", u)
	}
}