package initializer

import (
	"io/fs"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/SJZYKJ/QLToolsV2-docker/internal/pkg/response"
	"github.com/SJZYKJ/QLToolsV2-docker/web"
)

// SetupWebFrontend 注册前端静态资源
func SetupWebFrontend(r *gin.Engine) {
	// 创建一个子文件系统，根目录为 dist/assets
	assetsFS, err := fs.Sub(web.DistFS, "dist/assets")
	if err != nil {
		panic(err)
	}
	// 提供静态资源
	r.StaticFS("/assets", http.FS(assetsFS))

	// 对于所有未匹配的路由，返回 index.html（支持 Vue Router history 模式）
	r.NoRoute(func(c *gin.Context) {
		// ⚠️ 未匹配的 API 路径必须返回 JSON，绝不能回 index.html。
		// 否则前端响应拦截器会把一坨 HTML 当成正常响应，解析不出 code 字段，
		// 最终只弹出一个没有任何信息量的 "Error"，把「路由不存在 / 方法不对」
		// 伪装成「后端出错了」。（历史上 POST /api/auth/logout 就踩过这个坑）
		if strings.HasPrefix(c.Request.URL.Path, "/api/") {
			response.ResErrorWithMsg(c, response.CodeInvalidRouterRequested,
				"接口不存在: "+c.Request.Method+" "+c.Request.URL.Path)
			return
		}

		// 获取文件内容
		data, err := web.DistFS.ReadFile("dist/index.html")
		if err != nil {
			c.String(http.StatusInternalServerError, "index.html not found")
			return
		}

		// 判断是否请求静态资源（比如 .js/.css），直接 404
		if strings.Contains(c.Request.RequestURI, ".") {
			c.String(http.StatusNotFound, "404 page not found")
			return
		}

		// 返回 HTML
		c.Data(http.StatusOK, "text/html; charset=utf-8", data)
	})
}
