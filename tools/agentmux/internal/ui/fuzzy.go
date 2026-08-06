package ui

import "strings"

// fuzzyMatch reports whether query is a case-insensitive subsequence of text.
// An empty query matches everything.
func fuzzyMatch(query, text string) bool {
	if query == "" {
		return true
	}
	q := strings.ToLower(query)
	t := strings.ToLower(text)
	qi := 0
	for ti := 0; ti < len(t) && qi < len(q); ti++ {
		if t[ti] == q[qi] {
			qi++
		}
	}
	return qi == len(q)
}

// fuzzyFilter returns the items whose key fuzzy-matches query, preserving order.
func fuzzyFilter[T any](query string, items []T, key func(T) string) []T {
	var out []T
	for _, it := range items {
		if fuzzyMatch(query, key(it)) {
			out = append(out, it)
		}
	}
	return out
}
