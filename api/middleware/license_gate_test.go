package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/webb-chen/AgentSystem/api/internal/modules/license"
)

func TestLicenseGateBlocksBusinessButKeepsRecoveryPaths(t *testing.T) {
	gin.SetMode(gin.TestMode)

	old := license.Global()
	dir := t.TempDir()
	mgr, err := license.NewManager(license.Config{
		Enabled:      true,
		LicPath:      filepath.Join(dir, "license.lic"),
		PublicKeyPEM: license.PublicKeyPEM,
	})
	if err != nil {
		t.Fatalf("NewManager: %v", err)
	}
	license.SetGlobal(mgr)
	defer license.SetGlobal(old)

	engine := gin.New()
	engine.Use(LicenseRequired())
	engine.GET("/console/api/business", func(c *gin.Context) { c.Status(http.StatusOK) })
	engine.GET("/console/api/license/status", func(c *gin.Context) { c.Status(http.StatusOK) })
	engine.GET("/ping", func(c *gin.Context) { c.Status(http.StatusOK) })

	call := func(path string) (int, map[string]any) {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, path, nil)
		engine.ServeHTTP(rec, req)
		var body map[string]any
		if rec.Body.Len() > 0 {
			_ = json.Unmarshal(rec.Body.Bytes(), &body)
		}
		return rec.Code, body
	}

	if code, body := call("/console/api/business"); code != http.StatusForbidden {
		t.Fatalf("business should be blocked, got %d", code)
	} else if body["code"] != license.CodeMissing {
		t.Fatalf("expected license_missing, got %v", body["code"])
	}

	if code, _ := call("/console/api/license/status"); code != http.StatusOK {
		t.Fatalf("license status must stay reachable, got %d", code)
	}
	if code, _ := call("/ping"); code != http.StatusOK {
		t.Fatalf("health check must stay reachable, got %d", code)
	}
}
