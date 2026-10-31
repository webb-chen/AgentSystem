package v1

import (
	"github.com/gin-gonic/gin"

	licensemodule "github.com/webb-chen/AgentSystem/api/internal/modules/license"
)

// RegisterLicenseRoutes 注册统一授权平台（ULP）相关路由。
// 这些路径在 LicenseRequired 中间件的恢复通路清单内，授权失效时仍可访问，
// 保证客户能查看状态并上传新的授权文件自救。
func RegisterLicenseRoutes(router *gin.RouterGroup) {
	mgr := licensemodule.Global()
	handler := licensemodule.NewHandler(mgr)

	group := router.Group("/license")
	{
		group.GET("/status", handler.GetStatus)            // 查询授权状态
		group.GET("/machine-code", handler.GetMachineCode) // 查询本机机器码
		group.POST("/upload", handler.Upload)              // 上传新授权文件（先校验后落盘）
		group.POST("/reload", handler.Reload)              // 强制重新读取授权文件
	}
}
