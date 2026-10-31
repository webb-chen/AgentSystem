package fxapp

import (
	llmclient "github.com/webb-chen/AgentSystem/api/internal/modules/llm/client"
	videoservice "github.com/webb-chen/AgentSystem/api/internal/modules/video/service"
	"go.uber.org/fx"
	"gorm.io/gorm"
)

var videoRuntimeModule = fx.Module("videoruntime",
	fx.Provide(
		provideVideoRuntimeTaskPoller,
	),
)

func provideVideoRuntimeTaskPoller(db *gorm.DB, client llmclient.LLMClient) *videoservice.TaskPoller {
	return videoservice.NewTaskPoller(db, client)
}
