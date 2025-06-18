function config = proposal_optimization_config()
    % === Proposal 方法優化配置文件 ===
    % 基於學術建議的參數配置，針對不同場景優化
    
    config = struct();
    
    % === 基礎參數 ===
    config.version = '2.0_enhanced';
    config.optimization_target = 'completion_rate_and_latency';
    
    % === 自適應參數控制 ===
    config.adaptive_control = struct();
    config.adaptive_control.enable = true;
    config.adaptive_control.update_frequency = 10;  % 每10個時間單位更新一次
    config.adaptive_control.sensitivity = 0.15;     % 參數調整敏感度
    
    % === 負載分類閾值 ===
    config.load_thresholds = struct();
    config.load_thresholds.low = 0.3;     % 低負載閾值
    config.load_thresholds.medium = 0.6;  % 中等負載閾值
    config.load_thresholds.high = 0.8;    % 高負載閾值
    config.load_thresholds.critical = 0.95; % 臨界負載閾值
    
    % === 任務複製策略 ===
    config.replication = struct();
    config.replication.enable = true;
    config.replication.max_replicas = 2;              % 最大複製數
    config.replication.load_threshold = 0.75;         % 啟動複製的負載閾值
    config.replication.indivisible_priority = 1.5;    % 不可分割任務複製優先權
    config.replication.urgent_task_threshold = 15;    % 緊急任務時間閾值(ms)
    
    % === 分割優化策略 ===
    config.partitioning = struct();
    config.partitioning.max_partitions = 5;                    % 最大分割數
    config.partitioning.min_cores_required = 2;                % 分割所需最小核心數
    config.partitioning.communication_overhead_limit = 0.15;   % 通信開銷限制
    config.partitioning.efficiency_threshold = 0.90;          % 分割效率閾值
    config.partitioning.coordination_overhead_per_core = 0.05; % 每核心協調開銷
    
    % === 能耗優化 ===
    config.energy = struct();
    config.energy.enable = true;
    config.energy.processing_energy_per_cycle = 1.2e-9;  % 每周期處理能耗
    config.energy.communication_energy_per_bit = 3e-7;   % 每位通信能耗
    config.energy.idle_power = 0.1;                      % 空閒功率(W)
    config.energy.dvfs_enable = true;                    % 動態電壓頻率調節
    config.energy.energy_weight_in_cost = 0.15;          % 能耗在成本函數中的權重
    
    % === 協作機制 ===
    config.collaboration = struct();
    config.collaboration.enable = true;
    config.collaboration.neighbor_awareness = true;       % 鄰居感知
    config.collaboration.max_collaborators = 4;           % 最大協作者數
    config.collaboration.collaboration_threshold = 0.3;   % 協作啟動閾值
    config.collaboration.global_load_weight = 0.4;        % 全域負載權重
    config.collaboration.migration_enable = true;         % 任務遷移
    
    % === 調度策略 ===
    config.scheduling = struct();
    config.scheduling.priority_scheme = 'deadline_aware'; % 優先級方案
    config.scheduling.indivisible_first = true;           % 不可分割任務優先
    config.scheduling.small_task_bonus = 0.15;            % 小任務獎勵
    config.scheduling.urgent_task_multiplier = 0.7;       % 緊急任務優先權倍數
    
    % === 負載平衡 ===
    config.load_balancing = struct();
    config.load_balancing.enable = true;
    config.load_balancing.rebalance_threshold = 0.6;      % 重平衡閾值
    config.load_balancing.migration_candidate_limit = 2;   % 遷移候選任務限制
    config.load_balancing.target_load_difference = 0.3;   % 目標負載差異
    
    % === 成本函數參數 ===
    config.cost_function = struct();
    config.cost_function.time_urgency_base_weight = 1.0;       % 時間緊急度基礎權重
    config.cost_function.partition_benefit_weight = -0.3;      % 分割獎勵權重
    config.cost_function.load_penalty_weight = 0.4;            % 負載懲罰權重
    config.cost_function.deadline_awareness_weight = 0.3;      % 截止期感知權重
    config.cost_function.neighbor_influence_weight = 0.2;      % 鄰居影響權重
    
    % === 性能監控 ===
    config.monitoring = struct();
    config.monitoring.enable = true;
    config.monitoring.metrics_history_length = 100;      % 指標歷史長度
    config.monitoring.alert_thresholds = struct(...
        'completion_rate', 0.95, ...
        'avg_latency_ms', 100, ...
        'energy_budget_ratio', 1.2);
    
    % === 場景特定配置 ===
    config.scenarios = struct();
    
    % 高密度場景 (大量ED)
    config.scenarios.high_density = struct();
    config.scenarios.high_density.ed_threshold = 2000;
    config.scenarios.high_density.load_balance_weight = 0.7;     % 強化負載平衡
    config.scenarios.high_density.replication_factor = 2.5;     % 更積極的複製
    config.scenarios.high_density.collaboration_threshold = 0.2; % 降低協作門檻
    config.scenarios.high_density.partition_preference = 0.8;   % 偏好分割處理
    
    % 低密度場景 (少量ED)
    config.scenarios.low_density = struct();
    config.scenarios.low_density.ed_threshold = 1000;
    config.scenarios.low_density.load_balance_weight = 0.3;     % 降低負載平衡權重
    config.scenarios.low_density.replication_factor = 1.2;     % 保守的複製策略
    config.scenarios.low_density.collaboration_threshold = 0.6; % 提高協作門檻
    config.scenarios.low_density.energy_optimization = 1.2;    % 強化能耗優化
    
    % 混合工作負載場景
    config.scenarios.mixed_workload = struct();
    config.scenarios.mixed_workload.divisible_ratio_threshold = 0.5;
    config.scenarios.mixed_workload.adaptive_partitioning = true;
    config.scenarios.mixed_workload.intelligent_scheduling = true;
    config.scenarios.mixed_workload.dynamic_priority_adjustment = true;
    
    % === 分割比例特定優化 ===
    config.partition_ratio_optimization = struct();
    
    % 0% 可分割任務場景
    config.partition_ratio_optimization.ratio_0 = struct();
    config.partition_ratio_optimization.ratio_0.focus = 'completion_rate';
    config.partition_ratio_optimization.ratio_0.replication_multiplier = 3.0;
    config.partition_ratio_optimization.ratio_0.load_avoidance_strength = 2.0;
    config.partition_ratio_optimization.ratio_0.migration_aggressiveness = 1.5;
    config.partition_ratio_optimization.ratio_0.backup_allocation_rate = 0.8;
    
    % 50% 可分割任務場景  
    config.partition_ratio_optimization.ratio_50 = struct();
    config.partition_ratio_optimization.ratio_50.focus = 'balanced_optimization';
    config.partition_ratio_optimization.ratio_50.partition_efficiency_threshold = 0.85;
    config.partition_ratio_optimization.ratio_50.hybrid_strategy_weight = 0.6;
    config.partition_ratio_optimization.ratio_50.communication_optimization = true;
    config.partition_ratio_optimization.ratio_50.dynamic_core_allocation = true;
    
    % 100% 可分割任務場景
    config.partition_ratio_optimization.ratio_100 = struct();
    config.partition_ratio_optimization.ratio_100.focus = 'latency_minimization';
    config.partition_ratio_optimization.ratio_100.max_parallelism_utilization = 0.95;
    config.partition_ratio_optimization.ratio_100.fine_grain_partitioning = true;
    config.partition_ratio_optimization.ratio_100.over_partitioning_prevention = true;
    config.partition_ratio_optimization.ratio_100.synchronization_optimization = true;
    
    % === 動態優化參數 ===
    config.dynamic_optimization = struct();
    config.dynamic_optimization.enable = true;
    config.dynamic_optimization.adaptation_rate = 0.1;          % 適應速率
    config.dynamic_optimization.performance_window = 50;        % 性能評估窗口
    config.dynamic_optimization.trigger_thresholds = struct(...
        'completion_rate_drop', 0.05, ...                      % 完成率下降閾值
        'latency_increase', 0.15, ...                          % 延遲增加閾值
        'energy_increase', 0.20);                              % 能耗增加閾值
    
    % === 實驗優化建議 ===
    config.experimental_enhancements = struct();
    
    % MADRL (多代理深度強化學習) 模擬
    config.experimental_enhancements.madrl_simulation = struct();
    config.experimental_enhancements.madrl_simulation.enable = false;  % 默認關閉
    config.experimental_enhancements.madrl_simulation.learning_rate = 0.01;
    config.experimental_enhancements.madrl_simulation.cooperation_reward = 0.3;
    config.experimental_enhancements.madrl_simulation.exploration_rate = 0.1;
    
    % 預測式調度
    config.experimental_enhancements.predictive_scheduling = struct();
    config.experimental_enhancements.predictive_scheduling.enable = true;
    config.experimental_enhancements.predictive_scheduling.prediction_horizon = 20;  % 預測時間範圍
    config.experimental_enhancements.predictive_scheduling.confidence_threshold = 0.7;
    
    % 聯邦學習模擬
    config.experimental_enhancements.federated_learning = struct();
    config.experimental_enhancements.federated_learning.enable = false;  % 默認關閉
    config.experimental_enhancements.federated_learning.knowledge_sharing_rate = 0.2;
    config.experimental_enhancements.federated_learning.privacy_preservation = true;
    
    % === 調試和監控 ===
    config.debug = struct();
    config.debug.enable = false;                               % 生產環境關閉
    config.debug.verbose_logging = false;
    config.debug.performance_profiling = false;
    config.debug.decision_tracking = false;                    % 決策追踪
    config.debug.energy_monitoring = false;                    % 能耗監控
    
    % === 與TSM/BAT的差異化策略 ===
    config.differentiation = struct();
    config.differentiation.vs_tsm = struct();
    config.differentiation.vs_tsm.superior_load_balancing = true;
    config.differentiation.vs_tsm.advanced_partitioning = true;
    config.differentiation.vs_tsm.neighbor_awareness = true;
    config.differentiation.vs_tsm.energy_consciousness = true;
    
    config.differentiation.vs_bat = struct();
    config.differentiation.vs_bat.intelligent_task_classification = true;
    config.differentiation.vs_bat.adaptive_replication = true;
    config.differentiation.vs_bat.global_optimization = true;
    config.differentiation.vs_bat.communication_efficiency = true;
    
    % === 性能目標設定 ===
    config.performance_targets = struct();
    config.performance_targets.completion_rate_target = 0.998;  % 99.8%
    config.performance_targets.latency_improvement_vs_tsm = 0.25; % 25%改善
    config.performance_targets.latency_improvement_vs_bat = 0.35; % 35%改善
    config.performance_targets.energy_reduction_target = 0.20;   % 20%節能
    config.performance_targets.load_balance_efficiency = 0.90;   % 90%負載平衡效率
    
    % === 故障處理和容錯 ===
    config.fault_tolerance = struct();
    config.fault_tolerance.enable = true;
    config.fault_tolerance.max_retry_attempts = 2;
    config.fault_tolerance.fallback_strategy = 'single_core_execution';
    config.fault_tolerance.error_recovery_timeout = 5;         % 錯誤恢復超時(ms)
    config.fault_tolerance.graceful_degradation = true;        % 優雅降級
    
    % === 版本兼容性 ===
    config.compatibility = struct();
    config.compatibility.matlab_version_required = '2019b';
    config.compatibility.backward_compatible = true;
    config.compatibility.legacy_mode_available = true;
    
    % === 最終配置驗證 ===
    config = validate_configuration(config);
end

function validated_config = validate_configuration(config)
    % === 配置驗證函數 ===
    validated_config = config;
    
    % 檢查關鍵參數的合理性
    if config.load_thresholds.low >= config.load_thresholds.medium
        warning('Load threshold configuration may be incorrect');
        validated_config.load_thresholds.low = 0.3;
        validated_config.load_thresholds.medium = 0.6;
    end
    
    % 限制複製因子在合理範圍內
    if config.replication.max_replicas > 3
        warning('Maximum replicas limited to 3 for stability');
        validated_config.replication.max_replicas = 3;
    end
    
    % 確保分割參數合理
    if config.partitioning.communication_overhead_limit > 0.3
        warning('Communication overhead limit too high, reducing to 0.3');
        validated_config.partitioning.communication_overhead_limit = 0.3;
    end
    
    % 驗證性能目標的可達性
    if config.performance_targets.completion_rate_target > 0.999
        warning('Completion rate target may be too aggressive');
    end
    
    % 添加配置時間戳
    validated_config.meta = struct();
    validated_config.meta.created_time = datestr(now);
    validated_config.meta.config_version = config.version;
    validated_config.meta.validation_passed = true;
    
    fprintf('[Config] Proposal optimization configuration loaded successfully (v%s)\n', config.version);
end