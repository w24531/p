function energy = calculate_energy_consumption(task_set, ES_set, ED_set, method_type)
    % 計算能耗統計 - 統一標準，移除方法偏好
    % 輸入:
    %   task_set: 任務集合
    %   ES_set: 邊緣服務器集合
    %   ED_set: 終端設備集合
    %   method_type: 方法類型 ('proposal', 'tsm', 'bat') - 僅用於標識，不影響計算
    % 輸出:
    %   energy: 包含能耗詳細數據的結構體
    
    % 初始化能耗變量
    computation_energy = 0;  % 計算能耗
    communication_energy = 0; % 通信能耗
    idle_energy = 0;         % 空閒能耗
    overhead_energy = 0;     % 額外開銷能耗
    
    % 統一的基礎能耗參數 (單位: J) - 所有方法使用相同參數
    COMP_ENERGY_PER_CYCLE = 1e-9;  % 每個CPU周期消耗的能量
    COMM_ENERGY_PER_BIT = 5e-7;    % 每位數據傳輸消耗的能量
    IDLE_POWER = 0.1;              % 空閒功率(W)
    OVERHEAD_PER_TASK = 0.05;      % 每個任務的額外開銷
    
    % 移除方法特定的調整因子 - 所有方法使用相同的能耗計算
    comp_factor = 1.0;
    comm_factor = 1.0;
    idle_factor = 1.0;
    overhead_factor = 1.0;
    
    % 統計任務狀態並計算已執行任務的能耗
    completed_tasks = 0;
    completed_task_ids = [];
    active_tasks = 0;         % 實際消耗能量的任務數量
    active_task_ids = [];

    for i = 1:length(task_set)

        if isfield(task_set(i), 'is_done') && task_set(i).is_done == 1
            completed_tasks = completed_tasks + 1;
            completed_task_ids(end+1) = i;
        end

        % 判斷任務是否實際消耗能量
        % 先檢查是否屬於早期失敗：未指派且未開始
        if isfield(task_set(i), 'is_done') && task_set(i).is_done == -1 && ...
           (~isfield(task_set(i), 'start_time') || task_set(i).start_time == -1) && ...
           (~isfield(task_set(i), 'ES_ID') || task_set(i).ES_ID == 0)
            continue;  % 早期失敗任務不計入能耗
        end

        is_active = false;
        % 成功完成、已開始、已進入流程或已指派的任務才算活躍
        if isfield(task_set(i), 'is_done') && task_set(i).is_done == 1
            is_active = true;
        elseif isfield(task_set(i), 'start_time') && task_set(i).start_time ~= -1
            is_active = true;
        elseif isfield(task_set(i), 'enter_time') && task_set(i).enter_time ~= -1
            is_active = true;
        elseif isfield(task_set(i), 'ES_ID') && task_set(i).ES_ID > 0
            is_active = true;
        end

        if is_active
            active_tasks = active_tasks + 1;
            active_task_ids(end+1) = i;

            if isfield(task_set(i), 'workload')
                task_comp_energy = task_set(i).workload * COMP_ENERGY_PER_CYCLE * comp_factor;
                computation_energy = computation_energy + task_comp_energy;
            end

            if isfield(task_set(i), 'storage')
                if isfield(task_set(i), 'is_done') && task_set(i).is_done == 1
                    transfer_times = 2; % 上傳與下載皆成功
                else
                    transfer_times = 1; % 僅計入上傳
                end
                task_comm_energy = task_set(i).storage * COMM_ENERGY_PER_BIT * transfer_times * comm_factor;
                communication_energy = communication_energy + task_comm_energy;
            end

            task_overhead = OVERHEAD_PER_TASK * overhead_factor;
            overhead_energy = overhead_energy + task_overhead;

            if isfield(task_set(i), 'is_partition') && task_set(i).is_partition == 1
                if isfield(task_set(i), 'allowed_partition_ratio') && ~isempty(task_set(i).allowed_partition_ratio)
                    partition_overhead = length(task_set(i).allowed_partition_ratio) * 0.01 * overhead_factor;
                    overhead_energy = overhead_energy + partition_overhead;
                end
            end
        end
    end
    
    % 計算ES的空閒能耗 - 統一計算方式
    total_runtime = 0;
    for i = 1:length(ES_set)
        if isfield(ES_set(i), 'core') && ~isempty(ES_set(i).core)
            % 找出最長運行時間
            core_times = zeros(1, length(ES_set(i).core));
            for j = 1:length(ES_set(i).core)
                if isfield(ES_set(i).core(j), 'running_time')
                    core_times(j) = ES_set(i).core(j).running_time;
                end
            end
            max_runtime = max(core_times);
            total_runtime = total_runtime + max_runtime;
        end
    end
    
    % 統一的空閒時間計算
    idle_time = total_runtime * 0.5;
    idle_energy = idle_time * IDLE_POWER * idle_factor / 1000;  % 除以1000轉換為秒
    
    % 汇總所有能耗
    total_energy = computation_energy + communication_energy + idle_energy + overhead_energy;
    
    % 返回結構化結果
    energy = struct();
    energy.computation = computation_energy;
    energy.communication = communication_energy;
    energy.idle = idle_energy;
    energy.overhead = overhead_energy;
    energy.total = total_energy;
    energy.completed_tasks = completed_tasks;
    energy.completed_task_ids = completed_task_ids;
    energy.active_tasks = active_tasks;
    energy.active_task_ids = active_task_ids;
    
    % 如果有執行的任務，計算每任務平均能耗
    if active_tasks > 0
        energy.per_task = total_energy / active_tasks;
    else
        energy.per_task = 0;
    end
    
    % 移除方法特定的能耗分析，使用統一的標準分析
    switch lower(method_type)
        case 'proposal'
            energy.optimization_level = 'standard';
        case 'tsm'
            energy.optimization_level = 'standard';
        case 'bat'
            energy.optimization_level = 'standard';
    end
end