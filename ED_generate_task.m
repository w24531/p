function [task_set, newTK_set] = ED_generate_task(ED_set, ES_set, task_set, task_parm, new_task_nums, task_generate_time, divisible_ratio)
    % === ED 產生新任務（事先隨機分割策略版本）===
    % 重點：任務的分割策略在生成時即確定，不可動態調整
    
    % 任務參數範圍
    deadline_rng = task_parm.deadline;
    workload_rng = task_parm.workload;
    storage_rng = task_parm.storage;
    if isfield(task_parm, 'memory')
        memory_rng = task_parm.memory;
    else
        memory_rng = [1, 1];
    end
    
    if nargin < 7
        divisible_ratio = 1.0;
    end
    
    % ===== 核心修正：預定義分割策略（事先確定，不可動態調整）=====
    predefined_partition_strategies = {
        [],                         % 不可分割
        [0.5, 0.5],                % 二分割：平均分成兩部分
        [0.33, 0.33, 0.34],        % 三分割：盡量平均分成三部分
        [0.25, 0.25, 0.25, 0.25],  % 四分割：平均分成四部分
        [0.2, 0.2, 0.2, 0.2, 0.2] % 五分割：平均分成五部分
    };
    
    task_ID = length(task_set) + 1;
    newTK_set = [];
    
    if new_task_nums <= 0 || isempty(ED_set)
        return;
    end
    
    % 隨機選擇ED
    edIDs = randperm(length(ED_set), min(new_task_nums, length(ED_set)));
    
    for k = 1:new_task_nums
        ED_id = edIDs(min(k, length(edIDs)));
        
        % === 創建任務結構 ===
        if ~isempty(task_set)
            tk = create_task_from_template(task_set(1));
        else
            tk = create_standard_task_structure();
        end
        
        % 設置基本屬性
        tk.ID = task_ID;
        tk.ED_ID = ED_id;
        tk.workload = generate_task_parm(workload_rng(1), workload_rng(2), 1);
        tk.storage = generate_task_parm(storage_rng(1), storage_rng(2), 0);
        tk.memory  = generate_task_parm(memory_rng(1), memory_rng(2), 0);
        tk.generate_time = task_generate_time;
        tk.expired_time = task_generate_time + generate_task_parm(deadline_rng(1), deadline_rng(2), 1);
        tk.transfer_time = 0;
        
        % ===== 關鍵修正：事先確定分割策略（隨機選擇） =====
        if rand() < divisible_ratio
            % 隨機選擇一種預定義分割策略（排除不可分割選項）
            strategy_idx = randi(length(predefined_partition_strategies)-1) + 1;
            tk.is_partition = 1;
            tk.allowed_partition_ratio = predefined_partition_strategies{strategy_idx};
            tk.partition_fixed = true; % 標記為固定分割，不可動態調整
            
            % 新增：記錄分割策略類型（用於debug和分析）
            tk.partition_strategy_type = strategy_idx; % 2=二分割, 3=三分割, 4=四分割, 5=五分割
            
            % fprintf('[DEBUG] 任務 %d 設為 %d 分割策略: %s\n', tk.ID, strategy_idx, mat2str(tk.allowed_partition_ratio));
        else
            tk.is_partition = 0;
            tk.allowed_partition_ratio = [];
            tk.partition_fixed = true; % 即使不可分割也標記為固定
            tk.partition_strategy_type = 0; % 0=不可分割
            
            % fprintf('[DEBUG] 任務 %d 設為不可分割\n', tk.ID);
        end
        
        % ES綁定
        if ~isempty(ES_set)
            tk.ES_id = find_nearest_ES(ED_set(ED_id), ES_set);
        else
            tk.ES_id = 1;
        end
        
        % === 安全的結構體添加 ===
        try
            if isempty(task_set)
                task_set = tk;
            else
                tk = reorder_fields_to_match(tk, task_set(1));
                task_set(end+1) = tk;
            end
            
            if isempty(newTK_set)
                newTK_set = tk;
            else
                newTK_set(end+1) = tk;
            end
            
        catch ME
            % fprintf('任務添加錯誤: %s\n', ME.message);
            % 使用更安全的方法
            if isempty(task_set)
                task_set = struct();
                task_set(1) = tk;
            else
                unified_tk = unify_task_structure(tk, task_set(1));
                task_set(end+1) = unified_tk;
            end
            
            if isempty(newTK_set)
                newTK_set = tk;
            else
                newTK_set(end+1) = tk;
            end
        end
        
        task_ID = task_ID + 1;
    end
    
    % === 顯示分割策略統計（用於驗證） ===
    if ~isempty(newTK_set)
        partition_stats = zeros(1, 6); % 0=不可分割, 1=未使用, 2=二分割, 3=三分割, 4=四分割, 5=五分割
        for i = 1:length(newTK_set)
            if isfield(newTK_set(i), 'partition_strategy_type')
                type_idx = newTK_set(i).partition_strategy_type + 1;
                if type_idx >= 1 && type_idx <= 6
                    partition_stats(type_idx) = partition_stats(type_idx) + 1;
                end
            end
        end
        
        % fprintf('[INFO] 本批次分割策略統計: 不可分割=%d, 二分割=%d, 三分割=%d, 四分割=%d, 五分割=%d\n', ...
        %     partition_stats(1), partition_stats(3), partition_stats(4), partition_stats(5), partition_stats(6));
    end
end

% === 輔助函數 ===
function tk = create_task_from_template(template_task)
    % === 根據現有模板創建新任務結構 ===
    
    % 獲取所有欄位名稱
    field_names = fieldnames(template_task);
    
    % 創建新結構體
    tk = struct();
    
    for i = 1:length(field_names)
        field_name = field_names{i};
        tk.(field_name) = get_default_field_value(field_name);
    end
end

function tk = create_standard_task_structure()
    % 創建標準任務結構，包含所有必要欄位
    tk = struct();
    
    % 基本識別
    tk.ID = 0;
    tk.ED_ID = 0;
    tk.ES_id = 0;
    tk.ES_ID = 0;
    
    % 任務屬性
    tk.workload = 0;
    tk.storage = 0;
    tk.memory  = 0;
    tk.is_partition = 0;
    tk.allowed_partition_ratio = [];
    tk.partition_fixed = true; % 新增：標記分割策略是否固定
    tk.partition_strategy_type = 0; % 新增：記錄分割策略類型
    
    % 時間相關
    tk.generate_time = 0;
    tk.expired_time = 0;
    tk.start_time = -1;
    tk.finish_time = -1;
    tk.assigned_time = -1;
    tk.enter_time = -1;
    tk.transfer_time = 0;
    
    % 狀態相關
    tk.is_done = 0;
    tk.retry_count = 0;
    tk.status = '';
    
    % 路徑和轉發
    tk.ES_path = [];
    tk.candidate_ES = [];
    tk.route = [];
    tk.last_ES_ID = 0;
    tk.fwd_ES_ID = 0;
    
    % 排程相關
    tk.Tcost = 0;
    tk.priority_value = 0;
    tk.priority_score = 0;
    
    % 增強功能欄位
    tk.enhanced_cost = 0;
    tk.energy_estimate = 0;
    tk.delay_estimate = 0;
    tk.execution_strategy = '';
    tk.partition_strategy = '';
    tk.drop_reason = '';
    
    % Proposal方法特有欄位
    tk.collaboration_mode = '';
    tk.preferred_ES_ids = [];
    tk.collaboration_priority = 0;
    tk.subtasks = [];
end

function reordered_tk = reorder_fields_to_match(tk, reference_task)
    % === 重新排列欄位順序以匹配參考任務 ===
    
    reference_fields = fieldnames(reference_task);
    tk_fields = fieldnames(tk);
    
    reordered_tk = struct();
    
    % 首先添加參考任務中的所有欄位
    for i = 1:length(reference_fields)
        field_name = reference_fields{i};
        if isfield(tk, field_name)
            reordered_tk.(field_name) = tk.(field_name);
        else
            reordered_tk.(field_name) = get_default_field_value(field_name);
        end
    end
    
    % 然後添加新任務中額外的欄位
    for i = 1:length(tk_fields)
        field_name = tk_fields{i};
        if ~isfield(reordered_tk, field_name)
            reordered_tk.(field_name) = tk.(field_name);
        end
    end
end

function unified_tk = unify_task_structure(new_task, reference_task)
    % === 強制統一任務結構 ===
    
    % 獲取參考任務的所有欄位
    ref_fields = fieldnames(reference_task);
    
    % 創建統一後的任務
    unified_tk = struct();
    
    % 按照參考任務的欄位順序添加
    for i = 1:length(ref_fields)
        field_name = ref_fields{i};
        
        if isfield(new_task, field_name)
            unified_tk.(field_name) = new_task.(field_name);
        else
            unified_tk.(field_name) = get_default_field_value(field_name);
        end
    end
    
    % 添加新任務中的額外欄位
    new_fields = fieldnames(new_task);
    for i = 1:length(new_fields)
        field_name = new_fields{i};
        if ~isfield(unified_tk, field_name)
            unified_tk.(field_name) = new_task.(field_name);
        end
    end
end

function value = get_default_field_value(field_name)
    % === 根據欄位名稱返回預設值 ===
    
    switch lower(field_name)
        case {'start_time', 'finish_time', 'assigned_time', 'enter_time'}
            value = -1;
        case {'retry_count', 'last_es_id', 'fwd_es_id', 'es_id', 'id', 'ed_id', 'es_id', ...
              'partition_strategy_type', 'collaboration_priority'}
            value = 0;
        case {'candidate_es', 'route', 'es_path', 'allowed_partition_ratio', 'preferred_es_ids', 'subtasks'}
            value = [];
        case {'status', 'execution_strategy', 'partition_strategy', 'drop_reason', 'collaboration_mode'}
            value = '';
        case {'transfer_time', 'tcost', 'priority_value', 'workload', 'storage', 'memory', ...
              'enhanced_cost', 'energy_estimate', 'delay_estimate', 'priority_score'}
            value = 0;
        case {'is_done', 'is_partition', 'partition_fixed'}
            value = 0;
        case {'expired_time', 'generate_time'}
            value = 0;
        otherwise
            value = [];
    end
end