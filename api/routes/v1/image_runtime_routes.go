package v1

import (
	"github.com/gin-gonic/gin"
	chatruntime "github.com/webb-chen/AgentSystem/api/internal/capabilities/chatruntime/service"
	imagemodule "github.com/webb-chen/AgentSystem/api/internal/modules/image"
	channelsvc "github.com/webb-chen/AgentSystem/api/internal/modules/llm/channel/service"
	llmclient "github.com/webb-chen/AgentSystem/api/internal/modules/llm/client"
	llmmodelsvc "github.com/webb-chen/AgentSystem/api/internal/modules/llm/llmmodel/service"
	interfaces "github.com/webb-chen/AgentSystem/api/internal/modules/shared/interface"
	"github.com/webb-chen/AgentSystem/api/middleware"
	appcatalog "github.com/webb-chen/AgentSystem/api/pkg/apperror/catalog"
	apptransport "github.com/webb-chen/AgentSystem/api/pkg/apperror/transport"
	"github.com/webb-chen/AgentSystem/api/pkg/logger"
	"gorm.io/gorm"
)

type ImageRuntimeRouteDeps struct {
	DB                      *gorm.DB
	AvailableModels         llmmodelsvc.AvailableModelsService
	Routes                  channelsvc.ChannelService
	LLMClient               llmclient.LLMClient
	ChatService             chatruntime.Service
	AccountService          interfaces.AccountService
	FileService             interfaces.FileService
	ApplicationErrorCatalog *appcatalog.Catalog
}

func RegisterImageRuntimeRoutes(router *gin.RouterGroup, deps ImageRuntimeRouteDeps) {
	if deps.AvailableModels == nil {
		panic("image runtime routes require available models service")
	}
	if deps.Routes == nil {
		panic("image runtime routes require channel route service")
	}
	if deps.LLMClient == nil {
		panic("image runtime routes require llm client")
	}
	if deps.ChatService == nil {
		panic("image runtime routes require chat service")
	}
	if deps.AccountService == nil {
		panic("image runtime routes require account service")
	}
	if deps.FileService == nil {
		panic("image runtime routes require file service")
	}
	errorProjector, err := apptransport.NewProjector(deps.ApplicationErrorCatalog)
	if err != nil {
		panic("image runtime routes require application error catalog")
	}
	module := imagemodule.NewModule(deps.DB, deps.AvailableModels, deps.Routes, deps.LLMClient, deps.ChatService, errorProjector, deps.FileService)
	group := router.Group("")
	group.Use(middleware.SetupRequired())
	group.Use(middleware.JWTWithOrganizationAndService(deps.AccountService))
	module.RegisterRoutes(group)
	logger.Info("Image runtime routes registered", "path", "/console/api/image-runtime/*")
}
