package storagefx

import (
	"go.uber.org/fx"

	"github.com/webb-chen/AgentSystem/runner/internal/config"
	"github.com/webb-chen/AgentSystem/runner/internal/storage"
	localstore "github.com/webb-chen/AgentSystem/runner/internal/storage/local"
)

// Module wires the storage implementation into Fx.
var Module = fx.Provide(
	func(cfg *config.Config) storage.Store {
		return localstore.NewStore(cfg.WorkspacePath, cfg.PackageCachePath)
	},
)
