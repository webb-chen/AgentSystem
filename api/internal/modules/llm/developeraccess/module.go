package developeraccess

import (
	apikeyrepo "github.com/webb-chen/AgentSystem/api/internal/modules/llm/apikey/repository"
	interfaces "github.com/webb-chen/AgentSystem/api/internal/modules/shared/interface"
	apptransport "github.com/webb-chen/AgentSystem/api/pkg/apperror/transport"
	"gorm.io/gorm"
)

type Module struct {
	Service *Service
	Handler *Handler
}

func NewModule(db *gorm.DB, keys apikeyrepo.APIKeyRepository, organizationService interfaces.OrganizationService, projector *apptransport.Projector) *Module {
	service := NewService(db, keys, organizationService)
	return &Module{Service: service, Handler: NewHandler(service, projector)}
}
