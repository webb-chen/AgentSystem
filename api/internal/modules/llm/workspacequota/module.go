package workspacequota

import (
	"github.com/webb-chen/AgentSystem/api/internal/modules/llm/workspacequota/handler"
	"github.com/webb-chen/AgentSystem/api/internal/modules/llm/workspacequota/service"
	interfaces "github.com/webb-chen/AgentSystem/api/internal/modules/shared/interface"
	"gorm.io/gorm"
)

// Module provides workspace quota management APIs for LLM billing.
type Module struct {
	Service service.WorkspaceQuotaService
	Handler *handler.WorkspaceQuotaHandler
}

func NewModule(db *gorm.DB, organizationService interfaces.OrganizationService) *Module {
	svc := service.NewWorkspaceQuotaService(db)
	h := handler.NewWorkspaceQuotaHandler(svc, organizationService)
	return &Module{
		Service: svc,
		Handler: h,
	}
}
