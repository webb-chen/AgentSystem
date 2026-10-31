package runner

import (
	"fmt"
	"strings"

	"github.com/webb-chen/AgentSystem-sandbox/internal/config"
)

func newBackendFromConfig(cfg config.Config) (backend, error) {
	switch strings.ToLower(strings.TrimSpace(cfg.RuntimeBackend)) {
	case "", "preview", "process", "preview-process":
		return newProcessBackend(cfg.DependencyRootFSDir), nil
	case "linux-secure":
		return newLinuxSecureBackend(cfg)
	default:
		return nil, fmt.Errorf("unsupported runtime backend: %s", cfg.RuntimeBackend)
	}
}
