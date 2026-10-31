package fxapp

import (
	"github.com/redis/go-redis/v9"
	"github.com/webb-chen/AgentSystem/api/config"
	"github.com/webb-chen/AgentSystem/api/internal/container"
	"github.com/webb-chen/AgentSystem/api/internal/infra/platform"
	workflowtest "github.com/webb-chen/AgentSystem/api/internal/modules/app/workflowtest"
	"github.com/webb-chen/AgentSystem/api/internal/modules/dataset/graphflow"
	llmclient "github.com/webb-chen/AgentSystem/api/internal/modules/llm/client"
	system_service "github.com/webb-chen/AgentSystem/api/internal/modules/system/service"
	workspacerepo "github.com/webb-chen/AgentSystem/api/internal/modules/workspace/repository"
	"github.com/webb-chen/AgentSystem/api/internal/util"
	"github.com/webb-chen/AgentSystem/api/pkg/email"
	"github.com/webb-chen/AgentSystem/api/pkg/jwt"
	"github.com/webb-chen/AgentSystem/api/pkg/queue"
	pkgscheduler "github.com/webb-chen/AgentSystem/api/pkg/scheduler"
	"go.uber.org/fx"
	"gorm.io/gorm"
)

type legacyGlobalsReady struct{}

var legacyGlobalsModule = fx.Module("legacyglobals",
	fx.Provide(
		provideLegacyGlobals,
	),
)

var legacyContainerModule = fx.Module("legacycontainer",
	fx.Provide(
		provideServiceContainer,
		provideBootstrapService,
	),
)

var taskRuntimeModule = fx.Module("taskruntime",
	fx.Provide(
		provideTaskManager,
		provideTaskHandlerRegistry,
		provideWorkflowTestService,
		provideLLMClient,
	),
)

var schedulerModule = fx.Module("scheduler",
	fx.Provide(
		provideScheduler,
	),
)

var graphFlowModule = fx.Module("graphflow",
	fx.Provide(
		provideGraphFlowService,
	),
)

func provideLegacyGlobals(cfg *config.Config) legacyGlobalsReady {
	// These package-level initializers still back legacy code paths that are
	// not constructor-injected yet.
	jwt.Init(cfg)
	email.Init(cfg)
	return legacyGlobalsReady{}
}

// provideServiceContainer bridges the legacy service container into the Fx graph.
// The Redis dependency is intentionally requested to force infra initialization
// to complete before the legacy boot side effects run.
func provideServiceContainer(
	db *gorm.DB,
	cfg *config.Config,
	_ *redis.Client,
	_ legacyGlobalsReady,
	platformContainer *platform.Container,
) (*container.ServiceContainer, error) {
	tokenManager := util.NewTokenManager()

	workspaceRepo := workspacerepo.NewWorkspaceRepository(db)
	workspaceMemberRepo := workspacerepo.NewWorkspaceMemberRepository(db)

	serviceContainer := container.NewServiceContainer(
		db,
		tokenManager,
		cfg,
		workspaceRepo,
		workspaceMemberRepo,
		platformContainer,
	)
	serviceContainer.InitializeDependencies()

	return serviceContainer, nil
}

// Expose concrete runtime dependencies instead of making downstream code pull
// everything from the legacy ServiceContainer directly.
func provideTaskManager(serviceContainer *container.ServiceContainer) *queue.TaskManager {
	return serviceContainer.GetTaskManager()
}

func provideTaskHandlerRegistry(serviceContainer *container.ServiceContainer) *container.TaskHandlerRegistrar {
	return serviceContainer.GetTaskHandlerRegistry()
}

func provideWorkflowTestService(serviceContainer *container.ServiceContainer) *workflowtest.Service {
	return serviceContainer.GetWorkflowTestService()
}

func provideLLMClient(serviceContainer *container.ServiceContainer) llmclient.LLMClient {
	return serviceContainer.GetLLMClient()
}

func provideScheduler(serviceContainer *container.ServiceContainer) *pkgscheduler.Scheduler {
	return serviceContainer.GetScheduler()
}

func provideGraphFlowService(serviceContainer *container.ServiceContainer) *graphflow.Service {
	return serviceContainer.GetGraphFlowService()
}

func provideBootstrapService(serviceContainer *container.ServiceContainer) *system_service.BootstrapService {
	return serviceContainer.GetBootstrapService()
}
