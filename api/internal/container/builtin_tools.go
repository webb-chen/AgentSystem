package container

import (
	"github.com/webb-chen/AgentSystem/api/internal/modules/tools"
	"github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin"

	// Import builtin tools to trigger init() registration
	_ "github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin/architecturediagram"
	_ "github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin/calculator"
	_ "github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin/chartgenerator"
	_ "github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin/consolenavigation"
	_ "github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin/filegenerator"
	_ "github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin/intentrouter"
	_ "github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin/sensitiveredaction"
	_ "github.com/webb-chen/AgentSystem/api/internal/modules/tools/builtin/time"
)

// getBuiltinToolProviders returns all registered builtin tool providers
// This function is called during ToolManager initialization
func getBuiltinToolProviders() []tools.ToolProvider {
	return builtin.GetAllProviders()
}
