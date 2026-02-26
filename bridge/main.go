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
	Player2Endpoint = "http://127.0.0.1:4315"
	
	// PROTECTED - DO NOT MODIFY
	// This GameKey must remain unchanged in all versions, forks, and derivatives
	GameKey = "019c23d7-e3e9-7381-b2bd-b186f184ac7b" // LEGALLY PROTECTED
	
	ServerPort      = ":4316"
	Timeout         = 30 * time.Second
	Version         = "1.0.3"
	PollInterval    = 500 * time.Millisecond
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
)

// Debug logger
func debugLog(format string, v ...interface{}) {
	if DEBUG_MODE {
		log.Printf("[DEBUG] "+format, v...)
	}
}

func main() {
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

	// Poll BOTH regular and NPC request files
	go pollRequestFile()
	go pollNPCRequestFile() // NEW: Separate polling for NPC requests

	http.HandleFunc("/", handleDashboard)
	http.HandleFunc("/api/status", handleStatus)

	go func() {
		for {
			checkPlayer2Status()
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
	log.Println("✓ NPC request polling active") // NEW
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
		if req.Command == "chat" {
			debugLog("Messages payload size: %d bytes", len(req.Messages))
			
			// Parse messages to show structure
			var messages []map[string]interface{}
			if err := json.Unmarshal(req.Messages, &messages); err == nil {
				debugLog("Number of messages: %d", len(messages))
				for i, msg := range messages {
					role := msg["role"]
					content := msg["content"]
					if contentStr, ok := content.(string); ok {
						debugLog("  Message %d: role=%s, length=%d chars", i+1, role, len(contentStr))
						if len(contentStr) > 200 {
							debugLog("    Preview: %s...", contentStr[:200])
						} else {
							debugLog("    Content: %s", contentStr)
						}
					}
				}
			}
		}

		var resp Response
		startTime := time.Now()

		switch req.Command {
		case "health":
			resp = handleHealthCheck()
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
		debugLog("Success: %v", resp.Success)
		if resp.Success {
			debugLog("Response length: %d chars", len(resp.Message))
			if len(resp.Message) > 200 {
				debugLog("Response preview: %s...", resp.Message[:200])
			} else {
				debugLog("Response: %s", resp.Message)
			}
		} else {
			log.Printf("❌ ERROR: %s", resp.Message)
		}
		log.Println()
	}
}

func writeResponse(path string, resp Response) {
	data, _ := json.Marshal(resp)
	ioutil.WriteFile(path, data, 0644)
}

func handleHealthCheck() Response {
	requestCounter++
	lastActivity = "Health check"
	debugLog("Processing health check...")

	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(Player2Endpoint + "/v1/health")
	if err != nil {
		debugLog("Health check failed: %v", err)
		return Response{Success: false, Message: "Player2 not running"}
	}
	defer resp.Body.Close()

	body, _ := ioutil.ReadAll(resp.Body)
	debugLog("Health response: %s", string(body))

	var healthData map[string]interface{}
	if err := json.Unmarshal(body, &healthData); err != nil {
		return Response{Success: false, Message: "Invalid response"}
	}

	if _, ok := healthData["client_version"]; ok {
		return Response{Success: true, Message: "Player2 is running"}
	}

	return Response{Success: false, Message: "Invalid response"}
}

func handleChatRequest(messages json.RawMessage) Response {
	requestCounter++
	lastActivity = "Chat request"
	
	log.Println("🤖 Processing chat request...")
	debugLog("Creating Player2 API request...")

	client := &http.Client{Timeout: Timeout}
	payload := map[string]interface{}{"messages": json.RawMessage(messages)}
	payloadBytes, _ := json.Marshal(payload)

	debugLog("Payload size: %d bytes", len(payloadBytes))

	httpReq, err := http.NewRequest("POST", Player2Endpoint+"/v1/chat/completions", bytes.NewBuffer(payloadBytes))
	if err != nil {
		log.Printf("❌ Failed to create request: %v", err)
		return Response{Success: false, Message: "Failed to create request"}
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("player2-game-key", GameKey)

	debugLog("Sending request to Player2...")
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
	debugLog("Response body size: %d bytes", len(body))

	if resp.StatusCode != 200 {
		log.Printf("❌ HTTP error %d from Player2", resp.StatusCode)
		debugLog("Error response body: %s", string(body))
		
		var errorResp map[string]interface{}
		if json.Unmarshal(body, &errorResp) == nil {
			if errMsg, ok := errorResp["error"]; ok {
				return Response{Success: false, Message: fmt.Sprintf("HTTP %d: %v", resp.StatusCode, errMsg)}
			}
		}
		
		return Response{Success: false, Message: fmt.Sprintf("HTTP %d", resp.StatusCode)}
	}

	var apiResponse map[string]interface{}
	if err := json.Unmarshal(body, &apiResponse); err != nil {
		log.Printf("❌ Failed to parse Player2 response: %v", err)
		debugLog("Invalid JSON response: %s", string(body[:min(500, len(body))]))
		return Response{Success: false, Message: "Invalid JSON response from Player2"}
	}

	debugLog("Parsed API response successfully")

	// Extract content
	choices, ok := apiResponse["choices"].([]interface{})
	if !ok || len(choices) == 0 {
		log.Println("❌ No choices in API response")
		debugLog("API response structure: %+v", apiResponse)
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
	debugLog("Response content: %s", content)
	
	// ============================================================
	// NUEVO: GUARDAR RESPUESTA RAW EN ARCHIVO PARA DEBUG
	// ============================================================
	rawResponsePath := filepath.Join(tempDir, "go_raw_response.txt")
	if err := ioutil.WriteFile(rawResponsePath, []byte(content), 0644); err == nil {
		log.Printf("✓ Saved raw response to: %s", rawResponsePath)
	}
	
	// ============================================================
	// NUEVO: ANALIZAR SI HAY ACTION EN LA RESPUESTA
	// ============================================================
	if strings.Contains(content, "ACTION:") {
		log.Println("✅✅✅ DETECTED ACTION IN RESPONSE!")
		
		// Extraer la línea de ACTION
		lines := strings.Split(content, "\n")
		for i, line := range lines {
			if strings.Contains(line, "ACTION:") {
				log.Printf("  → Line %d: %s", i+1, line)
				
				// Intentar parsear el JSON
				jsonStart := strings.Index(line, "{")
				if jsonStart >= 0 {
					jsonStr := line[jsonStart:]
					var actionData map[string]interface{}
					if err := json.Unmarshal([]byte(jsonStr), &actionData); err == nil {
						log.Printf("  → Parsed action type: %v", actionData["type"])
						log.Printf("  → Parsed action amount: %v", actionData["amount"])
					} else {
						log.Printf("  → ⚠️ Could not parse JSON: %v", err)
					}
				}
			}
		}
	} else {
		log.Println("⚠️ NO ACTION detected in response")
	}
	
	// ============================================================
	// NUEVO: LOG DEL RESPONSE.JSON QUE SE VA A ESCRIBIR
	// ============================================================
	finalResponse := Response{Success: true, Message: content}
	responseJSON, _ := json.MarshalIndent(finalResponse, "", "  ")
	log.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	log.Println("📝 RESPONSE.JSON CONTENT:")
	log.Println(string(responseJSON))
	log.Println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	return finalResponse
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func checkPlayer2Status() {
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(Player2Endpoint + "/v1/health")

	if err != nil {
		player2OK = false
		player2Status = "Not Running"
		return
	}
	defer resp.Body.Close()

	body, _ := ioutil.ReadAll(resp.Body)
	var healthData map[string]interface{}

	if err := json.Unmarshal(body, &healthData); err == nil {
		if version, ok := healthData["client_version"]; ok {
			player2OK = true
			player2Status = fmt.Sprintf("Connected (v%v)", version)
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
        .debug-badge {
            background: #ffc107;
            color: #000;
            padding: 5px 10px;
            border-radius: 5px;
            font-size: 0.8em;
            font-weight: bold;
            margin-top: 10px;
            display: inline-block;
        }
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
            <small>File Polling Mode v` + Version + debugStatus + `</small>` +
		(func() string {
			if DEBUG_MODE {
				return `<div class="debug-badge">🔍 DEBUG MODE ACTIVE - Check console for detailed logs</div>`
			}
			return ""
		})() + `
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
                ℹ️ Keep this window open or minimize it. The bridge monitors files automatically.
            </div>
        </div>
        
        <div class="footer">
            DwarfTalk Bridge v` + Version + ` | File Polling Mode
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