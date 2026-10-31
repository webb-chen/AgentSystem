//go:build !linux

package runner

import (
	"fmt"

	"github.com/webb-chen/AgentSystem-sandbox/internal/config"
)

func newLinuxSecureBackend(cfg config.Config) (backend, error) {
	return nil, fmt.Errorf("linux-secure backend is only available on linux (requested rootfs=%q)", cfg.SecureRootFS)
}
