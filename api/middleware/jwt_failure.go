package middleware

import (
	"errors"

	"github.com/gin-gonic/gin"
	jwtpkg "github.com/webb-chen/AgentSystem/api/pkg/jwt"
	"github.com/webb-chen/AgentSystem/api/pkg/response"
)

// A revocation-store outage denies this request but must not tell clients that
// their credentials are invalid. The existing 5xx contract preserves sessions.
func failJWTValidation(c *gin.Context, err error) {
	if errors.Is(err, jwtpkg.ErrRevocationStoreUnavailable) {
		response.Fail(c, response.ErrSystemError)
		return
	}
	response.Fail(c, response.ErrTokenInvalid)
}
