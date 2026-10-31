package v1

import (
	announcementruntime "github.com/webb-chen/AgentSystem/api/internal/modules/app/workflow/announcement"
	"github.com/webb-chen/AgentSystem/api/pkg/logger"
	pkgscheduler "github.com/webb-chen/AgentSystem/api/pkg/scheduler"
)

func registerAnnouncementScheduledTasks(scheduler *pkgscheduler.Scheduler, service *announcementruntime.Service) {
	if scheduler == nil || service == nil {
		return
	}
	task := announcementruntime.NewCleanupExpiredTask("")
	taskHandler := announcementruntime.NewCleanupExpiredHandler(service)
	if err := scheduler.RegisterTask(task, taskHandler); err != nil {
		logger.Error("Failed to register announcement cleanup task", err)
		return
	}
	logger.Info("Announcement cleanup task registered", map[string]interface{}{
		"cron_spec": task.CronSpec(),
	})
}
