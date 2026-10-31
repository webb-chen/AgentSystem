package fxapp

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/getsentry/sentry-go"
	sentrygin "github.com/getsentry/sentry-go/gin"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/webb-chen/AgentSystem/api/config"
	grpcinfra "github.com/webb-chen/AgentSystem/api/internal/infra/grpc"
	"github.com/webb-chen/AgentSystem/api/internal/infra/platform"
	licensemodule "github.com/webb-chen/AgentSystem/api/internal/modules/license"
	"github.com/webb-chen/AgentSystem/api/internal/observability"
	"github.com/webb-chen/AgentSystem/api/middleware"
	apptransport "github.com/webb-chen/AgentSystem/api/pkg/apperror/transport"
	"github.com/webb-chen/AgentSystem/api/pkg/database"
	"github.com/webb-chen/AgentSystem/api/pkg/logger"
	redispkg "github.com/webb-chen/AgentSystem/api/pkg/redis"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.uber.org/fx"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

const corsAllowOriginsEnvKey = "WEB_API_CORS_ALLOW_ORIGINS"

var corsAllowHeaders = []string{
	"Origin",
	"Content-Type",
	"Accept",
	"Authorization",
	"X-Requested-With",
	"X-Request-ID",
	"X-User-Account-Id",
	"Cache-Control",
	"Connection",
}

var defaultCORSAllowOrigins = []string{
	"http://localhost:2679",
	"http://localhost:3000",
	"http://localhost:3001",
	"http://localhost:3002",
}

type ServerAddresses struct {
	HTTP        string
	GRPC        int
	GRPCEnabled bool
}

type SentryResource struct {
	Enabled bool
}

type listenerResult struct {
	fx.Out

	HTTP net.Listener `name:"http_listener"`
	GRPC net.Listener `name:"grpc_listener"`
}

var infraModule = fx.Module("infra",
	fx.Provide(
		provideServerAddresses,
		provideSentryResource,
		provideOpenTelemetryResource,
		provideMINGYINGKEJIReporter,
		provideDatabase,
		provideRedis,
		providePlatformContainer,
		provideListeners,
		provideGinEngine,
		provideHTTPServer,
		provideGRPCServer,
	),
	fx.Invoke(registerInfraLifecycle),
)

func provideServerAddresses(cfg *config.Config) ServerAddresses {
	return ServerAddresses{
		HTTP:        fmt.Sprintf(":%d", cfg.Server.Port),
		GRPC:        cfg.Server.GRPCPort,
		GRPCEnabled: cfg.Server.GRPCEnabled,
	}
}

func provideSentryResource(cfg *config.Config, log *zap.Logger) *SentryResource {
	sentryDSN := strings.TrimSpace(cfg.Sentry.DSN)
	if !cfg.Observability.ReporterEnabled("sentry", sentryDSN != "") {
		log.Info("Sentry reporter disabled or not configured")
		return &SentryResource{}
	}

	err := sentry.Init(sentry.ClientOptions{
		Dsn:              sentryDSN,
		Environment:      cfg.Sentry.Environment,
		Release:          cfg.Sentry.Release,
		EnableTracing:    true,
		TracesSampleRate: normalizedSentryTraceSampleRate(cfg.Sentry.TraceSampleRate),
		BeforeSend: func(event *sentry.Event, hint *sentry.EventHint) *sentry.Event {
			if hint != nil && hint.Context != nil {
				req, ok := hint.Context.Value(sentry.RequestContextKey).(*http.Request)
				if ok {
					event.Request = sentry.NewRequest(req)
				}
			}
			return observability.SanitizeSentryEvent(event)
		},
	})
	if err != nil {
		log.Warn("Sentry initialization failed", zap.Error(err))
		return &SentryResource{}
	}

	log.Info("Sentry initialized successfully")
	return &SentryResource{Enabled: true}
}

func normalizedSentryTraceSampleRate(sampleRate float64) float64 {
	if sampleRate < 0 {
		return 0
	}
	if sampleRate > 1 {
		return 1
	}
	return sampleRate
}

func provideMINGYINGKEJIReporter(sentryResource *SentryResource, otelResource *OpenTelemetryResource, log *zap.Logger) *observability.MINGYINGKEJIReporter {
	reporters := make([]observability.Reporter, 0, 2)
	if sentryResource != nil && sentryResource.Enabled {
		reporters = append(reporters, observability.NewSentryReporter())
	}
	if otelResource != nil && otelResource.Enabled {
		reporters = append(reporters, observability.NewOTelReporter())
	}

	reporter := observability.NewMINGYINGKEJIReporter(reporters...)
	observability.SetDefaultReporter(reporter)
	if reporter.Enabled() {
		log.Info("MINGYINGKEJI Reporter initialized", zap.Strings("reporters", reporter.ReporterNames()))
	} else {
		log.Info("MINGYINGKEJI Reporter disabled; using No-op behavior")
	}
	return reporter
}

func provideDatabase(cfg *config.Config, _ *zap.Logger, _ *observability.MINGYINGKEJIReporter) (*gorm.DB, error) {
	db, err := database.InitDB(cfg.Database)
	if err != nil {
		return nil, err
	}

	database.SetDB(db)
	return db, nil
}

func provideRedis(cfg *config.Config) (*redis.Client, error) {
	if err := redispkg.Init(cfg); err != nil {
		return nil, err
	}

	client := redispkg.GetClient()
	redispkg.SetClient(client)
	return client, nil
}

func providePlatformContainer(db *gorm.DB) (*platform.Container, error) {
	return platform.NewContainer(db)
}

func provideListeners(addresses ServerAddresses) (listenerResult, error) {
	httpListener, err := net.Listen("tcp", addresses.HTTP)
	if err != nil {
		return listenerResult{}, fmt.Errorf("failed to listen on %s: %w", addresses.HTTP, err)
	}

	if !addresses.GRPCEnabled {
		return listenerResult{HTTP: httpListener}, nil
	}

	grpcAddr := fmt.Sprintf(":%d", addresses.GRPC)
	grpcListener, err := net.Listen("tcp", grpcAddr)
	if err != nil {
		_ = httpListener.Close()
		return listenerResult{}, fmt.Errorf("failed to listen on %s: %w", grpcAddr, err)
	}

	return listenerResult{
		HTTP: httpListener,
		GRPC: grpcListener,
	}, nil
}

func provideGinEngine(cfg *config.Config, reporter *observability.MINGYINGKEJIReporter, otelResource *OpenTelemetryResource) *gin.Engine {
	setGinMode(cfg.Server.Mode)

	engine := gin.New()
	engine.Use(middleware.RequestID())
	if otelResource != nil && otelResource.Enabled {
		engine.Use(otelgin.Middleware(cfg.OpenTelemetry.ServiceName))
		engine.Use(middleware.OpenTelemetryRequestAttributes())
	}
	engine.Use(middleware.Logger())
	engine.Use(middleware.AuditLogger())
	engine.Use(cors.New(cors.Config{
		// 动态放行任意来源：浏览器端默认同源访问不会触发 CORS；此处作为兜底，
		// 确保不同客户部署环境（任意 IP / 域名 / 端口）下，即便前端使用绝对
		// 地址跨域访问，也不会被 CORS 拦截。
		AllowOriginFunc: func(origin string) bool { return true },
		AllowMethods:    []string{"GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"},
		AllowHeaders:    corsAllowHeaders,
		ExposeHeaders: []string{
			"Content-Length",
			"X-Request-ID",
			"X-MINGYINGKEJI-Request-ID",
			apptransport.HeaderApplicationErrorCode,
			"X-MINGYINGKEJI-Conversation-ID",
			"X-MINGYINGKEJI-Message-ID",
		},
		AllowCredentials: true,
	}))
	engine.Use(middleware.Recovery())

	if reporter.HasReporter("sentry") {
		engine.Use(sentrygin.New(sentrygin.Options{
			Repanic:         true,
			WaitForDelivery: false,
			Timeout:         2 * time.Second,
		}))
	}
	engine.Use(middleware.MINGYINGKEJIErrorReporter(reporter))

	// 初始化离线授权管理器并挂载全局授权拦截中间件。
	// 授权校验只在 Go 后端执行；未启用时中间件直接放行。
	initLicenseManager(cfg)
	engine.Use(middleware.LicenseRequired())

	return engine
}

// initLicenseManager 根据配置初始化全局授权管理器。
//
// 不变量 4：授权模块初始化失败时绝不静默放行。
// NewManager 会把公钥解析错误记录进 Manager，此时受保护请求统一返回
// 503 license_no_public_key；若目录等基础设施创建失败，则记录错误并
// 保留一个未初始化桥接（同样返回 503），确保系统不会"无声地失去授权保护"。
func initLicenseManager(cfg *config.Config) {
	publicKey := cfg.License.PublicKeyPEM
	if publicKey == "" {
		// 未通过环境变量指定公钥时，使用内置公钥。
		publicKey = licensemodule.PublicKeyPEM
	}

	mgr, err := licensemodule.NewManager(licensemodule.Config{
		Enabled:       cfg.License.Enabled,
		LicPath:       cfg.License.LicPath,
		PublicKeyPEM:  publicKey,
		LastCheckFile: cfg.License.LastCheckFile,
	})
	if err != nil {
		// 目录等创建失败属于致命配置问题；仍然挂载一个未初始化的管理器，
		// 由中间件返回 503，避免服务在无授权保护的情况下继续对外提供业务能力。
		logger.Error("license manager init failed, service will answer 503 for protected routes", "error", err)
	}

	licensemodule.SetGlobal(mgr)
}

func provideHTTPServer(cfg *config.Config, addresses ServerAddresses, engine *gin.Engine) *http.Server {
	return &http.Server{
		Addr:           addresses.HTTP,
		Handler:        engine,
		ReadTimeout:    time.Duration(cfg.Server.ReadTimeout) * time.Second,
		WriteTimeout:   time.Duration(cfg.Server.WriteTimeout) * time.Second,
		MaxHeaderBytes: cfg.Server.MaxHeaderBytes,
	}
}

func provideGRPCServer(db *gorm.DB) *grpcinfra.Server {
	return grpcinfra.NewServer(db)
}

func registerInfraLifecycle(lc fx.Lifecycle, db *gorm.DB, redisClient *redis.Client) {
	lc.Append(fx.Hook{
		OnStop: func(ctx context.Context) error {
			var result error

			if redisClient != nil {
				if err := redisClient.Close(); err != nil {
					result = errors.Join(result, err)
				}
			}

			sqlDB, err := db.DB()
			if err != nil {
				return errors.Join(result, err)
			}

			if err := sqlDB.Close(); err != nil {
				result = errors.Join(result, err)
			}

			return result
		},
	})
}

func setGinMode(mode string) {
	switch mode {
	case gin.DebugMode, gin.ReleaseMode, gin.TestMode:
		gin.SetMode(mode)
	default:
		gin.SetMode(gin.DebugMode)
	}
}

func getCORSAllowOrigins() []string {
	cfg := config.Current()
	if len(cfg.Server.CORSAllowOrigins) > 0 {
		logger.Info("CORS origins configured",
			zap.String("source", corsAllowOriginsEnvKey),
			zap.Strings("origins", cfg.Server.CORSAllowOrigins),
		)
		return append([]string(nil), cfg.Server.CORSAllowOrigins...)
	}

	logger.Info("CORS default origins configured", zap.Strings("origins", defaultCORSAllowOrigins))
	return defaultCORSAllowOrigins
}
