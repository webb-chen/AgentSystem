package service

import (
	"context"
	"fmt"

	"github.com/redis/go-redis/v9"
	"github.com/webb-chen/AgentSystem/api/config"
	contentparsecap "github.com/webb-chen/AgentSystem/api/internal/capabilities/contentparse"
	systemvlm "github.com/webb-chen/AgentSystem/api/internal/capabilities/contentparse/adapters/system_vlm"
	contentparsemodule "github.com/webb-chen/AgentSystem/api/internal/modules/contentparse"
	graphflowrepo "github.com/webb-chen/AgentSystem/api/internal/modules/dataset/graphflow/repository"
	"github.com/webb-chen/AgentSystem/api/internal/modules/dataset/indexing"
	datasetmodel "github.com/webb-chen/AgentSystem/api/internal/modules/dataset/model"
	datasetrepository "github.com/webb-chen/AgentSystem/api/internal/modules/dataset/repository"
	llmclient "github.com/webb-chen/AgentSystem/api/internal/modules/llm/client"
	llmdefaultservice "github.com/webb-chen/AgentSystem/api/internal/modules/llm/defaultmodel/service"
	interfaces "github.com/webb-chen/AgentSystem/api/internal/modules/shared/interface"
	"github.com/webb-chen/AgentSystem/api/pkg/logger"
	"github.com/webb-chen/AgentSystem/api/pkg/queue"
	"github.com/webb-chen/AgentSystem/api/pkg/security"
	"github.com/webb-chen/AgentSystem/api/pkg/storage"
	"github.com/webb-chen/AgentSystem/api/pkg/vectordb"
	"gorm.io/gorm"
)

// DocumentIndexingService handles document vectorization and indexing
type DocumentIndexingService struct {
	indexingRunner *indexing.IndexingRunner
}

// NewDocumentIndexingService creates a new document indexing service.
// The llmClient should be obtained from the DI container (ServiceContainer.GetLLMClient()).
func NewDocumentIndexingService(
	documentRepo datasetrepository.DocumentRepository,
	datasetRepo datasetrepository.DatasetRepository,
	fileService interfaces.FileService,
	storage storage.Storage,
	cfg *config.Config,
	db *gorm.DB,
	_ *redis.Client,
	_ *security.Encrypter,
	llmClient llmclient.LLMClient,
	defaultModelService llmdefaultservice.DefaultModelService,
	taskManager *queue.TaskManager,
) *DocumentIndexingService {
	// Initialize vector database client based on configuration
	vectorDBClient, err := vectordb.NewVectorDB(&cfg.VectorStore)
	if err != nil {
		logger.Error("Failed to initialize vector database, using mock implementation", err)
		vectorDBClient = &vectordb.MockVectorDB{}
	}

	// Initialize GraphFlow task repository
	graphFlowTaskRepo := graphflowrepo.NewGraphFlowTaskRepository(db)

	// Initialize indexing runner with taskManager for GraphFlow task enqueueing
	indexingRunner := indexing.NewIndexingRunner(storage, documentRepo, datasetRepo, fileService, nil, vectorDBClient, defaultModelService, llmClient, graphFlowTaskRepo, taskManager)
	shadowDatasetIndexingEnabled := cfg != nil && cfg.ContentParse.ShadowDatasetIndexingEnabled
	contentParseCapability := contentparsecap.NewModule(
		contentparsecap.WithAdapters(systemvlm.NewAdapter(llmClient, defaultModelService)),
		contentparsecap.WithProviderOverrides(contentparsecap.SystemVLMProviderConfig(llmClient != nil && defaultModelService != nil)),
	)
	contentParsePlatform := contentparsemodule.NewModule(
		db,
		contentparsemodule.WithSystemVisionModel(llmClient, defaultModelService),
	)
	indexingRunner.SetContentParseShadow(
		contentParseCapability.Service,
		contentParseCapability.Orchestrator,
		contentParseCapability.Planner,
		contentParseCapability.ChunkMapper,
		contentParseCapability.ChunkPlanner,
		contentParseCapability.Catalog,
		contentParsePlatform.RunQueryService,
		contentParsePlatform.ArtifactService,
		contentParsePlatform.ChunkArtifactService,
		shadowDatasetIndexingEnabled,
	)

	return &DocumentIndexingService{
		indexingRunner: indexingRunner,
	}
}

// Run executes the document indexing process
func (s *DocumentIndexingService) Run(ctx context.Context, document *datasetmodel.Document) error {
	return s.indexingRunner.Run(ctx, document)
}

func (s *DocumentIndexingService) StartContentParseShadowSampling(ctx context.Context, datasetID, organizationID string, limit int, documentIDs []string) (*indexing.ContentParseShadowSamplingResult, error) {
	if s == nil || s.indexingRunner == nil {
		return nil, fmt.Errorf("document indexing service is not configured")
	}
	return s.indexingRunner.StartContentParseShadowSampling(ctx, datasetID, organizationID, limit, documentIDs)
}
