package initializer

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/SJZYKJ/QLToolsV2-docker/internal/app/config"
	"github.com/SJZYKJ/QLToolsV2-docker/internal/data/ent/user"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
)

// 初始管理员账号相关的环境变量。
//
// 之所以走环境变量而不是 config.yaml：
//   - 密码不需要落盘到配置文件里（配置文件在容器里是明文，容易被打进镜像/日志）；
//   - 环境变量不受 YAML 引号转义限制，密码里出现 " ' \ $ # 等字符也不会把配置写坏。
const (
	// EnvAdminUsername 初始管理员用户名，默认 admin
	EnvAdminUsername = "QLTOOLS_ADMIN_USERNAME"
	// EnvAdminPassword 初始管理员密码。不设置则完全跳过自动建号
	EnvAdminPassword = "QLTOOLS_ADMIN_PASSWORD"
	// EnvAdminReset 置为 1 时，对已存在的同名账号强制重置密码（忘记密码的补救手段）
	EnvAdminReset = "QLTOOLS_ADMIN_RESET"
)

// SeedAdmin 初始化管理员账号。
//
// 规则：
//   - 未设置 QLTOOLS_ADMIN_PASSWORD：什么都不做，沿用「首次访问自行注册」的老流程；
//   - 库中一个用户都没有：按 QLTOOLS_ADMIN_USERNAME / QLTOOLS_ADMIN_PASSWORD 建号；
//   - 库中已有用户：默认不动（避免容器重启把密码改回去），
//     只有显式设置 QLTOOLS_ADMIN_RESET=1 时才重置同名账号的密码。
//
// 必须在 data.InitData() 之后调用（那时建表迁移已完成）。
func SeedAdmin() error {
	password := os.Getenv(EnvAdminPassword)
	if password == "" {
		return nil
	}

	username := strings.TrimSpace(os.Getenv(EnvAdminUsername))
	if username == "" {
		username = "admin"
	}

	ctx := context.Background()

	cnt, err := config.Ent.User.Query().Count(ctx)
	if err != nil {
		return fmt.Errorf("查询用户数量失败: %w", err)
	}

	if cnt > 0 {
		if strings.TrimSpace(os.Getenv(EnvAdminReset)) != "1" {
			config.Log.Info("数据库中已存在用户，跳过初始管理员创建",
				zap.String("username", username))
			return nil
		}
		return resetAdminPassword(ctx, username, password)
	}

	hashed, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("密码加密失败: %w", err)
	}

	now := time.Now()
	if _, err = config.Ent.User.Create().
		SetUsername(username).
		SetPassword(string(hashed)).
		SetCreatedAt(now).
		SetUpdatedAt(now).
		Save(ctx); err != nil {
		return fmt.Errorf("创建初始管理员失败: %w", err)
	}

	config.Log.Info("已自动创建管理员账号，可直接用该账号登录后台",
		zap.String("username", username))
	return nil
}

// resetAdminPassword 重置已存在管理员的密码（QLTOOLS_ADMIN_RESET=1 时才走到这里）
func resetAdminPassword(ctx context.Context, username, password string) error {
	u, err := config.Ent.User.Query().
		Where(user.UsernameEQ(username)).
		Only(ctx)
	if err != nil {
		return fmt.Errorf("未找到用户 %q，无法重置密码（请改用该用户的用户名）: %w", username, err)
	}

	hashed, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("密码加密失败: %w", err)
	}

	if _, err = config.Ent.User.UpdateOneID(u.ID).
		SetPassword(string(hashed)).
		SetUpdatedAt(time.Now()).
		Save(ctx); err != nil {
		return fmt.Errorf("重置密码失败: %w", err)
	}

	config.Log.Info("已按环境变量重置管理员密码",
		zap.String("username", username))
	return nil
}
