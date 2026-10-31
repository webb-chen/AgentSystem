package handler

import (
	"github.com/gin-gonic/gin"
	"github.com/webb-chen/AgentSystem/api/middleware"
)

// RegisterTenantCredentialRoutes registers tenant routes for credential management
func RegisterTenantCredentialRoutes(r *gin.RouterGroup, handler *TenantCredentialHandler) {
	g := r.Group("/tenant/credentials")
	admin := g.Group("")
	admin.Use(middleware.EnterpriseAdminOrOwnerRequired())

	admin.POST("", handler.Create)
	g.GET("", handler.List)
	g.GET("/:id", handler.Get)
	admin.PUT("/:id", handler.Update)
	admin.DELETE("/:id", handler.Delete)
	admin.POST("/:id/test", handler.Test)
}
