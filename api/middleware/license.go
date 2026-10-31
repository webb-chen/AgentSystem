package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"github.com/webb-chen/AgentSystem/api/internal/modules/license"
)

// AgentSystem 采用「受控前缀 + 强制恢复通路」模型（推荐模型）：
//   - 只拦截真正对外提供业务能力的路径前缀；
//   - 授权状态/机器码/上传/重载、登录鉴权、初始化、健康检查永远放行。
//
// 不采用「全部拦截 + 白名单放行」的原因：前端页面与静态资源由独立的 web
// 服务提供，后端白名单无法覆盖前端所有路由；而且一旦漏放行一条恢复接口，
// 客户到期后连登录和上传授权都做不到，系统会被彻底锁死。
var licenseGuardPrefixes = []string{
	"/console/api", // 控制台全部业务接口
	"/v1",          // OpenAI 兼容 LLM 网关（API Key 调用）
	"/files",       // 工具文件下载等业务资源
	"/api",         // 兼容旧前缀（如存在）
}

// licenseRecoveryPaths 是授权失效时仍必须放行的路径（恢复通路）。
var licenseRecoveryPaths = []string{
	// 授权管理自身：查状态、查机器码、上传、重载。
	"/console/api/license",

	// 登录与会话：到期后仍需登录进后台才能上传新授权。
	"/console/api/login",
	"/console/api/logout",
	"/console/api/refresh-token",
	"/console/api/email/check",
	"/console/api/register",
	"/console/api/login/by-email",
	"/console/api/phone/",
	"/console/api/sso/",
	"/console/api/forgot",
	"/console/api/activate",
	"/console/api/account/context",

	// 初始化与前端启动依赖（不含业务能力）。
	"/console/api/setup",
	"/console/api/system-features",

	// 健康检查与文档。
	"/ping",
	"/health",
	"/healthz",
	"/swagger",
}

// LicenseRequired 是全局授权拦截中间件。
// 授权无效时返回 403 + 统一状态码；授权模块初始化失败返回 503，
// 绝不静默放行（不变量 4）。
func LicenseRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path

		if !isLicenseGuardedPath(path) {
			c.Next()
			return
		}
		if isLicenseRecoveryPath(path) {
			c.Next()
			return
		}

		mgr := license.Global()
		if mgr == nil {
			abortLicense(c, http.StatusServiceUnavailable, license.CodeNotInit, "授权模块未初始化，服务暂不可用")
			return
		}

		st := mgr.Status()
		if st.Code == license.CodeNotInit || st.Code == license.CodeNoPublicKey {
			abortLicense(c, http.StatusServiceUnavailable, st.Code, st.Message)
			return
		}
		if !st.Valid {
			abortLicense(c, http.StatusForbidden, st.Code, st.Message)
			return
		}

		c.Set("license", st.License)
		c.Next()
	}
}

func isLicenseGuardedPath(path string) bool {
	for _, prefix := range licenseGuardPrefixes {
		if path == prefix || strings.HasPrefix(path, prefix+"/") {
			return true
		}
	}
	return false
}

func isLicenseRecoveryPath(path string) bool {
	for _, prefix := range licenseRecoveryPaths {
		if path == prefix || strings.HasPrefix(path, prefix+"/") ||
			(strings.HasSuffix(prefix, "/") && strings.HasPrefix(path, prefix)) {
			return true
		}
	}
	return false
}

// abortLicense 返回统一状态的授权错误。
// 响应体顶层包含 code 字符串（前端据此跳转授权页），同时保留 errorCode
// 数字字段供旧版前端兼容。
func abortLicense(c *gin.Context, status int, code, message string) {
	c.AbortWithStatusJSON(status, gin.H{
		"code":           code,
		"valid":          false,
		"message":        message,
		"in_grace":       false,
		"remaining_days": 0,
		"errorCode":      licenseErrorNumericCode(code),
	})
}

// licenseErrorNumericCode 把统一状态码映射到旧版数字错误码，仅用于兼容。
func licenseErrorNumericCode(code string) int {
	switch code {
	case license.CodeMissing:
		return 213300
	case license.CodeMalformed:
		return 213301
	case license.CodeBadSignature:
		return 213304
	case license.CodeMachineMismatch:
		return 213305
	case license.CodeExpired:
		return 213306
	case license.CodeClockRollback:
		return 213307
	case license.CodeDisabled:
		return 213308
	case license.CodeProductMismatch:
		return 213310
	case license.CodeNoPublicKey:
		return 213311
	case license.CodeNotInit:
		return 213312
	default:
		return 213306
	}
}
