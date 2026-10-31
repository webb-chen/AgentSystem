package license

import (
	"errors"
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// MaxLicenseFileSize 是授权文件大小上限。正常 .lic 只有几百字节。
const MaxLicenseFileSize = 1 << 20

// Handler 处理授权相关的 HTTP 接口。
// 所有校验都在后端完成，前端只负责展示结果和上传文件。
type Handler struct {
	mgr *Manager
}

// NewHandler 创建授权 handler。
func NewHandler(mgr *Manager) *Handler {
	return &Handler{mgr: mgr}
}

// GetStatus 返回当前授权状态（HTTP 200，用 valid/code 表达失败原因）。
// 该接口在门禁放行清单内，授权失效时也能访问。
func (h *Handler) GetStatus(c *gin.Context) {
	st := h.mgr.Status()
	c.JSON(http.StatusOK, statusBody(st))
}

// GetMachineCode 返回本机统一机器码。
func (h *Handler) GetMachineCode(c *gin.Context) {
	code := GetMachineCode()
	c.JSON(http.StatusOK, gin.H{
		"code":         CodeOK,
		"valid":        true,
		"machine_code": code,
		"message":      "",
		"data":         gin.H{"machine_code": code},
	})
}

// Upload 接收上传的授权文件：先完整校验，通过后才备份 + 原子替换（不变量 6）。
// 校验失败返回 HTTP 200 + 统一状态码，前端直接展示原因。
func (h *Handler) Upload(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		respondFailure(c, CodeMalformed, "请选择要上传的授权文件（表单字段名应为 file）")
		return
	}
	if file.Size <= 0 {
		respondFailure(c, CodeMalformed, "授权文件为空，请重新选择")
		return
	}
	if file.Size > MaxLicenseFileSize {
		respondFailure(c, CodeMalformed, "授权文件过大，请确认上传的是 .lic 授权文件")
		return
	}

	src, err := file.Open()
	if err != nil {
		respondFailure(c, CodeMalformed, "读取上传文件失败: "+err.Error())
		return
	}
	defer src.Close()

	content, err := io.ReadAll(io.LimitReader(src, MaxLicenseFileSize+1))
	if err != nil || len(content) > MaxLicenseFileSize {
		respondFailure(c, CodeMalformed, "读取上传文件失败或文件过大")
		return
	}

	st, err := h.mgr.Install(content)
	if err != nil {
		code := CodeMalformed
		var le *LicenseError
		if errors.As(err, &le) {
			code = le.Code
		}
		respondFailure(c, code, "授权文件校验失败: "+err.Error())
		return
	}
	c.JSON(http.StatusOK, statusBody(st))
}

// Reload 强制重新读取授权文件。
func (h *Handler) Reload(c *gin.Context) {
	c.JSON(http.StatusOK, statusBody(h.mgr.Reload()))
}

// statusBody 输出统一状态响应（规范 §6）。顶层字段与 data 内容一致，
// 便于不同前端封装直接读取。
func statusBody(st Status) gin.H {
	payload := payloadBody(st.License)
	data := gin.H{
		"code":           st.Code,
		"valid":          st.Valid,
		"message":        st.Message,
		"in_grace":       st.InGrace,
		"remaining_days": st.RemainingDays,
		"checked_at":     st.CheckedAt.UTC().Format(time.RFC3339),
		"license":        payload,
	}
	body := gin.H{
		"data": data,
	}
	for k, v := range data {
		body[k] = v
	}
	return body
}

func respondFailure(c *gin.Context, code, message string) {
	now := time.Now().UTC().Format(time.RFC3339)
	body := gin.H{
		"code":           code,
		"valid":          false,
		"message":        message,
		"in_grace":       false,
		"remaining_days": 0,
		"checked_at":     now,
		"license":        nil,
		"data": gin.H{
			"code":           code,
			"valid":          false,
			"message":        message,
			"in_grace":       false,
			"remaining_days": 0,
			"checked_at":     now,
			"license":        nil,
		},
	}
	c.JSON(http.StatusOK, body)
}

func payloadBody(p *Payload) gin.H {
	if p == nil {
		return nil
	}
	var issuedAt interface{}
	if p.IssuedAt != nil {
		issuedAt = p.IssuedAt.UTC().Format(time.RFC3339)
	}
	var expireAt interface{}
	if p.ExpireTime != nil {
		expireAt = p.ExpireTime.UTC().Format(time.RFC3339)
	}
	return gin.H{
		"license_id":       p.LicenseID,
		"product":          p.Product,
		"product_display":  p.ProductDisplay,
		"customer":         p.Customer,
		"customer_contact": p.CustomerContact,
		"issued_at":        issuedAt,
		"expire_time":      expireAt,
		"grace_days":       p.GraceDays,
		"machine_code":     p.MachineCode,
		"instance_id":      p.InstanceID,
		"features":         p.Features,
		"permanent":        p.Permanent(),
	}
}
