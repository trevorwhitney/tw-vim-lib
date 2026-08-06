package main

import (
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_AgentdSocket(t *testing.T) {
	t.Run("XDG_STATE_HOME wins", func(t *testing.T) {
		t.Setenv("XDG_STATE_HOME", "/xdg")
		assert.Equal(t, "/xdg/agentd/agentd.sock", agentdSocket())
	})
	t.Run("falls back to ~/.local/state/agentd", func(t *testing.T) {
		t.Setenv("XDG_STATE_HOME", "")
		t.Setenv("HOME", "/home/me")
		assert.Equal(t, filepath.Join("/home/me", ".local/state/agentd/agentd.sock"), agentdSocket())
	})
}
