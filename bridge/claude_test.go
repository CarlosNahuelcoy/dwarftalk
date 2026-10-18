package main

import (
	"strings"
	"testing"
)

func TestCleanModelText(t *testing.T) {
	in := "```json\n{\"dialogue\": \"I don\u2019t care\u2014go away\u2026\", \"action\": {\"type\": \"none\"}}\n```"
	want := `{"dialogue": "I don't care - go away...", "action": {"type": "none"}}`
	if got := cleanModelText(in); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestFlattenForCLI(t *testing.T) {
	msgs := []map[string]interface{}{
		{"role": "system", "content": "You are Urist."},
		{"role": "user", "content": "Hi"},
		{"role": "assistant", "content": "Hmph."},
		{"role": "user", "content": "How's the ale?"},
	}
	sys, prompt := flattenForCLI(msgs)
	if sys != "You are Urist." {
		t.Fatalf("system = %q", sys)
	}
	for _, s := range []string{"[player]: Hi", "[you]: Hmph.", "How's the ale?"} {
		if !strings.Contains(prompt, s) {
			t.Fatalf("prompt missing %q:\n%s", s, prompt)
		}
	}
	if _, p := flattenForCLI(msgs[:2]); p != "Hi" {
		t.Fatalf("single turn prompt = %q", p)
	}
}
