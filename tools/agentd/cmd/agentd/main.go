package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var errNotImplemented = errors.New("not implemented yet")

func main() {
	if err := rootCmd().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "agentd:", err)
		os.Exit(1)
	}
}

func rootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:           "agentd",
		Short:         "Deterministic PR assistant daemon",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.PersistentFlags().String("config", defaultConfigPath(), "path to config file")

	for _, c := range []*cobra.Command{
		{Use: "serve", Short: "run the daemon"},
		{Use: "once", Short: "single poll pass over all repos, then exit"},
		{Use: "enqueue", Short: "process one PR immediately"},
		{Use: "resolve <job-id>", Short: "resolve a job's escalation (approve / reject)"},
		{Use: "status [job-id]", Short: "daemon and job status"},
	} {
		c.RunE = func(*cobra.Command, []string) error { return errNotImplemented }
		root.AddCommand(c)
	}
	return root
}

func defaultConfigPath() string {
	if x := os.Getenv("XDG_CONFIG_HOME"); x != "" {
		return x + "/agentd/config.yaml"
	}
	home, _ := os.UserHomeDir()
	return home + "/.config/agentd/config.yaml"
}
