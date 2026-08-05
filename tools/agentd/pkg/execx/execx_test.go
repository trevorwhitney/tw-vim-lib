package execx

import (
	"context"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRunRespectsDirAndEnv(t *testing.T) {
	dir := t.TempDir()
	out, err := Run(context.Background(), Options{Dir: dir, Env: map[string]string{"AGENTD_TEST_VAR": "hello"}},
		"sh", "-c", "pwd && printf '%s' \"$AGENTD_TEST_VAR\"")
	require.NoError(t, err)
	lines := strings.Split(strings.TrimSpace(out), "\n")
	require.Len(t, lines, 2)
	got, want := lines[0], dir
	gotEval, _ := filepath.EvalSymlinks(got)
	wantEval, _ := filepath.EvalSymlinks(want)
	require.Equal(t, wantEval, gotEval)
	require.Equal(t, "hello", lines[1])
}

func TestRunInheritsParentEnv(t *testing.T) {
	t.Setenv("AGENTD_PARENT_VAR", "inherited")
	out, err := Run(context.Background(), Options{}, "sh", "-c", "printf '%s' \"$AGENTD_PARENT_VAR\"")
	require.NoError(t, err)
	require.Equal(t, "inherited", out)
}

func TestRunErrorCarriesOutput(t *testing.T) {
	_, err := Run(context.Background(), Options{}, "sh", "-c", "echo boom >&2; exit 3")
	require.Error(t, err)
	require.Contains(t, err.Error(), "boom")
}

func TestRunOverridesAndUnsetsEnv(t *testing.T) {
	t.Setenv("AGENTD_OVERRIDE_VAR", "parent")
	t.Setenv("AGENTD_UNSET_VAR", "parent")
	out, err := Run(context.Background(),
		Options{Env: map[string]string{"AGENTD_OVERRIDE_VAR": "child", "AGENTD_UNSET_VAR": ""}},
		"sh", "-c", `printf '%s|%s' "$AGENTD_OVERRIDE_VAR" "${AGENTD_UNSET_VAR-GONE}"`)
	require.NoError(t, err)
	require.Equal(t, "child|GONE", out)
}
