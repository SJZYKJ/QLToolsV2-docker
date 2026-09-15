package service

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/nuanxinqing123/QLToolsV2/internal/app/config"
	_const "github.com/nuanxinqing123/QLToolsV2/internal/const"
	"github.com/nuanxinqing123/QLToolsV2/internal/data/ent"
	"github.com/nuanxinqing123/QLToolsV2/internal/data/ent/cdkey"
	"github.com/nuanxinqing123/QLToolsV2/internal/data/ent/env"
	"github.com/nuanxinqing123/QLToolsV2/internal/data/ent/envplugin"
	"github.com/nuanxinqing123/QLToolsV2/internal/data/ent/panel"
	"github.com/nuanxinqing123/QLToolsV2/internal/data/ent/plugin"
	pkgPlugin "github.com/nuanxinqing123/QLToolsV2/internal/pkg/plugin"
	"github.com/nuanxinqing123/QLToolsV2/internal/schema"
)

type OpenService struct {
	cdkMutexMap   sync.Map       // 基于卡密值的锁映射，每个卡密有独立的锁
	pluginService *PluginService // 插件服务
	panelService  *PanelService  // 面板服务
}

// NewOpenService 创建 OpenService
func NewOpenService() *OpenService {
	return &OpenService{
		pluginService: NewPluginService(),
		panelService:  NewPanelService(),
	}
}

// getCDKMutex 获取指定卡密的互斥锁
func (s *OpenService) getCDKMutex(cdkKey string) *sync.Mutex {
	mutex, _ := s.cdkMutexMap.LoadOrStore(cdkKey, &sync.Mutex{})
	return mutex.(*sync.Mutex)
}

// CheckCDK 检查卡密
func (s *OpenService) CheckCDK(req schema.CheckCDKRequest) (*schema.CheckCDKResponse, error) {
	ctx := context.Background()
	// 查询CDK是否存在
	c, err := config.Ent.CdKey.Query().
		Where(cdkey.KeyEQ(req.Key)).
		Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return &schema.CheckCDKResponse{
				Valid:         false,
				RemainingUses: 0,
				Message:       "卡密不存在",
			}, nil
		}
		return nil, fmt.Errorf("查询卡密失败: %w", err)
	}

	// 检查是否禁用
	if !c.IsEnable {
		return &schema.CheckCDKResponse{
			Valid:         false,
			RemainingUses: c.Count,
			Message:       "卡密已被禁用",
		}, nil
	}

	// 检查使用次数是否足够
	if c.Count <= 0 {
		return &schema.CheckCDKResponse{
			Valid:         false,
			RemainingUses: 0,
			Message:       "卡密使用次数已用完",
		}, nil
	}

	return &schema.CheckCDKResponse{
		Valid:         true,
		RemainingUses: c.Count,
		Message:       "卡密有效",
	}, nil
}

// GetOnlineServices 获取在线服务
func (s *OpenService) GetOnlineServices() (*schema.GetOnlineServicesResponse, error) {
	ctx := context.Background()
	// 查询所有启用的环境变量
	query := config.Ent.Env.Query().Where(env.IsEnableEQ(true))

	// 获取总数
	total, err := query.Count(ctx)
	if err != nil {
		return nil, fmt.Errorf("查询环境变量总数失败: %w", err)
	}

	// 查询所有数据
	envs, err := query.Order(ent.Desc(env.FieldCreatedAt)).All(ctx)
	if err != nil {
		return nil, fmt.Errorf("查询环境变量列表失败: %w", err)
	}

	// 转换为响应格式并计算可用位置数
	var list []schema.OnlineServiceInfo
	for _, e := range envs {
		// 查询该环境变量绑定的启用面板ID
		panelIDs, err := config.Ent.Env.Query().
			Where(env.IDEQ(e.ID)).
			QueryPanels().
			Where(panel.IsEnableEQ(true)).
			IDs(ctx)
		if err != nil {
			return nil, fmt.Errorf("查询绑定面板失败: %w", err)
		}

		// 计算可用位置数：配置变量总数 - 所有面板中该变量的实际数量
		totalSlots := e.Quantity
		usedSlots := int32(0)

		// 遍历所有绑定的面板，统计该变量在每个面板中的数量
		for _, panelID := range panelIDs {
			// 创建青龙API实例
			qlAPI, err := s.panelService.CreateQlAPIWithAutoRefresh(panelID)
			if err != nil {
				config.Log.Warn(fmt.Sprintf("创建面板%d的API实例失败: %v", panelID, err))
				continue
			}

			// 获取面板中的所有环境变量
			envResponse, err := qlAPI.GetEnvs()
			if err != nil {
				config.Log.Warn(fmt.Sprintf("获取面板%d环境变量失败: %v", panelID, err))
				continue
			}

			if envResponse.Code != 200 {
				config.Log.Warn(fmt.Sprintf("获取面板%d环境变量失败，响应码: %d", panelID, envResponse.Code))
				continue
			}

			// 统计该面板中匹配的变量数量
			for _, panelEnv := range envResponse.Data {
				if panelEnv.Name == e.Name {
					usedSlots++
				}
			}
		}

		// 计算可用位置数
		availableSlots := totalSlots - usedSlots
		if availableSlots < 0 {
			availableSlots = 0
		}

		// 调试日志：输出计算过程
		config.Log.Debug(fmt.Sprintf("环境变量[%s] ID=%d: 绑定面板数=%d, 总配额=%d, 已使用=%d, 可用=%d",
			e.Name, e.ID, len(panelIDs), totalSlots, usedSlots, availableSlots))

		list = append(list, schema.OnlineServiceInfo{
			ID:             e.ID,
			Name:           e.Name,
			Remarks:        e.Remarks,
			Quantity:       e.Quantity,
			EnableKey:      e.EnableKey,
			CdkLimit:       e.CdkLimit,
			IsPrompt:       e.IsPrompt,
			PromptLevel:    e.PromptLevel,
			PromptContent:  e.PromptContent,
			AvailableSlots: availableSlots,
		})
	}

	return &schema.GetOnlineServicesResponse{
		Total: int64(total),
		List:  list,
	}, nil
}

// CalculateAvailableSlots 计算剩余位置
func (s *OpenService) CalculateAvailableSlots(req schema.CalculateAvailableSlotsRequest) (*schema.CalculateAvailableSlotsResponse, error) {
	ctx := context.Background()
	// 查询环境变量是否存在且启用
	e, err := config.Ent.Env.Query().
		Where(
			env.IDEQ(req.EnvID),
			env.IsEnableEQ(true),
		).
		Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return nil, errors.New("环境变量不存在或已禁用")
		}
		return nil, fmt.Errorf("查询环境变量失败: %w", err)
	}

	// 查询该环境变量绑定的启用面板ID
	panelIDs, err := config.Ent.Env.Query().
		Where(env.IDEQ(req.EnvID)).
		QueryPanels().
		Where(panel.IsEnableEQ(true)).
		IDs(ctx)
	if err != nil {
		return nil, fmt.Errorf("查询绑定面板失败: %w", err)
	}

	// 计算总位置数和已使用位置数
	totalSlots := e.Quantity
	usedSlots := int32(0)

	// 遍历所有绑定的面板，统计该变量在每个面板中的数量
	for _, panelID := range panelIDs {
		// 创建青龙API实例
		qlAPI, err := s.panelService.CreateQlAPIWithAutoRefresh(panelID)
		if err != nil {
			config.Log.Warn(fmt.Sprintf("创建面板%d的API实例失败: %v", panelID, err))
			continue
		}

		// 获取面板中的所有环境变量
		envResponse, err := qlAPI.GetEnvs()
		if err != nil {
			config.Log.Warn(fmt.Sprintf("获取面板%d环境变量失败: %v", panelID, err))
			continue
		}

		if envResponse.Code != 200 {
			config.Log.Warn(fmt.Sprintf("获取面板%d环境变量失败，响应码: %d", panelID, envResponse.Code))
			continue
		}

		// 统计该面板中匹配的变量数量
		for _, panelEnv := range envResponse.Data {
			if panelEnv.Name == e.Name {
				usedSlots++
			}
		}
	}

	// 计算可用位置数
	availableSlots := totalSlots - usedSlots
	if availableSlots < 0 {
		availableSlots = 0
	}

	return &schema.CalculateAvailableSlotsResponse{
		EnvID:          req.EnvID,
		TotalSlots:     totalSlots,
		UsedSlots:      usedSlots,
		AvailableSlots: availableSlots,
	}, nil
}

// SubmitVariable 提交变量
func (s *OpenService) SubmitVariable(req schema.SubmitVariableRequest) (*schema.SubmitVariableResponse, error) {
	ctx := context.Background()
	// 判断是否为空内容
	if req.Value == "" {
		return &schema.SubmitVariableResponse{
			Success: false,
			Message: "变量值不能为空",
		}, nil
	}

	// 检查变量名是否存在并启用
	e, err := config.Ent.Env.Query().
		Where(
			env.IDEQ(req.EnvID),
			env.IsEnableEQ(true),
		).
		Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return &schema.SubmitVariableResponse{
				Success: false,
				Message: "环境变量不存在或已禁用",
			}, nil
		}
		return nil, fmt.Errorf("查询环境变量失败: %w", err)
	}

	var remainingCDK int32 = 0

	// 检查是否启用KEY，并且用户提交的KEY是否有效
	if e.EnableKey {
		if req.Key == "" {
			return &schema.SubmitVariableResponse{
				Success: false,
				Message: "该服务需要提供有效的卡密",
			}, nil
		}

		// 使用基于卡密值的互斥锁防止并发问题
		cdkMutex := s.getCDKMutex(req.Key)
		cdkMutex.Lock()
		defer cdkMutex.Unlock()

		// 检查卡密
		cdkResp, err := s.CheckCDK(schema.CheckCDKRequest{Key: req.Key})
		if err != nil {
			return nil, fmt.Errorf("检查卡密失败: %w", err)
		}

		if !cdkResp.Valid {
			return &schema.SubmitVariableResponse{
				Success: false,
				Message: cdkResp.Message,
			}, nil
		}

		// 检查卡密次数是否足够
		if cdkResp.RemainingUses < e.CdkLimit {
			return &schema.SubmitVariableResponse{
				Success: false,
				Message: fmt.Sprintf("卡密剩余次数不足，需要%d次，剩余%d次", e.CdkLimit, cdkResp.RemainingUses),
			}, nil
		}

		remainingCDK = cdkResp.RemainingUses
	}

	// 校验正则，判断是否满足提交条件，并提取匹配内容
	if e.Regex != nil && *e.Regex != "" {
		re, err := regexp.Compile(*e.Regex)
		if err != nil {
			return nil, fmt.Errorf("正则表达式错误: %w", err)
		}

		// 查找匹配的内容
		matched := re.FindString(req.Value)
		if matched == "" {
			return &schema.SubmitVariableResponse{
				Success: false,
				Message: "变量值格式不符合要求",
			}, nil
		}

		// 将匹配到的内容替换原始值
		req.Value = matched
	}

	// 执行插件处理
	processedValue := req.Value
	allowSubmit, processErr := s.executeEnvPlugins(req.EnvID, req.Value, &processedValue)
	if processErr != nil {
		return nil, fmt.Errorf("执行插件处理失败: %w", processErr)
	}
	if !allowSubmit {
		// 插件返回false,禁止提交
		return &schema.SubmitVariableResponse{
			Success: false,
			Message: processedValue, // processedValue此时包含禁止原因
		}, nil
	}

	// 执行实时计算，判断是否还有空余提交位置
	slotsResp, err := s.CalculateAvailableSlots(schema.CalculateAvailableSlotsRequest{EnvID: req.EnvID})
	if err != nil {
		return nil, fmt.Errorf("计算可用位置失败: %w", err)
	}
	if slotsResp.AvailableSlots <= 0 {
		return &schema.SubmitVariableResponse{
			Success: false,
			Message: "当前服务已满，暂无可用位置",
		}, nil
	}

	// 提交数据到所有绑定的面板，并根据IsAutoEnvEnable判断是否需要启用提交变量
	// 查询该环境变量绑定的启用面板ID
	panelIDs, err := config.Ent.Env.Query().
		Where(env.IDEQ(req.EnvID)).
		QueryPanels().
		Where(panel.IsEnableEQ(true)).
		IDs(ctx)
	if err != nil {
		return nil, fmt.Errorf("查询绑定面板失败: %w", err)
	}

	// 根据模式选择提交策略
	submittedTo := int32(0)

	switch e.Mode {
	case _const.CreateMode:
		// 新建模式：使用负载均衡，选择可用位置最多的面板
		err = s.submitAndAutoEnable(req.EnvID, panelIDs, e.Name, processedValue, req.Remarks, e.IsAutoEnvEnable)
		if err != nil {
			return nil, err
		}
		submittedTo = 1

	case _const.UpdateMode:
		// 更新模式：遍历所有面板，根据正则表达式匹配并更新
		if e.RegexUpdate == nil || *e.RegexUpdate == "" {
			return nil, errors.New("更新模式下必须设置更新正则表达式")
		}

		updatedCount, _, err := s.updateExistingVariables(panelIDs, e.Name, *e.RegexUpdate, processedValue, req.Remarks)
		if err != nil {
			return nil, fmt.Errorf("更新现有变量失败: %w", err)
		}

		if updatedCount == 0 {
			// 所有面板都没有同名变量，只能新建
			config.Log.Info("更新模式下各面板均无同名变量，使用新建逻辑")
			err = s.submitAndAutoEnable(req.EnvID, panelIDs, e.Name, processedValue, req.Remarks, e.IsAutoEnvEnable)
			if err != nil {
				return nil, err
			}
			submittedTo = 1
		} else {
			submittedTo = int32(updatedCount)
		}

	default:
		return nil, fmt.Errorf("不支持的模式: %d", e.Mode)
	}

	// 如果启用了KEY验证，扣减卡密次数
	if e.EnableKey {
		// 扣减卡密次数
		err = config.Ent.CdKey.Update().
			Where(cdkey.KeyEQ(req.Key)).
			AddCount(-e.CdkLimit).
			Exec(ctx)
		if err != nil {
			return nil, fmt.Errorf("扣减卡密次数失败: %w", err)
		}
		remainingCDK -= e.CdkLimit
	}

	return &schema.SubmitVariableResponse{
		Success:      true,
		Message:      "变量提交成功",
		SubmittedTo:  submittedTo,
		RemainingCDK: remainingCDK,
	}, nil
}

// PanelLoadInfo 面板负载信息
type PanelLoadInfo struct {
	PanelID   int64
	UsedSlots int32
}

// selectBestPanelForSubmit 选择最佳面板进行提交（负载均衡）
// 策略：选择该环境变量数量最少的面板，即负载最轻的面板
func (s *OpenService) selectBestPanelForSubmit(envID int64, panelIDs []int64) (int64, error) {
	ctx := context.Background()
	// 获取环境变量信息
	e, err := config.Ent.Env.Get(ctx, envID)
	if err != nil {
		return 0, fmt.Errorf("查询环境变量失败: %w", err)
	}

	var panelLoads []PanelLoadInfo

	// 获取每个面板的负载情况
	for _, panelID := range panelIDs {
		// 创建青龙API实例
		qlAPI, err := s.panelService.CreateQlAPIWithAutoRefresh(panelID)
		if err != nil {
			config.Log.Warn(fmt.Sprintf("创建面板%d的API实例失败: %v", panelID, err))
			continue
		}

		// 获取面板中的所有环境变量
		envResponse, err := qlAPI.GetEnvs()
		if err != nil {
			config.Log.Warn(fmt.Sprintf("获取面板%d环境变量失败: %v", panelID, err))
			continue
		}

		if envResponse.Code != 200 {
			config.Log.Warn(fmt.Sprintf("获取面板%d环境变量失败，响应码: %d", panelID, envResponse.Code))
			continue
		}

		// 统计该面板中匹配的变量数量
		envCount := int32(0)
		for _, panelEnv := range envResponse.Data {
			if panelEnv.Name == e.Name {
				envCount++
			}
		}

		panelLoads = append(panelLoads, PanelLoadInfo{
			PanelID:   panelID,
			UsedSlots: envCount,
		})
	}

	if len(panelLoads) == 0 {
		return 0, errors.New("没有可用的面板")
	}

	// 按已使用位置数升序排序，选择负载最轻的面板
	sort.Slice(panelLoads, func(i, j int) bool {
		return panelLoads[i].UsedSlots < panelLoads[j].UsedSlots
	})

	bestPanel := panelLoads[0]
	config.Log.Info(fmt.Sprintf("选择面板%d进行提交，当前该变量数量: %d",
		bestPanel.PanelID, bestPanel.UsedSlots))

	return bestPanel.PanelID, nil
}

// submitAndAutoEnable 提交变量到最佳面板并根据配置自动启用
func (s *OpenService) submitAndAutoEnable(envID int64, panelIDs []int64, envName, processedValue, remarks string, isAutoEnable bool) error {
	// 选择最佳面板
	bestPanelID, err := s.selectBestPanelForSubmit(envID, panelIDs)
	if err != nil {
		return fmt.Errorf("选择最佳面板失败: %w", err)
	}

	// 提交到最佳面板
	panelEnvID, err := s.submitToPanel(bestPanelID, envName, processedValue, remarks)
	if err != nil {
		return fmt.Errorf("提交到面板%d失败: %w", bestPanelID, err)
	}

	// 如果需要自动启用，则启用环境变量
	if isAutoEnable && panelEnvID > 0 {
		err = s.enablePanelEnv(bestPanelID, panelEnvID)
		if err != nil {
			config.Log.Warn(fmt.Sprintf("自动启用面板%d变量%d失败: %v", bestPanelID, panelEnvID, err))
		}
	}

	return nil
}

// submitToPanel 提交变量到指定面板
func (s *OpenService) submitToPanel(panelID int64, name, value, remarks string) (int, error) {

	// 创建青龙API实例（使用自动token刷新功能）
	qlAPI, err := s.panelService.CreateQlAPIWithAutoRefresh(panelID)
	if err != nil {
		return 0, fmt.Errorf("创建青龙API实例失败: %w", err)
	}

	// 构建环境变量数据
	envData := []schema.PostEnvRequest{{
		Name:    name,
		Value:   value,
		Remarks: remarks,
	}}

	// 提交环境变量
	response, err := qlAPI.PostEnvs(envData)
	if err != nil {
		return 0, fmt.Errorf("提交环境变量失败: %w", err)
	}

	// 检查响应状态
	if response.Code != 200 {
		return 0, fmt.Errorf("提交失败，响应码: %d", response.Code)
	}

	// 获取创建的变量ID
	if len(response.Data) > 0 {
		createdEnvID := response.Data[0].Id
		config.Log.Info(fmt.Sprintf("成功提交变量到面板%d，变量ID: %d", panelID, createdEnvID))
		return createdEnvID, nil
	}

	return 0, errors.New("未获取到创建的变量ID")
}

// enablePanelEnv 启用面板中的环境变量
func (s *OpenService) enablePanelEnv(panelID int64, envID int) error {
	// 创建青龙API实例
	qlAPI, err := s.panelService.CreateQlAPIWithAutoRefresh(panelID)
	if err != nil {
		return fmt.Errorf("创建青龙API实例失败: %w", err)
	}

	// 启用环境变量
	enableRequest := schema.PutEnableEnvRequest{envID}
	response, err := qlAPI.PutEnableEnvs(enableRequest)
	if err != nil {
		return fmt.Errorf("启用环境变量失败: %w", err)
	}

	if response.Code != 200 {
		return fmt.Errorf("启用失败，响应码: %d", response.Code)
	}

	config.Log.Info(fmt.Sprintf("成功启用面板%d中的变量%d", panelID, envID))
	return nil
}

// updateExistingVariables 更新现有变量（更新模式）
//
// 语义：把用户提交的值「合并」进同名环境变量，而不是整条覆盖。
//   - 已有值按 "&"（或换行）拆成若干字段段，青龙的多值变量就是这么存的
//   - 用 regexPattern 分别从「用户提交的值」和「每个字段段」里提取标识
//   - 标识相同 → 该段原位替换成用户提交的完整值（已有则替换）
//   - 标识都不同 → 在末尾追加用户提交的值（没有则新增）
//   - 合并结果与原有值完全一致时不写回，避免重复提交产生冗余写入
// 面板中不存在同名变量时才返回 0，由调用方退化为新建。
func (s *OpenService) updateExistingVariables(panelIDs []int64, envName, regexPattern, newValue, remarks string) (int, []int64, error) {
	// 编译正则表达式
	regex, err := regexp.Compile(regexPattern)
	if err != nil {
		return 0, nil, fmt.Errorf("编译正则表达式失败: %w", err)
	}

	// 预先从用户提交的值中提取匹配正则的标识（所有面板共享此结果）
	submittedMatch := regex.FindString(newValue)
	if submittedMatch == "" {
		return 0, nil, fmt.Errorf("用户提交的值不匹配正则表达式")
	}

	updatedCount := 0
	var updatedPanelIDs []int64

	// 遍历所有面板
	for _, panelID := range panelIDs {
		// 创建青龙API实例
		qlAPI, err := s.panelService.CreateQlAPIWithAutoRefresh(panelID)
		if err != nil {
			config.Log.Warn(fmt.Sprintf("创建面板%d的API实例失败: %v", panelID, err))
			continue
		}

		// 获取面板中的所有环境变量
		envResponse, err := qlAPI.GetEnvs()
		if err != nil {
			config.Log.Warn(fmt.Sprintf("获取面板%d环境变量失败: %v", panelID, err))
			continue
		}

		if envResponse.Code != 200 {
			config.Log.Warn(fmt.Sprintf("获取面板%d环境变量失败，响应码: %d", panelID, envResponse.Code))
			continue
		}

		// 在同名变量中挑出写入目标：
		//   优先「已包含相同标识」的那条（替换该段）；
		//   都没有命中，就退而把新值追加到第一条同名变量后面。
		targetIdx := -1
		targetValue := ""
		targetAction := ""

		for idx := range envResponse.Data {
			e := envResponse.Data[idx]
			if e.Name != envName {
				continue
			}

			if merged, hit := replaceMatchedSegment(regex, submittedMatch, e.Value, newValue); hit {
				targetIdx = idx
				targetValue = merged
				targetAction = "替换"
				break
			}

			if targetIdx == -1 {
				targetIdx = idx
				targetValue = appendSegment(e.Value, newValue)
				targetAction = "追加"
			}
		}

		if targetIdx == -1 {
			// 该面板没有同名变量，换下一个面板试试
			continue
		}

		target := envResponse.Data[targetIdx]

		if targetValue == target.Value {
			// 提交的内容已经在该变量里了，不必重复写入
			config.Log.Info(fmt.Sprintf("面板%d变量%d已包含相同内容，跳过写入: %s", panelID, target.Id, target.Name))
			updatedCount++
			updatedPanelIDs = append(updatedPanelIDs, panelID)
			break
		}

		updateRequest := schema.PutEnvRequest{
			Id:      target.Id,
			Name:    target.Name,
			Value:   targetValue,
			Remarks: remarks,
		}

		updateResponse, err := qlAPI.PutEnvs(updateRequest)
		if err != nil {
			config.Log.Warn(fmt.Sprintf("更新面板%d变量%d失败: %v", panelID, target.Id, err))
			continue
		}

		if updateResponse.Code != 200 {
			config.Log.Warn(fmt.Sprintf("更新面板%d变量%d失败，响应码: %d", panelID, target.Id, updateResponse.Code))
			continue
		}

		config.Log.Info(fmt.Sprintf("成功%s面板%d变量%d: %s (匹配标识: %s) => %s",
			targetAction, panelID, target.Id, target.Name, submittedMatch, targetValue))
		updatedCount++
		updatedPanelIDs = append(updatedPanelIDs, panelID)
		break
	}

	return updatedCount, updatedPanelIDs, nil
}

// envSeparator 判断已有值使用的多值分隔符：沿用原有风格，默认用 "&"
func envSeparator(value string) string {
	if strings.Contains(value, "\n") {
		return "\n"
	}
	return "&"
}

// splitEnvSegments 把多值环境变量拆成字段段，"&" 与换行都当作分隔符，忽略空白段
func splitEnvSegments(value string) []string {
	segments := make([]string, 0, 4)
	for _, line := range strings.Split(value, "\n") {
		for _, part := range strings.Split(line, "&") {
			if seg := strings.TrimSpace(part); seg != "" {
				segments = append(segments, seg)
			}
		}
	}
	return segments
}

// replaceMatchedSegment 在已有值里找出「标识与提交值相同」的段，原位替换成 newValue
// 命中返回（合并后的值, true）；没有命中返回（"", false）
func replaceMatchedSegment(regex *regexp.Regexp, submittedMatch, existingValue, newValue string) (string, bool) {
	segments := splitEnvSegments(existingValue)
	if len(segments) == 0 {
		return "", false
	}

	hit := false
	for i, seg := range segments {
		if !hit && regex.FindString(seg) == submittedMatch {
			segments[i] = newValue
			hit = true
		}
	}

	if !hit {
		return "", false
	}
	return strings.Join(segments, envSeparator(existingValue)), true
}

// appendSegment 把新值追加到已有值末尾
func appendSegment(existingValue, newValue string) string {
	segments := append(splitEnvSegments(existingValue), newValue)
	return strings.Join(segments, envSeparator(existingValue))
}

// executeEnvPlugins 执行环境变量绑定的插件
// 返回值: (是否允许继续提交, 错误)
// processedValue: 插件处理后的值或禁止原因
func (s *OpenService) executeEnvPlugins(envID int64, envValue string, processedValue *string) (bool, error) {
	ctx := context.Background()
	// 查询该环境变量绑定的启用插件，按执行顺序排序
	results, err := config.Ent.EnvPlugin.Query().
		Where(
			envplugin.EnvIDEQ(envID),
			envplugin.IsEnableEQ(true),
		).
		WithPlugin(func(q *ent.PluginQuery) {
			q.Where(plugin.IsEnableEQ(true))
		}).
		Order(ent.Asc(envplugin.FieldExecutionOrder)).
		All(ctx)

	if err != nil {
		return false, fmt.Errorf("查询环境变量插件失败: %w", err)
	}

	// 如果没有插件，直接返回允许提交
	if len(results) == 0 {
		*processedValue = envValue
		return true, nil
	}

	// 依次执行插件
	currentValue := envValue
	for _, item := range results {
		p := item.Edges.Plugin
		if p == nil {
			continue
		}

		// 构建执行上下文
		var configData []byte
		if item.Config != nil && *item.Config != "" {
			configData = []byte(*item.Config)
		} else {
			configData = []byte("{}")
		}

		execCtx := &pkgPlugin.ExecutionContext{
			PluginID:  item.PluginID,
			EnvID:     envID,
			EnvValue:  currentValue,
			Config:    configData,
			Timestamp: time.Now().Unix(),
		}

		// 执行插件
		timeout := time.Duration(p.ExecutionTimeout) * time.Millisecond
		pluginResult := s.pluginService.engine.Execute(context.Background(), p.ScriptContent, execCtx, timeout)

		// 记录执行日志
		s.pluginService.logPluginExecution(item.PluginID, envID, pluginResult)

		// 检查执行是否成功
		if !pluginResult.Success {
			return false, fmt.Errorf("插件 %s 执行失败: %s", p.Name, pluginResult.ErrorMessage)
		}

		// 解析插件返回结果
		if pluginResult == nil || len(pluginResult.OutputData) == 0 {
			// 插件没有返回数据，使用原值继续
			continue
		}

		// 解析返回的JSON: {bool: true/false, env: "value"}
		var result map[string]interface{}
		if err := config.JSON.Unmarshal(pluginResult.OutputData, &result); err != nil {
			return false, fmt.Errorf("插件 %s 返回数据格式错误: %w", p.Name, err)
		}

		// 检查bool字段
		allowContinue, ok := result["bool"].(bool)
		if !ok {
			return false, fmt.Errorf("插件 %s 返回数据缺少bool字段或类型错误", p.Name)
		}

		// 获取env字段
		envResult, ok := result["env"].(string)
		if !ok {
			return false, fmt.Errorf("插件 %s 返回数据缺少env字段或类型错误", p.Name)
		}

		// 如果bool为false，禁止提交
		if !allowContinue {
			*processedValue = envResult // 此时envResult包含禁止原因
			return false, nil
		}

		// 更新当前值，用于下一个插件
		currentValue = envResult
	}

	// 所有插件执行完成，返回最终处理后的值
	*processedValue = currentValue
	return true, nil
}
