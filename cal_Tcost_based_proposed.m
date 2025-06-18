function [Tcost] = cal_Tcost_based_proposed(task, alpha, beta, time, ES, all_ES_set)
    % === 增強版 Proposal 任務成本計算函數 ===
    % 整合學術建議的多重優化策略
    %
    % 輸入參數:
    %   task: 任務結構
    %   alpha: 時間緊急度權重
    %   beta: 分割獎勵權重
    %   time: 當前時間
    %   ES: 當前評估的邊緣伺服器
    %   all_ES_set: 所有ES集合（用於鄰居負載計算）
    %
    % 輸出:
    %   Tcost: 增強的任務執行成本
    
    % === 1. 基礎時間緊急度計算 ===
    remain_time = task.expired_time - time - (task.transfer_time / 2);
    if remain_time <= 0
        Tcost = inf;
        return;
    end
    
    % 增強的時間緊急度（考慮非線性緊急程度）
    if remain_time < 10  % 極度緊急
        urgency_factor = 3.0;
    elseif remain_time < 20  % 緊急
        urgency_factor = 2.0;
    elseif remain_time < 50  % 中等緊急
        urgency_factor = 1.5;
    else  % 不緊急
        urgency_factor = 1.0;
    end
    
    time_urgency = alpha * urgency_factor / remain_time;
    
    % === 2. 工作量規模影響 ===
    if isfield(task, 'workload') && ~isempty(task.workload)
        workload_factor = task.workload / 1e6;  % 標準化到百萬單位
        
        % 大任務在高負載時懲罰更重
        es_load_ratio = calculate_ES_load_ratio(ES);
        if workload_factor > 2.0 && es_load_ratio > 0.7
            workload_penalty = workload_factor * 0.3;
        else
            workload_penalty = workload_factor * 0.1;
        end
    else
        workload_penalty = 0;
    end
    
    % === 3. 增強的分割獎勵機制 ===
    partition_benefit = 0;
    if isfield(task, 'is_partition') && task.is_partition == 1 && ...
       isfield(task, 'allowed_partition_ratio') && ~isempty(task.allowed_partition_ratio)
        
        num_parts = length(task.allowed_partition_ratio);
        
        % 檢查ES的多核心可用性
        available_cores = count_available_cores(ES, time);
        usable_cores = min(available_cores, num_parts);
        
        if usable_cores >= 2
            % 並行效益評估
            parallel_efficiency = calculate_parallel_efficiency(usable_cores, num_parts);
            
            % 通信開銷評估
            comm_overhead = estimate_partition_communication_overhead(task, usable_cores);
            
            % 只有在通信開銷合理時才給予分割獎勵
            if comm_overhead < 0.2  % 通信開銷小於20%
                base_partition_benefit = beta * (-0.3 * parallel_efficiency);
                
                % 系統負載高時，分割獎勵更大（協助負載分散）
                if es_load_ratio > 0.6
                    partition_benefit = base_partition_benefit * 1.4;
                else
                    partition_benefit = base_partition_benefit;
                end
            else
                % 通信開銷過高，給予懲罰而非獎勵
                partition_benefit = beta * 0.2;
            end
        else
            % 可用核心不足，輕微懲罰分割任務
            partition_benefit = beta * 0.1;
        end
    end
    
    % === 4. 負載感知調整 ===
    % 本地負載
    local_load_factor = es_load_ratio;
    
    % 全域負載感知（去中心化協作的關鍵）
    global_load_factor = calculate_global_load_awareness(ES, all_ES_set);
    
    % 綜合負載調整
    load_adjustment = 0.4 * local_load_factor + 0.2 * global_load_factor;
    
    % 在高負載時，更積極地避開負載重的ES
    if local_load_factor > 0.8
        load_penalty = load_adjustment * 2.5;  % 高負載重懲罰
    elseif local_load_factor > 0.6
        load_penalty = load_adjustment * 1.5;  % 中等負載適度懲罰
    else
        load_penalty = load_adjustment * 0.8;  % 低負載輕微調整
    end
    
    % === 5. 能耗優化因子 ===
    energy_factor = calculate_energy_efficiency_factor(task, ES, time);
    
    % === 6. 協作潛力評估 ===
    collaboration_potential = 0;
    if task.is_partition == 1 && available_cores >= 2
        collaboration_potential = evaluate_collaboration_potential(ES, all_ES_set, task);
    end
    
    % === 7. 截止期感知加權 ===
    deadline_awareness = calculate_deadline_awareness_factor(task, time);
    
    % === 8. 綜合成本計算 ===
    base_cost = time_urgency + workload_penalty;
    optimization_adjustments = partition_benefit + energy_factor * 0.15;
    load_costs = load_penalty + collaboration_potential;
    deadline_costs = deadline_awareness * 0.3;
    
    Tcost = base_cost + optimization_adjustments + load_costs + deadline_costs;
    
    % === 9. 特殊情況處理 ===
    
    % 小任務優先處理（提高整體吞吐量）
    if workload_factor < 0.8
        Tcost = Tcost * 0.85;  % 15%優先權
    end
    
    % 緊急任務進一步提升優先權
    if remain_time < 15
        Tcost = Tcost * 0.7;   % 30%優先權提升
    end
    
    % 防止負值成本
    Tcost = max(Tcost, 0.001);
end

function available_cores = count_available_cores(ES, time)
    % === 計算可用核心數量 ===
    available_cores = 0;
    tolerance = 5;  % 5ms容忍度
    
    for i = 1:length(ES.core)
        if ES.core(i).running_time <= time + tolerance
            available_cores = available_cores + 1;
        end
    end
end

function efficiency = calculate_parallel_efficiency(usable_cores, total_parts)
    % === 計算並行執行效率 ===
    if usable_cores <= 1
        efficiency = 0;
        return;
    end
    
    % Amdahl定律的簡化模型
    parallel_portion = 0.9;  % 90%可並行化
    serial_portion = 0.1;    % 10%必須串行
    
    theoretical_speedup = 1 / (serial_portion + parallel_portion / usable_cores);
    
    % 實際效率考慮協調開銷
    coordination_overhead = (usable_cores - 1) * 0.05;  % 每增加一個核心5%開銷
    
    efficiency = max(0.1, theoretical_speedup / usable_cores - coordination_overhead);
end

function overhead = estimate_partition_communication_overhead(task, num_cores)
    % === 估算分割通信開銷 ===
    
    % 基礎模型：開銷與分割數量和數據大小相關
    base_data_transfer = task.storage * 0.1;  % 10%數據需要在核心間傳輸
    coordination_msgs = num_cores * 0.02;     % 協調消息
    synchronization_cost = (num_cores - 1) * 0.01;  % 同步成本
    
    total_comm_cost = base_data_transfer + coordination_msgs + synchronization_cost;
    computation_benefit = task.workload / (num_cores * 1e6);  % 標準化計算效益
    
    overhead = total_comm_cost / max(computation_benefit, 0.1);
end

% function load_ratio = calculate_ES_load_ratio(ES)
%     % === 計算 ES 負載比例 ===
%     % 將計算與儲存的佔用分開正規化，避免單位混用
% 
%     workload_ratio = 0;
%     if isfield(ES, 'total_workloads') && isfield(ES, 'core_rate') && isfield(ES, 'core_nums')
%         capacity = ES.core_rate * ES.core_nums;
%         workload_ratio = ES.total_workloads / max(capacity, 1);
%     end
% 
%     storage_ratio = 0;
%     if isfield(ES, 'queue_storage') && isfield(ES, 'max_storage')
%         storage_ratio = ES.queue_storage / max(ES.max_storage, 1);
%     end
% 
%     load_ratio = (workload_ratio + storage_ratio) / 2;
%     load_ratio = max(0, min(load_ratio, 1.0));
% end

function global_factor = calculate_global_load_awareness(current_ES, all_ES_set)
    % === 計算全域負載感知因子 ===
    
    global_factor = 0;
    
    if ~isfield(current_ES, 'neighbor_ES') || isempty(current_ES.neighbor_ES)
        return;
    end
    
    neighbor_loads = [];
    
    % 收集鄰居負載信息
    for i = 1:length(current_ES.neighbor_ES)
        neighbor_id = current_ES.neighbor_ES(i);
        if neighbor_id > 0 && neighbor_id <= length(all_ES_set)
            neighbor_load = calculate_ES_load_ratio(all_ES_set(neighbor_id));
            neighbor_loads(end+1) = neighbor_load;
        end
    end
    
    if ~isempty(neighbor_loads)
        avg_neighbor_load = mean(neighbor_loads);
        max_neighbor_load = max(neighbor_loads);
        
        % 如果鄰居普遍負載高，當前ES壓力也大
        global_factor = 0.7 * avg_neighbor_load + 0.3 * max_neighbor_load;
    end
end

function energy_factor = calculate_energy_efficiency_factor(task, ES, time)
    % === 計算能效因子 ===
    
    % 簡化能耗模型
    processing_energy = task.workload * 1.2e-9;  % 處理能耗
    communication_energy = task.storage * 3e-7;   % 通信能耗
    idle_energy = 0.1 * 0.01;  % 空閒能耗（10ms）
    
    total_energy = processing_energy + communication_energy + idle_energy;
    
    % 正規化能效因子
    energy_factor = total_energy * 1000;  % 轉換為毫焦耳級別
    
    % 在低負載時降低能耗權重，高負載時提高
    es_load = calculate_ES_load_ratio(ES);
    if es_load > 0.7
        energy_factor = energy_factor * 1.3;
    elseif es_load < 0.3
        energy_factor = energy_factor * 0.7;
    end
end

function potential = evaluate_collaboration_potential(current_ES, all_ES_set, task)
    % === 評估協作潛力 ===
    
    potential = 0;
    
    if ~isfield(current_ES, 'neighbor_ES') || isempty(current_ES.neighbor_ES)
        return;
    end
    
    % 檢查鄰居ES的協作可能性
    available_neighbors = 0;
    neighbor_capacity_sum = 0;
    
    for i = 1:length(current_ES.neighbor_ES)
        neighbor_id = current_ES.neighbor_ES(i);
        if neighbor_id > 0 && neighbor_id <= length(all_ES_set)
            neighbor_ES = all_ES_set(neighbor_id);
            
            % 檢查鄰居是否有空閒容量
            if (neighbor_ES.queue_storage + task.storage) <= neighbor_ES.max_storage
                neighbor_load = calculate_ES_load_ratio(neighbor_ES);
                if neighbor_load < 0.8  % 負載不太高
                    available_neighbors = available_neighbors + 1;
                    neighbor_capacity_sum = neighbor_capacity_sum + (1 - neighbor_load);
                end
            end
        end
    end
    
    if available_neighbors > 0
        % 協作潛力與可用鄰居數量和其剩餘容量相關
        avg_neighbor_capacity = neighbor_capacity_sum / available_neighbors;
        potential = -0.1 * min(available_neighbors, 3) * avg_neighbor_capacity;  % 負值表示成本降低
    end
end

function deadline_factor = calculate_deadline_awareness_factor(task, time)
    % === 計算截止期感知因子 ===
    
    remain_time = task.expired_time - time;
    total_time = task.expired_time - task.generate_time;
    
    if total_time <= 0 || remain_time <= 0
        deadline_factor = 5.0;  % 極高優先級
        return;
    end
    
    % 計算時間消耗比例
    time_consumed_ratio = (total_time - remain_time) / total_time;
    
    % 截止期壓力評估
    if time_consumed_ratio > 0.8  % 已消耗80%時間
        deadline_factor = 2.0;
    elseif time_consumed_ratio > 0.6  % 已消耗60%時間
        deadline_factor = 1.0;
    elseif time_consumed_ratio > 0.4  % 已消耗40%時間
        deadline_factor = 0.5;
    else
        deadline_factor = 0.1;  % 時間充裕
    end
end
