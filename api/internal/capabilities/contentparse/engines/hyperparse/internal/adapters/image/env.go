package image

import (
	"github.com/webb-chen/AgentSystem/api/internal/capabilities/contentparse/envconfig"
)

func firstNonEmptyEnv(keys ...string) string {
	for _, key := range keys {
		if v := envconfig.String(key); v != "" {
			return v
		}
	}
	return ""
}
