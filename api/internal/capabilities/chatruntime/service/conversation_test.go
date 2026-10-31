package service

import (
	"testing"

	runtimemodel "github.com/webb-chen/AgentSystem/api/internal/capabilities/chatruntime/model"
)

func TestNormalizeConversationSourcePreservesExternalAPI(t *testing.T) {
	if got := normalizeConversationSource(runtimemodel.ConversationSourceExternalAPI); got != runtimemodel.ConversationSourceExternalAPI {
		t.Fatalf("normalizeConversationSource(external-api) = %q, want %q", got, runtimemodel.ConversationSourceExternalAPI)
	}
}
