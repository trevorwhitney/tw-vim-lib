// tools/agentmux/internal/tree/tree.go
package tree

import (
	"sort"
	"strings"

	"github.com/trevorwhitney/tw-vim-lib/agentmux/internal/store"
)

// Kind identifies a node's level in the project → worktree → agent tree.
type Kind int

// Node kinds, one per level of the project → worktree → agent tree.
const (
	KindProject Kind = iota
	KindWorktree
	KindAgent
)

// Node is a single renderable row. Project/worktree nodes carry rollups; agent
// nodes carry their Record.
type Node struct {
	Kind     Kind
	Depth    int
	Project  string
	Worktree string
	Path     string // worktree nodes: worktree root path (for jump)
	Handle   string // worktree nodes: workmux handle (for workmux-open fallback)
	IsMain   bool
	Validity string // worktree nodes: "valid" | "gone"

	// Worktree rollup.
	Working        int
	Waiting        int
	Saved          int
	NeedsAttention bool

	Record store.Record // agent nodes only
}

type worktreeGroup struct {
	name           string
	path           string
	handle         string
	isMain         bool
	validity       string
	records        []store.Record
	needsAttention bool
	live           bool
	maxAge         int64
	working        int
	waiting        int
	saved          int
}

// Build groups records into an ordered, flattenable node slice.
func Build(recs []store.Record, now int64, statPath func(string) bool) []Node {
	byProject := map[string]map[string]*worktreeGroup{}
	pathOf := map[string]map[string]string{}

	for _, r := range recs {
		if byProject[r.Project] == nil {
			byProject[r.Project] = map[string]*worktreeGroup{}
			pathOf[r.Project] = map[string]string{}
		}
		g := byProject[r.Project][r.Worktree]
		if g == nil {
			g = &worktreeGroup{
				name:   r.Worktree,
				path:   r.Path,
				handle: r.Handle,
				isMain: r.Project == r.Worktree,
			}
			byProject[r.Project][r.Worktree] = g
		}
		g.records = append(g.records, r)
		pathOf[r.Project][r.Worktree] = r.Path

		// Disjoint classification: every agent falls into exactly one bucket.
		// waiting takes precedence (it always needs attention); otherwise a
		// live agent is "working" and a non-live one is "saved".
		switch {
		case r.Status == "waiting":
			g.waiting++
		case store.Liveness(r, now) == "live":
			g.working++
			g.live = true
		default:
			g.saved++
		}
		// A waiting agent takes the waiting branch above without setting live, so
		// mark the group live here too: a worktree with a live-but-waiting agent
		// must still sort among the live group.
		if store.Liveness(r, now) == "live" {
			g.live = true
		}
		if age := store.AgeSecs(r, now); age > g.maxAge {
			g.maxAge = age
		}
		if store.NeedsAttention(r, now) {
			g.needsAttention = true
		}
	}

	projects := make([]string, 0, len(byProject))
	for p := range byProject {
		projects = append(projects, p)
	}
	sort.Strings(projects)

	var nodes []Node
	for _, p := range projects {
		nodes = append(nodes, Node{Kind: KindProject, Depth: 0, Project: p})

		groups := make([]*worktreeGroup, 0, len(byProject[p]))
		for _, g := range byProject[p] {
			g.validity = store.Validity(pathOf[p][g.name], statPath)
			groups = append(groups, g)
		}
		sort.SliceStable(groups, func(i, j int) bool {
			a, b := groups[i], groups[j]
			if a.isMain != b.isMain {
				return a.isMain
			}
			if a.needsAttention != b.needsAttention {
				return a.needsAttention
			}
			if a.live != b.live {
				return a.live
			}
			if a.live && b.live {
				return a.name < b.name
			}
			if a.maxAge != b.maxAge {
				return a.maxAge > b.maxAge
			}
			return a.name < b.name
		})

		for _, g := range groups {
			nodes = append(nodes, Node{
				Kind:           KindWorktree,
				Depth:          1,
				Project:        p,
				Worktree:       g.name,
				Path:           g.path,
				Handle:         g.handle,
				IsMain:         g.isMain,
				Validity:       g.validity,
				Working:        g.working,
				Waiting:        g.waiting,
				Saved:          g.saved,
				NeedsAttention: g.needsAttention,
			})
			agents := append([]store.Record(nil), g.records...)
			sort.SliceStable(agents, func(i, j int) bool {
				if agents[i].Mode != agents[j].Mode {
					return agents[i].Mode < agents[j].Mode
				}
				return agents[i].Idx < agents[j].Idx
			})
			for _, a := range agents {
				nodes = append(nodes, Node{
					Kind:     KindAgent,
					Depth:    2,
					Project:  p,
					Worktree: g.name,
					Record:   a,
				})
			}
		}
	}
	return nodes
}

// ProjectKey returns the collapse-set key for a project node.
func ProjectKey(project string) string { return "p:" + project }

// WorktreeKey returns the collapse-set key for a worktree node.
func WorktreeKey(p, w string) string { return "w:" + p + "/" + w }

// Flatten returns only the visible nodes given the collapsed key set.
func Flatten(nodes []Node, collapsed map[string]bool) []Node {
	var out []Node
	for _, n := range nodes {
		switch n.Kind {
		case KindProject:
			out = append(out, n)
		case KindWorktree:
			if !collapsed[ProjectKey(n.Project)] {
				out = append(out, n)
			}
		case KindAgent:
			if collapsed[ProjectKey(n.Project)] {
				continue
			}
			if collapsed[WorktreeKey(n.Project, n.Worktree)] {
				continue
			}
			out = append(out, n)
		}
	}
	return out
}

// Filter keeps only worktrees (and their project project headers) matching
// query case-insensitively on project/worktree name or any child agent's
// description or mode. Empty query returns nodes unchanged.
func Filter(nodes []Node, query string) []Node {
	if query == "" {
		return nodes
	}
	q := strings.ToLower(query)

	// Collect matching worktree keys.
	match := map[string]bool{}
	for _, n := range nodes {
		switch n.Kind {
		case KindWorktree:
			if strings.Contains(strings.ToLower(n.Project), q) ||
				strings.Contains(strings.ToLower(n.Worktree), q) {
				match[WorktreeKey(n.Project, n.Worktree)] = true
			}
		case KindAgent:
			r := n.Record
			if strings.Contains(strings.ToLower(r.Description), q) ||
				strings.Contains(strings.ToLower(r.Mode), q) {
				match[WorktreeKey(n.Project, n.Worktree)] = true
			}
		}
	}

	// Which projects have at least one matching worktree.
	projectHasMatch := map[string]bool{}
	for _, n := range nodes {
		if n.Kind == KindWorktree && match[WorktreeKey(n.Project, n.Worktree)] {
			projectHasMatch[n.Project] = true
		}
	}

	var out []Node
	for _, n := range nodes {
		switch n.Kind {
		case KindProject:
			if projectHasMatch[n.Project] {
				out = append(out, n)
			}
		case KindWorktree, KindAgent:
			if match[WorktreeKey(n.Project, n.Worktree)] {
				out = append(out, n)
			}
		}
	}
	return out
}
