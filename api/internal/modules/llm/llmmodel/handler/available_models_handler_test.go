package handler

import (
	"testing"

	llmmodelservice "github.com/webb-chen/AgentSystem/api/internal/modules/llm/llmmodel/service"
)

func TestIsValidUseCaseAcceptsAgentRuntimeEligibility(t *testing.T) {
	if !isValidUseCase(llmmodelservice.AgentRuntimeUseCase) {
		t.Fatalf("isValidUseCase(%q) = false, want true", llmmodelservice.AgentRuntimeUseCase)
	}
}
