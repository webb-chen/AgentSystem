package shared

import (
	"github.com/webb-chen/AgentSystem/api/config"
	"github.com/webb-chen/AgentSystem/api/pkg/security"
)

// CryptoService defines the interface for encryption/decryption operations
type CryptoService interface {
	Encrypt(plaintext string) (string, error)
	Decrypt(ciphertext string) (string, error)
}

// DefaultCryptoService creates a CryptoService using AES-GCM encryption
// It reads the encryption key from the loaded .env configuration or uses a default.
func DefaultCryptoService() (CryptoService, error) {
	key := config.Current().LLM.EncryptionKey
	if key == "" {
		// Default 32-byte key for development (MUST be changed in production)
		key = "mingyingkeji-llm-default-key-321"
	}
	return security.NewAESGCMEncrypter(key)
}
