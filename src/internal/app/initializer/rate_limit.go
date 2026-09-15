package initializer

import (
	"github.com/SJZYKJ/QLToolsV2-docker/internal/middleware"
)

// StartRateLimitCleanup 启动限速器清理任务
func StartRateLimitCleanup() {
	middleware.StartCleanupTask()
}
