package apikey

import (
	"github.com/webb-chen/AgentSystem/api/internal/modules/llm/apikey/handler"
	"github.com/webb-chen/AgentSystem/api/internal/modules/llm/apikey/repository"
	"github.com/webb-chen/AgentSystem/api/internal/modules/llm/apikey/service"
	interfaces "github.com/webb-chen/AgentSystem/api/internal/modules/shared/interface"
	workspace_repo "github.com/webb-chen/AgentSystem/api/internal/modules/workspace/repository"
	"gorm.io/gorm"
)

// Module provides API Key management functionality
type Module struct {
	Repository repository.APIKeyRepository
	Service    service.APIKeyService
	Handler    *handler.APIKeyHandler
}

// NewModule creates a new API Key module
func NewModule(
	db *gorm.DB,
	tenantService interfaces.WorkspaceManagementService,
	accountService interfaces.AccountService,
	enterpriseService interfaces.OrganizationService,
) *Module {
	repo := repository.NewAPIKeyRepository(db)
	svc := service.NewAPIKeyService(db, repo, tenantService, enterpriseService)
	workspaceMemberRepo := workspace_repo.NewWorkspaceMemberRepository(db)
	h := handler.NewAPIKeyHandler(svc, workspaceMemberRepo, accountService, tenantService, enterpriseService)

	return &Module{
		Repository: repo,
		Service:    svc,
		Handler:    h,
	}
}
