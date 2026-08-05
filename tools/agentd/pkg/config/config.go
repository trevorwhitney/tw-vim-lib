// Package config loads the agentd configuration file and the optional
// separate rules file holding per-repository policy chains.
package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// Duration is a time.Duration that unmarshals from YAML strings like "4h".
type Duration time.Duration

func (d *Duration) UnmarshalYAML(n *yaml.Node) error {
	dur, err := time.ParseDuration(n.Value)
	if err != nil {
		return fmt.Errorf("invalid duration %q: %w", n.Value, err)
	}
	*d = Duration(dur)
	return nil
}

type Notify struct {
	Banner    string `yaml:"banner"`
	BadgeFile string `yaml:"badge_file"`
}

type Escalation struct {
	RenotifyAfter Duration `yaml:"renotify_after"`
	ParkAfter     Duration `yaml:"park_after"`
}

// PolicyEntry is one named policy with its raw YAML config, decoded later by
// the policy registry.
type PolicyEntry struct {
	Name string
	Raw  *yaml.Node
}

// Repository is one watched repo with its ordered, first-match-wins policy
// chain.
type Repository struct {
	Repo     string
	Local    string
	Policies []PolicyEntry
}

func (r *Repository) UnmarshalYAML(n *yaml.Node) error {
	var aux struct {
		Repo     string    `yaml:"repo"`
		Local    string    `yaml:"local"`
		Policies yaml.Node `yaml:"policies"`
	}
	if err := n.Decode(&aux); err != nil {
		return err
	}
	r.Repo = aux.Repo
	r.Local = aux.Local
	if aux.Policies.Kind == yaml.MappingNode {
		for i := 0; i+1 < len(aux.Policies.Content); i += 2 {
			r.Policies = append(r.Policies, PolicyEntry{
				Name: aux.Policies.Content[i].Value,
				Raw:  aux.Policies.Content[i+1],
			})
		}
	}
	return nil
}

type Config struct {
	PollInterval     Duration     `yaml:"poll_interval"`
	Concurrency      int          `yaml:"concurrency"`
	Database         string       `yaml:"database"`
	Socket           string       `yaml:"socket"`
	Rules            string       `yaml:"rules"`
	TmuxSession      string       `yaml:"tmux_session"`
	TmuxSocketName   string       `yaml:"tmux_socket_name"`
	OnRestart        string       `yaml:"on_restart"`
	OpencodeBin      string       `yaml:"opencode_bin"`
	DropinCommand    string       `yaml:"dropin_command"`
	AllowOperatorPRs bool         `yaml:"allow_operator_prs"`
	Notify           Notify       `yaml:"notify"`
	Escalation       Escalation   `yaml:"escalation"`
	Repositories     []Repository `yaml:"repositories"`
}

// Load reads, defaults, and validates the config at path. Repositories come
// from exactly one of: an inline repositories block, or the file named by
// rules.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if cfg.Rules != "" {
		if len(cfg.Repositories) > 0 {
			return nil, errors.New("repositories must come from either the rules file or an inline block, not both")
		}
		rdata, err := os.ReadFile(expandHome(cfg.Rules))
		if err != nil {
			return nil, fmt.Errorf("read rules file: %w", err)
		}
		var rules struct {
			Repositories []Repository `yaml:"repositories"`
		}
		if err := yaml.Unmarshal(rdata, &rules); err != nil {
			return nil, fmt.Errorf("parse rules file %s: %w", cfg.Rules, err)
		}
		cfg.Repositories = rules.Repositories
	}
	applyDefaults(&cfg)
	if err := validate(&cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func applyDefaults(c *Config) {
	stateDir := expandHome("~/.local/state/agentd")
	if x := os.Getenv("XDG_STATE_HOME"); x != "" {
		stateDir = filepath.Join(x, "agentd")
	}
	if c.PollInterval == 0 {
		c.PollInterval = Duration(time.Minute)
	}
	if c.Concurrency == 0 {
		c.Concurrency = 3
	}
	if c.Database == "" {
		c.Database = filepath.Join(stateDir, "agentd.db")
	}
	if c.Socket == "" {
		c.Socket = filepath.Join(stateDir, "agentd.sock")
	}
	if c.TmuxSession == "" {
		c.TmuxSession = "agents"
	}
	if c.OnRestart == "" {
		c.OnRestart = "resume"
	}
	if c.Notify.Banner == "" {
		c.Notify.Banner = "decisions"
	}
	if c.Notify.BadgeFile == "" {
		c.Notify.BadgeFile = filepath.Join(stateDir, "badge")
	}
	if c.Escalation.RenotifyAfter == 0 {
		c.Escalation.RenotifyAfter = Duration(4 * time.Hour)
	}
	if c.Escalation.ParkAfter == 0 {
		c.Escalation.ParkAfter = Duration(24 * time.Hour)
	}
	for i := range c.Repositories {
		c.Repositories[i].Local = expandHome(c.Repositories[i].Local)
	}
	if c.OpencodeBin == "" {
		c.OpencodeBin = "opencode"
	}
	if c.DropinCommand == "" {
		c.DropinCommand = `nvim "+AgentFullscreen opencode"`
	}
	c.Database = expandHome(c.Database)
	c.Socket = expandHome(c.Socket)
	c.Notify.BadgeFile = expandHome(c.Notify.BadgeFile)
}

func validate(c *Config) error {
	switch c.Notify.Banner {
	case "decisions", "all", "none":
	default:
		return fmt.Errorf("notify.banner must be decisions|all|none, got %q", c.Notify.Banner)
	}
	switch c.OnRestart {
	case "resume", "fail":
	default:
		return fmt.Errorf("on_restart must be resume|fail, got %q", c.OnRestart)
	}
	if len(c.Repositories) == 0 {
		return errors.New("at least one repository is required")
	}
	for _, r := range c.Repositories {
		if r.Repo == "" {
			return errors.New("repository entry missing repo")
		}
		if len(r.Policies) == 0 {
			return fmt.Errorf("repository %s has no policies", r.Repo)
		}
	}
	return nil
}

func expandHome(p string) string {
	if strings.HasPrefix(p, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, p[2:])
		}
	}
	return p
}
