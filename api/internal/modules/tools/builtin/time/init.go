package time

import (
	"github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin"
)

func init() {
	// Register TimeProvider to builtin registry
	builtin.Register(NewTimeProvider())
}
