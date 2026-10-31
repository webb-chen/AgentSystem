package gateway

import (
	"context"
	"net/http"
	"strings"
)

const (
	headerMINGYINGKEJIBillingOrganizationID = "X-MINGYINGKEJI-Billing-Organization-ID"
	headerMINGYINGKEJIRequestID             = "X-MINGYINGKEJI-Request-ID"
	headerMINGYINGKEJIAttemptID             = "X-MINGYINGKEJI-Attempt-ID"
	headerMINGYINGKEJIDeductionID           = "X-MINGYINGKEJI-Deduction-ID"
	headerMINGYINGKEJIAPIKeyID              = "X-MINGYINGKEJI-API-Key-ID"
	headerMINGYINGKEJIWorkspaceID           = "X-MINGYINGKEJI-Workspace-ID"
	headerMINGYINGKEJIAppID                 = "X-MINGYINGKEJI-App-ID"
	headerMINGYINGKEJIAppType               = "X-MINGYINGKEJI-App-Type"
	headerMINGYINGKEJIModelName             = "X-MINGYINGKEJI-Model-Name"
	headerMINGYINGKEJIProviderName          = "X-MINGYINGKEJI-Provider-Name"
	headerMINGYINGKEJIIsStreaming           = "X-MINGYINGKEJI-Is-Streaming"
)

type platformProxyContextKey struct{}

type platformProxyMetadata struct {
	BillingOrganizationID string
	RequestID             string
	AttemptID             string
	DeductionID           string
	APIKeyID              string
	WorkspaceID           string
	AppID                 string
	AppType               string
	ModelName             string
	ProviderName          string
	IsStreaming           bool
}

func withPlatformProxyMetadata(ctx context.Context, bc *BillingContext) context.Context {
	if ctx == nil || bc == nil {
		return ctx
	}
	lane, err := normalizeBillingContextUsageLane(bc)
	if err != nil || lane != UsageBillingLanePlatform {
		return ctx
	}

	meta := platformProxyMetadata{
		BillingOrganizationID: strings.TrimSpace(bc.OrganizationID),
		RequestID:             strings.TrimSpace(bc.RequestID),
		AttemptID:             strings.TrimSpace(bc.AttemptID),
		DeductionID:           strings.TrimSpace(bc.DeductionID),
		APIKeyID:              strings.TrimSpace(bc.APIKeyID),
		WorkspaceID:           strings.TrimSpace(bc.WorkspaceID),
		ModelName:             strings.TrimSpace(bc.ModelName),
		ProviderName:          strings.TrimSpace(bc.ProviderName),
		IsStreaming:           bc.IsStreaming,
	}
	if bc.AppID != nil {
		meta.AppID = bc.AppID.String()
	}
	if bc.AppType != nil {
		meta.AppType = strings.TrimSpace(*bc.AppType)
	}

	return context.WithValue(ctx, platformProxyContextKey{}, meta)
}

func applyPlatformProxyHeaders(req *http.Request) {
	if req == nil {
		return
	}
	meta, ok := req.Context().Value(platformProxyContextKey{}).(platformProxyMetadata)
	if !ok {
		return
	}
	setHeaderIfNotEmpty(req, headerMINGYINGKEJIBillingOrganizationID, meta.BillingOrganizationID)
	setHeaderIfNotEmpty(req, headerMINGYINGKEJIRequestID, meta.RequestID)
	setHeaderIfNotEmpty(req, headerMINGYINGKEJIAttemptID, meta.AttemptID)
	setHeaderIfNotEmpty(req, headerMINGYINGKEJIDeductionID, meta.DeductionID)
	setHeaderIfNotEmpty(req, headerMINGYINGKEJIAPIKeyID, meta.APIKeyID)
	setHeaderIfNotEmpty(req, headerMINGYINGKEJIWorkspaceID, meta.WorkspaceID)
	setHeaderIfNotEmpty(req, headerMINGYINGKEJIAppID, meta.AppID)
	setHeaderIfNotEmpty(req, headerMINGYINGKEJIAppType, meta.AppType)
	setHeaderIfNotEmpty(req, headerMINGYINGKEJIModelName, meta.ModelName)
	setHeaderIfNotEmpty(req, headerMINGYINGKEJIProviderName, meta.ProviderName)
	if meta.IsStreaming {
		req.Header.Set(headerMINGYINGKEJIIsStreaming, "true")
	}
}

func setHeaderIfNotEmpty(req *http.Request, key string, value string) {
	value = strings.TrimSpace(value)
	if value == "" {
		return
	}
	req.Header.Set(key, value)
}
