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
	"strings"
	"time"
)

const (
	Player2LocalEndpoint = "http://127.0.0.1:4315"
	Player2APIEndpoint   = "https://api.player2.game/v1"
	
	// PROTECTED - DO NOT MODIFY
	// This GameClientID must remain unchanged in all versions, forks, and derivatives
	GameClientID = "019c23d7-e3e9-7381-b2bd-b186f184ac7b" // LEGALLY PROTECTED
	
	ServerPort   = ":4316"
	Timeout      = 30 * time.Second
	Version      = "1.0.4"
	PollInterval = 500 * time.Millisecond
)

// DEBUG MODE - Set to true for detailed logging
var DEBUG_MODE = false

type Request struct {
	Command  string          `json:"command"`
	Messages json.RawMessage `json:"messages"`
}

type Response struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

type Status struct {
	Running       bool   `json:"running"`
	Player2Status string `json:"player2_status"`
	Player2OK     bool   `json:"player2_ok"`
	RequestCount  int    `json:"request_count"`
	Uptime        string `json:"uptime"`
	LastActivity  string `json:"last_activity"`
}

var (
	requestCounter = 0
	startTime      = time.Now()
	lastActivity   = "Server started"
	player2OK      = false
	player2Status  = "Checking..."
	tempDir        string
	dfRootDir      string
	userP2Key      = "" // User's authentication token
)

// Debug logger
func debugLog(format string, v ...interface{}) {
	if DEBUG_MODE {
		log.Printf("[DEBUG] "+format, v...)
	}
}

func main() {
	// Verify GameClientID integrity
	expectedKey := "019c23d7-e3e9-7381-b2bd-b186f184ac7b"
	if GameClientID != expectedKey {
		log.Fatal("ERROR: GameClientID has been modified. This violates the software license.")
	}

	log.Println("╔════════════════════════════════════════╗")
	log.Println("║   DwarfTalk Bridge Server v" + Version + "   ║")
	log.Println("║   File Polling Mode                    ║")
	if DEBUG_MODE {
		log.Println("║   🔍 DEBUG MODE ENABLED                ║")
	}
	log.Println("╚════════════════════════════════════════╝")
	log.Println()

	exePath, _ := os.Executable()
	dfRootDir = filepath.Dir(exePath)

	log.Println("Dwarf Fortress directory:", dfRootDir)
	log.Println()

	if err := setupDirectories(); err != nil {
		log.Fatal("Failed to create directories:", err)
	}

	// Authenticate with Player2
	log.Println("🔐 Authenticating with Player2...")
	if err := authenticateUser(); err != nil {
		log.Printf("⚠️  Authentication failed: %v", err)
		log.Println("⚠️  Will retry authentication on first request")
	} else {
		log.Println("✓ Authentication successful")
	}
	log.Println()

	// Start health check routine (every 60 seconds)
	go healthCheckRoutine()

	// Poll BOTH regular and NPC request files
	go pollRequestFile()
	go pollNPCRequestFile()

	http.HandleFunc("/", handleDashboard)
	http.HandleFunc("/api/status", handleStatus)

	// Check Player2 app status
	go func() {
		for {
			checkPlayer2AppStatus()
			time.Sleep(5 * time.Second)
		}
	}()

	go func() {
		time.Sleep(1 * time.Second)
		openBrowser("http://localhost:4316")
	}()

	log.Println("✓ Server started successfully")
	log.Println("✓ Dashboard: http://localhost:4316")
	log.Println("✓ Monitoring request files in:", tempDir)
	log.Println("✓ Health check: Running every 60s")
	if DEBUG_MODE {
		log.Println("✓ DEBUG MODE: All requests/responses will be logged")
	}
	log.Println()
	log.Println("Press Ctrl+C to stop")
	log.Println()

	if err := http.ListenAndServe(ServerPort, nil); err != nil {
		log.Fatal("Server error:", err)
	}
}

// Authenticate user and get p2Key
func authenticateUser() error {
	client := &http.Client{Timeout: 5 * time.Second}
	
	url := fmt.Sprintf("%s/v1/login/web/%s", Player2LocalEndpoint, GameClientID)
	debugLog("Authentication URL: %s", url)
	
	resp, err := client.Post(url, "application/json", nil)
	if err != nil {
		return fmt.Errorf("failed to connect to Player2 app: %v", err)
	}
	defer resp.Body.Close()

	body, _ := ioutil.ReadAll(resp.Body)
	debugLog("Auth response: %s", string(body))

	var authData map[string]interface{}
	if err := json.Unmarshal(body, &authData); err != nil {
		return fmt.Errorf("invalid auth response: %v", err)
	}

	if p2Key, ok := authData["p2Key"].(string); ok && p2Key != "" {
		userP2Key = p2Key
		debugLog("Obtained p2Key: %s...%s", p2Key[:8], p2Key[len(p2Key)-8:])
		return nil
	}

	return fmt.Errorf("no p2Key in response")
}

// Health check routine - runs every 60 seconds
func healthCheckRoutine() {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	// First health check immediately
	sendHealthCheck()

	for range ticker.C {
		sendHealthCheck()
	}
}

// Send health check to Player2 API
func sendHealthCheck() {
	debugLog("Sending health check...")

	// Re-authenticate if needed
	if userP2Key == "" {
		if err := authenticateUser(); err != nil {
			debugLog("Health check skipped - authentication failed: %v", err)
			return
		}
	}

	client := &http.Client{Timeout: 5 * time.Second}
	
	req, err := http.NewRequest("GET", Player2APIEndpoint+"/health", nil)
	if err != nil {
		debugLog("Failed to create health check request: %v", err)
		return
	}

	req.Header.Set("Authorization", "Bearer "+userP2Key)

	resp, err := client.Do(req)
	if err != nil {
		debugLog("Health check failed: %v", err)
		// Try to re-authenticate
		userP2Key = ""
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == 200 {
		debugLog("✓ Health check successful (usage tracked)")
	} else {
		debugLog("Health check returned status %d", resp.StatusCode)
		// Invalid token - re-authenticate next time
		if resp.StatusCode == 401 {
			userP2Key = ""
		}
	}
}

// NEW: Separate polling function for NPC requests
func pollNPCRequestFile() {
	requestPath := filepath.Join(tempDir, "npc_request.json")
	responsePath := filepath.Join(tempDir, "npc_response.json")

	log.Println("Started polling for NPC request files...")

	for {
		time.Sleep(PollInterval)

		if _, err := os.Stat(requestPath); os.IsNotExist(err) {
			continue
		}

		data, err := ioutil.ReadFile(requestPath)
		if err != nil {
			log.Println("❌ Error reading NPC request:", err)
			continue
		}

		os.Remove(requestPath)

		log.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		log.Println("📥 NPC REQUEST RECEIVED")
		log.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		debugLog("NPC request size: %d bytes", len(data))

		var req Request
		if err := json.Unmarshal(data, &req); err != nil {
			log.Println("❌ Error parsing NPC request:", err)
			writeResponse(responsePath, Response{Success: false, Message: "Invalid request format"})
			continue
		}

		debugLog("NPC command: %s", req.Command)

		var resp Response
		startTime := time.Now()

		switch req.Command {
		case "chat":
			resp = handleChatRequest(req.Messages)
		default:
			resp = Response{Success: false, Message: "Unknown command: " + req.Command}
		}

		elapsed := time.Since(startTime)
		
		writeResponse(responsePath, resp)
		
		log.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		log.Printf("📤 NPC RESPONSE SENT (took %v)", elapsed)
		log.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		debugLog("NPC Success: %v", resp.Success)
		if resp.Success {
			debugLog("NPC Response length: %d chars", len(resp.Message))
		}
		log.Println()
	}
}

func setupDirectories() error {
	directories := map[string]string{
		"temp":     "dwarftalk_temp",
		"saves":    "dwarftalk_saves",
		"analysis": "dwarftalk_analysis",
	}

	log.Println("Creating necessary directories...")

	for name, dir := range directories {
		fullPath := filepath.Join(dfRootDir, dir)

		if _, err := os.Stat(fullPath); os.IsNotExist(err) {
			if err := os.MkdirAll(fullPath, 0755); err != nil {
				return fmt.Errorf("failed to create %s directory: %v", name, err)
			}
			log.Printf("  ✓ Created: %s", fullPath)
		} else {
			log.Printf("  ✓ Exists: %s", fullPath)
		}

		if name == "temp" {
			tempDir = fullPath
		}
	}

	log.Println()
	return nil
}

func pollRequestFile() {
	requestPath := filepath.Join(tempDir, "request.json")
	responsePath := filepath.Join(tempDir, "response.json")

	log.Println("Started polling for request files...")

	for {
		time.Sleep(PollInterval)

		if _, err := os.Stat(requestPath); os.IsNotExist(err) {
			continue
		}

		data, err := ioutil.ReadFile(requestPath)
		if err != nil {
			log.Println("❌ Error reading request:", err)
			continue
		}

		os.Remove(requestPath)

		log.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		log.Println("📥 REQUEST RECEIVED")
		log.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		debugLog("Raw request size: %d bytes", len(data))

		var req Request
		if err := json.Unmarshal(data, &req); err != nil {
			log.Println("❌ Error parsing request:", err)
			debugLog("Raw request data: %s", string(data))
			writeResponse(responsePath, Response{Success: false, Message: "Invalid request format"})
			continue
		}

		debugLog("Command: %s", req.Command)

		var resp Response
		startTime := time.Now()

		switch req.Command {
		case "chat":
			resp = handleChatRequest(req.Messages)
		default:
			resp = Response{Success: false, Message: "Unknown command: " + req.Command}
		}

		elapsed := time.Since(startTime)
		
		writeResponse(responsePath, resp)
		
		log.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		log.Printf("📤 RESPONSE SENT (took %v)", elapsed)
		log.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		log.Println()
	}
}

func writeResponse(path string, resp Response) {
	data, _ := json.Marshal(resp)
	ioutil.WriteFile(path, data, 0644)
}

func handleChatRequest(messages json.RawMessage) Response {
	requestCounter++
	lastActivity = "Chat request"
	
	log.Println("🤖 Processing chat request...")

	// Re-authenticate if needed
	if userP2Key == "" {
		log.Println("🔐 Re-authenticating...")
		if err := authenticateUser(); err != nil {
			log.Printf("❌ Authentication failed: %v", err)
			return Response{Success: false, Message: "Authentication failed - is Player2 App running?"}
		}
		log.Println("✓ Re-authentication successful")
	}

	client := &http.Client{Timeout: Timeout}
	payload := map[string]interface{}{"messages": json.RawMessage(messages)}
	payloadBytes, _ := json.Marshal(payload)

	debugLog("Payload size: %d bytes", len(payloadBytes))

	httpReq, err := http.NewRequest("POST", Player2APIEndpoint+"/chat/completions", bytes.NewBuffer(payloadBytes))
	if err != nil {
		log.Printf("❌ Failed to create request: %v", err)
		return Response{Success: false, Message: "Failed to create request"}
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+userP2Key)

	debugLog("Sending request to Player2 API...")
	requestStart := time.Now()

	resp, err := client.Do(httpReq)
	if err != nil {
		elapsed := time.Since(requestStart)
		log.Printf("❌ Player2 request failed after %v: %v", elapsed, err)
		
		if strings.Contains(err.Error(), "timeout") {
			return Response{Success: false, Message: "Request timeout - is Player2 responding?"}
		}
		
		return Response{Success: false, Message: "Request failed: " + err.Error()}
	}
	defer resp.Body.Close()

	elapsed := time.Since(requestStart)
	debugLog("Player2 responded in %v", elapsed)

	body, _ := ioutil.ReadAll(resp.Body)
	debugLog("Response status: %d", resp.StatusCode)

	if resp.StatusCode == 401 {
		log.Println("❌ Authentication expired - re-authenticating...")
		userP2Key = ""
		return Response{Success: false, Message: "Authentication expired - please try again"}
	}

	if resp.StatusCode != 200 {
		log.Printf("❌ HTTP error %d from Player2", resp.StatusCode)
		debugLog("Error response body: %s", string(body))
		return Response{Success: false, Message: fmt.Sprintf("HTTP %d", resp.StatusCode)}
	}

	var apiResponse map[string]interface{}
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		log.Printf("❌ Failed to parse Player2 response: %v", err)
		return Response{Success: false, Message: "Invalid JSON response from Player2"}
	}

	// Extract content
	choices, ok := apiResponse["choices"].([]interface{})
	if !ok || len(choices) == 0 {
		log.Println("❌ No choices in API response")
		return Response{Success: false, Message: "No response content from Player2"}
	}

	choice, ok := choices[0].(map[string]interface{})
	if !ok {
		log.Println("❌ Invalid choice structure")
		return Response{Success: false, Message: "Invalid response structure"}
	}

	message, ok := choice["message"].(map[string]interface{})
	if !ok {
		log.Println("❌ Invalid message structure")
		return Response{Success: false, Message: "Invalid message structure"}
	}

	content, ok := message["content"].(string)
	if !ok {
		log.Println("❌ Invalid content type")
		return Response{Success: false, Message: "Invalid content type"}
	}

	log.Printf("✓ Chat response received: %d characters", len(content))

	return Response{Success: true, Message: content}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// Check Player2 APP status (not API)
func checkPlayer2AppStatus() {
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(Player2LocalEndpoint + "/v1/health")

	if err != nil {
		player2OK = false
		player2Status = "App Not Running"
		return
	}
	defer resp.Body.Close()

	body, _ := ioutil.ReadAll(resp.Body)
	var healthData map[string]interface{}

	if err := json.Unmarshal(body, &healthData); err == nil {
		if version, ok := healthData["client_version"]; ok {
			player2OK = true
			player2Status = fmt.Sprintf("App Connected (v%v)", version)
			return
		}
	}

	player2OK = false
	player2Status = "Invalid Response"
}

func handleDashboard(w http.ResponseWriter, r *http.Request) {
	debugStatus := ""
	if DEBUG_MODE {
		debugStatus = " 🔍 DEBUG"
	}

	html := `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>DwarfTalk Bridge</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { opacity: 0.9; font-size: 1.1em; }
        .content { padding: 30px; }
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .status-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #667eea;
        }
        .status-card h3 {
            color: #666;
            font-size: 0.9em;
            margin-bottom: 10px;
            text-transform: uppercase;
        }
        .status-card .value {
            font-size: 1.8em;
            font-weight: bold;
            color: #333;
        }
        .status-ok { color: #28a745; }
        .status-error { color: #dc3545; }
        .indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .indicator.green { background: #28a745; }
        .indicator.red { background: #dc3545; }
        .footer {
            text-align: center;
            padding: 20px;
            color: #999;
            border-top: 1px solid #e0e0e0;
        }
        .minimize-hint {
            background: #fff3cd;
            border: 1px solid #ffc107;
            padding: 15px;
            border-radius: 10px;
            margin-top: 20px;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏔️ DwarfTalk Bridge</h1>
            <p>AI-Powered Dwarf Conversations for Dwarf Fortress</p>
            <small>v` + Version + debugStatus + `</small>
        </div>
        
        <div class="content">
            <div class="status-grid">
                <div class="status-card">
                    <h3>Server Status</h3>
                    <div class="value status-ok">
                        <span class="indicator green"></span>Running
                    </div>
                </div>
                
                <div class="status-card">
                    <h3>Player2 Status</h3>
                    <div class="value" id="player2-status">
                        <span class="indicator" id="player2-indicator"></span>
                        <span id="player2-text">Checking...</span>
                    </div>
                </div>
                
                <div class="status-card">
                    <h3>Requests Handled</h3>
                    <div class="value" id="request-count">0</div>
                </div>
                
                <div class="status-card">
                    <h3>Uptime</h3>
                    <div class="value" id="uptime">0m</div>
                </div>
            </div>
            
            <div class="minimize-hint">
                ℹ️ Keep this window open or minimize it while playing Dwarf Fortress.
            </div>
        </div>
        
        <div class="footer">
            DwarfTalk Bridge v` + Version + `
        </div>
    </div>
    
    <script>
        function updateStatus() {
            fetch('/api/status')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('request-count').textContent = data.request_count;
                    document.getElementById('uptime').textContent = data.uptime;
                    
                    const indicator = document.getElementById('player2-indicator');
                    const text = document.getElementById('player2-text');
                    
                    if (data.player2_ok) {
                        indicator.className = 'indicator green';
                        text.textContent = data.player2_status;
                        text.className = 'status-ok';
                    } else {
                        indicator.className = 'indicator red';
                        text.textContent = data.player2_status;
                        text.className = 'status-error';
                    }
                });
        }
        
        setInterval(updateStatus, 2000);
        updateStatus();
    </script>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(html))
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	uptime := time.Since(startTime)
	uptimeStr := fmt.Sprintf("%dm", int(uptime.Minutes()))
	if uptime.Hours() >= 1 {
		uptimeStr = fmt.Sprintf("%.1fh", uptime.Hours())
	}

	status := Status{
		Running:       true,
		Player2Status: player2Status,
		Player2OK:     player2OK,
		RequestCount:  requestCounter,
		Uptime:        uptimeStr,
		LastActivity:  lastActivity,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

func openBrowser(url string) {
	var err error
	switch runtime.GOOS {
	case "windows":
		err = exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	case "darwin":
		err = exec.Command("open", url).Start()
	default:
		err = exec.Command("xdg-open", url).Start()
	}
	if err != nil {
		log.Println("Please open:", url)
	}
}