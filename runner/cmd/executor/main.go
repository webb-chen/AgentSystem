package main

import (
	"go.uber.org/fx"

	"github.com/webb-chen/AgentSystem/runner/internal/cache"
	"github.com/webb-chen/AgentSystem/runner/internal/config"
	"github.com/webb-chen/AgentSystem/runner/internal/dataplane"
	"github.com/webb-chen/AgentSystem/runner/internal/logger"
	"github.com/webb-chen/AgentSystem/runner/internal/manager"
	"github.com/webb-chen/AgentSystem/runner/internal/manager/signaturefx"
	"github.com/webb-chen/AgentSystem/runner/internal/registry"
	"github.com/webb-chen/AgentSystem/runner/internal/runtime/local"
	"github.com/webb-chen/AgentSystem/runner/internal/server"
	"github.com/webb-chen/AgentSystem/runner/internal/storagefx"
)

func main() {
	app := fx.New(
		config.Module,
		logger.Module,
		dataplane.Module,
		cache.Module,
		signaturefx.Module,
		registry.Module,
		local.Module,
		storagefx.Module,
		manager.Module,
		server.Module,
	)
	app.Run()
}
