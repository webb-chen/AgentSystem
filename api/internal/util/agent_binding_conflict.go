package util

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/webb-chen/AgentSystem/api/internal/capabilities/agentbindings"
	"github.com/webb-chen/AgentSystem/api/pkg/response"
)

// WriteAgentBindingConflict writes the shared resource-mutation conflict response.
// It returns false when err is not an Agent binding conflict.
func WriteAgentBindingConflict(c *gin.Context, err error) bool {
	var conflict *agentbindings.ConflictError
	if !errors.As(err, &conflict) || conflict == nil {
		return false
	}
	c.JSON(http.StatusConflict, response.Response{
		Code:    agentbindings.ConflictCodeResourceBound,
		Message: conflict.Error(),
		Data:    conflict.Impact,
	})
	return true
}
