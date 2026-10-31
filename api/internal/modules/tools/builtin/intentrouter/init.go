package intentrouter

import "github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin"

func init() {
	builtin.Register(NewProvider())
}
