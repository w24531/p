function method_proposal(ED_set, ES_set, task_set, filename, alpha, beta, time, transfer_time, newTK_set)
    % === 優化版 Proposal Method ===
    % 基於學術建議的優化策略：提高完成率、降低延遲、優化能耗
    
    try
        % 載入先前狀態（若存在）
        if time > 1
            try
                load(filename, 'ED_set', 'ES_set', 'task_set');
            catch
                % 若載入失敗，使用傳入的參數
            end
        end

        % 合併新任務到 task_set
        if ~isempty(newTK_set)
            if ~isempty(task_set)
                task_set = unify_task_fields(task_set, newTK_set);
                newTK_set = unify_task_fields(newTK_set, task_set);
                task_set = [task_set, newTK_set];
            else
                task_set = newTK_set;
            end
        end

        % === 新增：計算系統負載和自適應參數調整 ===
        system_load_ratio = calculate_system_load(ES_set);
        adaptive_params = calculate_adaptive_parameters(system_load_ratio, alpha, beta);
        
        % Stage 1: 改進的新任務分配（混合策略）
        if ~isempty(newTK_set)
            [ES_set, task_set] = assign_new_tasks_enhanced(ED_set, ES_set, task_set, newTK_set, adaptive_params, time);
        end

        % Stage 2: 優化的未完成任務處理
        for ES_id = 1:length(ES_set)
            undone_task_id_set = ES_set(ES_id).undone_task_ID_set;
            if isempty(undone_task_id_set)
                continue;
            end

            % 更新核心至當前時間
            for c = 1:length(ES_set(ES_id).core)
                if ES_set(ES_id).core(c).running_time < time
                    ES_set(ES_id).core(c).running_time = time;
                end
            end

            % 優化的任務處理（包含複製策略和智能調度）
            [ES_set(ES_id), task_set] = process_undone_tasks_enhanced(...
                ES_set(ES_id), task_set, undone_task_id_set, time, adaptive_params, ES_set);
        end

        % Stage 3: 新增全域協作優化
        if system_load_ratio > 0.6  % 高負載時啟動協作機制
            [ES_set, task_set] = global_collaboration_optimization(ES_set, task_set, time, adaptive_params);
        end

        % Debug 輸出
        if mod(time, 20) == 0
            completed_tasks = sum([task_set.is_done] == 1);
            failed_tasks = sum([task_set.is_done] == -1);
            pending_tasks = sum([task_set.is_done] == 0);
            total_tasks = length(task_set);

            fprintf('[Enhanced Proposal] Time=%d: Completed=%d (%.1f%%), Failed=%d (%.1f%%), Pending=%d (%.1f%%), Load=%.2f\n', ...
                time, completed_tasks, completed_tasks/total_tasks*100, ...
                failed_tasks, failed_tasks/total_tasks*100, ...
                pending_tasks, pending_tasks/total_tasks*100, system_load_ratio);
        end

        save(filename, 'ED_set', 'ES_set', 'task_set');
    catch ME
        fprintf('Enhanced Proposal execution error: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('Error location: %s, line: %d\n', ME.stack(1).name, ME.stack(1).line);
        end
        save(filename, 'ED_set', 'ES_set', 'task_set');
    end
end

function system_load = calculate_system_load(ES_set)
    % === 計算系統整體負載 ===
    if isempty(ES_set)
        system_load = 0;
        return;
    end

    total_ratio = 0;
    for i = 1:length(ES_set)
        total_ratio = total_ratio + calculate_ES_load_ratio(ES_set(i));
    end

    system_load = total_ratio / length(ES_set);
end

function params = calculate_adaptive_parameters(system_load, alpha, beta)
    % === 自適應參數調整 ===
    params = struct();
    params.original_alpha = alpha;
    params.original_beta = beta;
    
    % 根據系統負載動態調整參數
    if system_load > 0.8  % 高負載
        params.alpha = alpha * 1.3;  % 提高時間緊急度權重
        params.beta = beta * 0.8;    % 降低分割權重，避免過度分割
        params.replication_factor = 2.5;  % 啟用任務複製
        params.cooperation_threshold = 0.3;  % 降低協作門檻
        params.load_balance_weight = 0.6;   % 強化負載平衡
    elseif system_load > 0.5  % 中等負載
        params.alpha = alpha * 1.1;
        params.beta = beta * 0.9;
        params.replication_factor = 1.5;
        params.cooperation_threshold = 0.5;
        params.load_balance_weight = 0.4;
    else  % 低負載
        params.alpha = alpha;
        params.beta = beta * 1.1;  % 可以更積極分割
        params.replication_factor = 1.0;
        params.cooperation_threshold = 0.7;
        params.load_balance_weight = 0.2;
    end
    
    % 新增優化參數
    params.deadline_awareness_factor = 1.5;  % 截止期感知因子
    params.energy_optimization_factor = 0.85;  % 能耗優化因子
    params.partition_overhead_limit = 0.15;  % 分割開銷限制（15%）
end

function [ES_set, task_set] = assign_new_tasks_enhanced(ED_set, ES_set, task_set, newTK_set, params, time)
    % === 增強的新任務分配邏輯 ===
    
    for newTK_idx = 1:length(newTK_set)
        newTK_id = newTK_set(newTK_idx).ID;
        
        % 安全檢查
        if newTK_id <= 0 || newTK_id > length(task_set)
            continue;
        end
        
        task = task_set(newTK_id);
        ED_id = task.ED_ID;
        
        if ED_id <= 0 || ED_id > length(ED_set)
            task_set(newTK_id).is_done = -1;
            continue;
        end
        
        % 檢查該 ED 是否有候選 ES
        if isempty(ED_set(ED_id).candidate_ES)
            task_set(newTK_id).is_done = -1;
            continue;
        end
        
        % 獲取有效的候選 ES
        candidate_list = ED_set(ED_id).candidate_ES;
        candidate_list = candidate_list(candidate_list > 0 & candidate_list <= length(ES_set));
        
        if isempty(candidate_list)
            task_set(newTK_id).is_done = -1;
            continue;
        end
        
        % === 關鍵改進：混合策略選擇 ES ===
        if task.is_partition == 0  % 不可分割任務：使用複製策略
            [best_ES_id, backup_ES_id] = select_ES_for_indivisible_task(ES_set, candidate_list, task, params, time);
            
            % 主要分配
            if best_ES_id > 0
                ES_set(best_ES_id) = ES_set(best_ES_id).add_task(task.workload, task.storage, task.memory, newTK_id);
                task_set(newTK_id).ES_ID = best_ES_id;
                task_set(newTK_id).ES_path = [best_ES_id];
                task_set(newTK_id).enter_time = time;
                
                % 如果系統負載高且有備份ES，標記為複製任務
                if backup_ES_id > 0 && params.replication_factor > 1.8
                    task_set(newTK_id).backup_ES_ID = backup_ES_id;
                    task_set(newTK_id).has_replica = true;
                end
            else
                task_set(newTK_id).is_done = -1;
            end
            
        else  % 可分割任務：智能協作分配
            [allocated_ES_ids, allocation_success] = select_ES_for_divisible_task(ES_set, candidate_list, task, params, time);

            if allocation_success && ~isempty(allocated_ES_ids)
                ratios = task.allowed_partition_ratio;
                if isempty(ratios)
                    ratios = ones(1, length(allocated_ES_ids)) / length(allocated_ES_ids);
                end

                for idx = 1:length(allocated_ES_ids)
                    es_id = allocated_ES_ids(idx);
                    r = ratios(min(idx, length(ratios)));
                    wl_part = task.workload * r;
                    st_part = task.storage * r;
                    mem_part = task.memory  * r;
                    ES_set(es_id) = ES_set(es_id).add_task(wl_part, st_part, mem_part, newTK_id);
                    sub.memory  = mem_part;

                    sub.es_id = es_id;
                    sub.workload = wl_part;
                    sub.storage = st_part;
                    sub.start_time = -1;
                    sub.finish_time = -1;
                    sub.is_done = 0;
                    if ~isfield(task_set(newTK_id), 'subtasks') || isempty(task_set(newTK_id).subtasks)
                        task_set(newTK_id).subtasks = sub;
                    else
                        task_set(newTK_id).subtasks(end+1) = sub;
                    end
                end

                task_set(newTK_id).ES_ID = allocated_ES_ids(1);
                task_set(newTK_id).ES_path = allocated_ES_ids;
                task_set(newTK_id).collaboration_ES_list = allocated_ES_ids;
                task_set(newTK_id).enter_time = time;
            else
                task_set(newTK_id).is_done = -1;
            end
        end
    end
end

function [best_ES_id, backup_ES_id] = select_ES_for_indivisible_task(ES_set, candidate_list, task, params, time)
    % === 為不可分割任務選擇最佳ES（含備份策略）===
    
    best_ES_id = 0;
    backup_ES_id = 0;
    best_score = inf;
    backup_score = inf;
    
    for i = 1:length(candidate_list)
        ES_id = candidate_list(i);
        
        % 確保ES_id在有效範圍內
        if ES_id <= 0 || ES_id > length(ES_set)
            continue;
        end
        
        % 檢查儲存容量
        if (ES_set(ES_id).queue_storage + task.storage) > ES_set(ES_id).max_storage || ...
           (ES_set(ES_id).queue_memory + task.memory)  > ES_set(ES_id).max_memory
            continue;
        end
        
        % === 評分機制：考慮負載、延遲、能耗 ===
        
        % 1. 負載分數
        load_factor = calculate_ES_load_ratio(ES_set(ES_id));
        load_score = load_factor * params.load_balance_weight * 2.0;
        
        % 2. 時間可用性分數
        core_times = zeros(1, length(ES_set(ES_id).core));
        for j = 1:length(ES_set(ES_id).core)
            core_times(j) = ES_set(ES_id).core(j).running_time;
        end
        min_core_time = min(core_times);
        earliest_available = max(time, min_core_time);
        
        % 計算預估完成時間
        % 安全計算平均核心速率
        total_rate = 0;
        valid_cores = 0;
        for j = 1:length(ES_set(ES_id).core)
            if isfield(ES_set(ES_id).core(j), 'rate') && ES_set(ES_id).core(j).rate > 0
                total_rate = total_rate + ES_set(ES_id).core(j).rate;
                valid_cores = valid_cores + 1;
            end
        end
        
        if valid_cores == 0
            avg_core_rate = 5e7;  % 默認值
        else
            avg_core_rate = total_rate / valid_cores;
        end
        
        estimated_exec_time = task.workload / avg_core_rate * 1000;
        estimated_finish = earliest_available + estimated_exec_time;
        
        % 截止期感知評分
        time_margin = task.expired_time - estimated_finish;
        if time_margin <= 0
            continue;  % 無法按時完成，跳過
        end
        deadline_score = params.deadline_awareness_factor / max(time_margin, 0.001);  % 避免除零
        
        % 3. 鄰居負載考量
        neighbor_load_score = 0;
        if isfield(ES_set(ES_id), 'neighbor_ES') && ~isempty(ES_set(ES_id).neighbor_ES)
            total_neighbor_load = 0;
            valid_neighbors = 0;
            
            for j = 1:length(ES_set(ES_id).neighbor_ES)
                neighbor_id = ES_set(ES_id).neighbor_ES(j);
                if neighbor_id > 0 && neighbor_id <= length(ES_set)
                    neighbor_load = calculate_ES_load_ratio(ES_set(neighbor_id));
                    total_neighbor_load = total_neighbor_load + neighbor_load;
                    valid_neighbors = valid_neighbors + 1;
                end
            end
            
            if valid_neighbors > 0
                avg_neighbor_load = total_neighbor_load / valid_neighbors;
                neighbor_load_score = avg_neighbor_load * 0.2;
            end
        end
        
        % 綜合評分
        total_score = load_score + deadline_score + neighbor_load_score;
        
        % 選擇最佳和備份
        if total_score < best_score
            backup_score = best_score;
            backup_ES_id = best_ES_id;
            best_score = total_score;
            best_ES_id = ES_id;
        elseif total_score < backup_score
            backup_score = total_score;
            backup_ES_id = ES_id;
        end
    end
end

function [allocated_ES_ids, success] = select_ES_for_divisible_task(ES_set, candidate_list, task, params, time)
    % === 為可分割任務選擇協作ES群組 ===
    
    allocated_ES_ids = [];
    success = false;
    
    if ~isfield(task, 'allowed_partition_ratio') || isempty(task.allowed_partition_ratio)
        % 如果沒有預定義分割，降級到單ES處理
        [primary_ES, ~] = select_ES_for_indivisible_task(ES_set, candidate_list, task, params, time);
        if primary_ES > 0
            allocated_ES_ids = [primary_ES];
            success = true;
        end
        return;
    end
    
    num_partitions = length(task.allowed_partition_ratio);
    
    % === 智能協作ES選擇 ===
    
    % 1. 篩選有足夠容量的候選ES
    suitable_ES = [];
    for i = 1:length(candidate_list)
        ES_id = candidate_list(i);
        if (ES_set(ES_id).queue_storage + task.storage) <= ES_set(ES_id).max_storage && ...
           (ES_set(ES_id).queue_memory + task.memory)  <= ES_set(ES_id).max_memory
            % 評估此ES的適合度
            suitability = evaluate_ES_suitability_for_partition(ES_set(ES_id), task, params, time);
            if suitability > 0.3  % 適合度門檻
                suitable_ES(end+1) = ES_id;
            end
        end
    end
    
    if length(suitable_ES) < 2
        % 不夠ES進行分割，降級到單ES
        if ~isempty(suitable_ES)
            allocated_ES_ids = [suitable_ES(1)];
            success = true;
        end
        return;
    end
    
    % 2. 選擇最佳協作群組（限制在分割數或可用ES數）
    max_collaborators_options = [num_partitions, length(suitable_ES), 4];
    max_collaborators = min(max_collaborators_options);  % 使用向量形式
    
    % 計算通信開銷，避免過度分割
    comm_overhead_ratio = estimate_communication_overhead(task, max_collaborators);
    if comm_overhead_ratio > params.partition_overhead_limit
        % 通信開銷過高，減少協作者數量
        max_collaborators = max(2, floor(max_collaborators * 0.7));
    end
    
    % 選擇負載最均衡的ES組合
    [optimal_ES_group, collaboration_benefit] = find_optimal_collaboration_group(...
        ES_set, suitable_ES, max_collaborators, task, params);
    
    if collaboration_benefit > 0.1  % 協作效益門檻
        allocated_ES_ids = optimal_ES_group;
        success = true;
    else
        % 協作效益不足，使用單ES
        allocated_ES_ids = [suitable_ES(1)];
        success = true;
    end
end

function suitability = evaluate_ES_suitability_for_partition(ES, task, params, time)
    % === 評估ES對分割任務的適合度 ===
    
    % 1. 核心數量適合度
    available_cores = 0;
    for c = 1:length(ES.core)
        if ES.core(c).running_time <= time + 10  % 10ms內可用
            available_cores = available_cores + 1;
        end
    end
    core_suitability = min(available_cores / 2, 1.0);  % 至少需要2個核心
    
    % 2. 負載適合度
    load_ratio = calculate_ES_load_ratio(ES);
    load_suitability = 1.0 - load_ratio;
    
    % 3. 時間適合度
    min_available_time = min([ES.core.running_time]);
    time_margin = task.expired_time - max(time, min_available_time);
    
    % 安全計算平均核心速率
    total_rate = 0;
    for c = 1:length(ES.core)
        total_rate = total_rate + ES.core(c).rate;
    end
    avg_core_rate = total_rate / length(ES.core);  % 安全計算平均值
    
    exec_time_estimate = task.workload / avg_core_rate * 1000;
    
    % 防止除零或負值
    if time_margin <= 0 || exec_time_estimate <= 0
        time_suitability = 0;
    else
        time_suitability = max(0, min(1, (time_margin - exec_time_estimate) / time_margin));
    end
    
    % 綜合適合度
    suitability = core_suitability * 0.4 + load_suitability * 0.4 + time_suitability * 0.2;
end

function overhead_ratio = estimate_communication_overhead(task, num_collaborators)
    % === 估算通信開銷比例 ===
    
    % 基礎通信成本模型
    base_comm_cost = task.storage * 0.1;  % 基礎數據傳輸
    coordination_cost = num_collaborators * 0.05;  % 協調成本
    synchronization_cost = (num_collaborators - 1) * 0.02;  % 同步成本
    
    total_comm_cost = base_comm_cost + coordination_cost + synchronization_cost;
    computation_benefit = task.workload / num_collaborators;
    
    % 避免除零
    if (total_comm_cost + computation_benefit) <= 0
        overhead_ratio = 0.5;  % 預設值
    else
        overhead_ratio = total_comm_cost / (total_comm_cost + computation_benefit);
    end
end

function [optimal_group, benefit] = find_optimal_collaboration_group(ES_set, suitable_ES, max_size, task, params)
    % === 尋找最佳協作群組 ===
    
    optimal_group = [];
    benefit = 0;
    
    if length(suitable_ES) < 2
        if ~isempty(suitable_ES)
            optimal_group = suitable_ES;
        end
        return;
    end
    
    % 簡化的貪婪算法選擇最佳組合
    % 1. 按負載排序，選擇最輕負載的ES
    load_scores = zeros(1, length(suitable_ES));
    for i = 1:length(suitable_ES)
        ES_id = suitable_ES(i);
        if ES_id > 0 && ES_id <= length(ES_set)
            load_scores(i) = calculate_ES_load_ratio(ES_set(ES_id));
        else
            load_scores(i) = 1.0;  % 無效ES給高負載分數
        end
    end
    
    [~, sorted_indices] = sort(load_scores);
    selected_count_options = [max_size, length(suitable_ES)];
    selected_count = min(selected_count_options);
    
    optimal_group = suitable_ES(sorted_indices(1:selected_count));
    
    % 計算協作效益
    if isempty(optimal_group)
        benefit = 0;
        return;
    end
    
    first_es_id = optimal_group(1);
    if first_es_id <= 0 || first_es_id > length(ES_set) || isempty(ES_set(first_es_id).core)
        benefit = 0;
        return;
    end
    
    % 安全計算第一個ES的核心速率
    first_core_rate = 0;
    if isfield(ES_set(first_es_id).core(1), 'rate')
        first_core_rate = ES_set(first_es_id).core(1).rate;
    else
        first_core_rate = 5e7;  % 默認值
    end
    
    if first_core_rate <= 0
        benefit = 0;
        return;
    end
    
    single_exec_time = task.workload / first_core_rate;
    
    % 安全計算並行效率
    parallel_efficiency = 0.85;  % 85%並行效率
    effective_cores = length(optimal_group) * parallel_efficiency;
    
    if effective_cores <= 0
        benefit = 0;
        return;
    end

    parallel_exec_time = task.workload / (effective_cores * first_core_rate);
    
    if single_exec_time <= 0
        benefit = 0;
    else
        benefit = max(0, (single_exec_time - parallel_exec_time) / single_exec_time);
    end
end
function energy_cost = estimate_energy_cost(task, ES, params)
    % === 估算能耗成本 ===
    
    % 簡化的能耗模型
    processing_energy = task.workload * 1e-9 * params.energy_optimization_factor;
    communication_energy = task.storage * 2e-7;
    
    energy_cost = (processing_energy + communication_energy) * 1000;  % 標準化
end

function neighbor_impact = calculate_neighbor_load_impact(ES_set, ES_id)
    % === 計算鄰居負載影響 ===
    
    neighbor_impact = 0;
    
    if ~isfield(ES_set(ES_id), 'neighbor_ES') || isempty(ES_set(ES_id).neighbor_ES)
        return;
    end
    
    total_neighbor_load = 0;
    valid_neighbors = 0;
    
    for i = 1:length(ES_set(ES_id).neighbor_ES)
        neighbor_id = ES_set(ES_id).neighbor_ES(i);
        if neighbor_id > 0 && neighbor_id <= length(ES_set)
            neighbor_load = calculate_ES_load_ratio(ES_set(neighbor_id));
            total_neighbor_load = total_neighbor_load + neighbor_load;
            valid_neighbors = valid_neighbors + 1;
        end
    end
    
    if valid_neighbors > 0
        avg_neighbor_load = total_neighbor_load / valid_neighbors;
        neighbor_impact = avg_neighbor_load * 0.3;  % 鄰居負載影響係數
    end
end

function [ES, task_set] = process_undone_tasks_enhanced(ES, task_set, undone_task_id_set, time, params, all_ES_set)
    % === 增強的未完成任務處理 ===
    
    valid_ids = [];
    
    % 1. 移除已過期任務，收集有效任務
    for i = 1:length(undone_task_id_set)
        tid = undone_task_id_set(i);
        if tid <= 0 || tid > length(task_set)
            continue;
        end
        if task_set(tid).expired_time <= time
            if isfield(task_set(tid), 'subtasks') && ~isempty(task_set(tid).subtasks)
                sidx = find([task_set(tid).subtasks.es_id] == ES.ID, 1);
                if ~isempty(sidx)
                    sub = task_set(tid).subtasks(sidx);
                    ES = ES.remove_task(sub.workload, sub.storage, sub.memory, tid, -1);
                    task_set(tid).subtasks(sidx).is_done = -1;
                end
                if all([task_set(tid).subtasks.is_done] ~= 0)
                    task_set(tid).is_done = -1;
                end
            else
                ES = ES.remove_task(task_set(tid).workload, task_set(tid).storage, task_set(tid).memory, tid, -1);
                task_set(tid).is_done = -1;
            end
        else
            % 使用增強的成本計算
            task_set(tid).Tcost = calculate_enhanced_task_cost(task_set(tid), params, time, ES);
            if task_set(tid).enter_time == -1
                task_set(tid).enter_time = time;
            end
            valid_ids(end+1) = tid;
        end
    end
    
    if isempty(valid_ids)
        return;
    end
    
    % 2. 智能排序：分離可分割和不可分割任務
    divisible_tasks = [];
    indivisible_tasks = [];
    
    for i = 1:length(valid_ids)
        tid = valid_ids(i);
        if task_set(tid).is_partition == 1 && isfield(task_set(tid), 'allowed_partition_ratio') && ...
           ~isempty(task_set(tid).allowed_partition_ratio)
            divisible_tasks(end+1) = tid;
        else
            indivisible_tasks(end+1) = tid;
        end
    end
    
    % 3. 優先處理不可分割任務（完成率優化）
    all_tasks_sorted = [indivisible_tasks, divisible_tasks];
    
    % 按增強成本排序
    if ~isempty(all_tasks_sorted)
        costs = [task_set(all_tasks_sorted).Tcost];
        [~, order] = sort(costs, 'ascend');
        all_tasks_sorted = all_tasks_sorted(order);
    end
    
    % 4. 處理每個任務
    for i = 1:length(all_tasks_sorted)
        tid = all_tasks_sorted(i);
        if tid <= 0 || tid > length(task_set)
            continue;
        end
        
        task = task_set(tid);
        if isfield(task, 'subtasks') && ~isempty(task.subtasks)
            sub_idx = find([task.subtasks.es_id] == ES.ID, 1);
            if isempty(sub_idx)
                continue;
            end
            sub = task.subtasks(sub_idx);
            temp_task = task;
            temp_task.workload = sub.workload;
            temp_task.storage = sub.storage;
            temp_task.is_partition = 0;  % treat as indivisible subtask
            [success, best_core, finish_time] = find_optimal_core_for_task(ES, temp_task, time, params);
            if success
                ES.core(best_core).running_time = finish_time;
                exec_time = (sub.workload / ES.core(best_core).rate) * 1000;
                sub.is_done = 1;
                sub.start_time = finish_time - exec_time;
                sub.finish_time = finish_time;
                ES = ES.remove_task(sub.workload, sub.storage, sub.memory, tid, 1);
            else
                sub.is_done = -1;
                ES = ES.remove_task(sub.workload, sub.storage, sub.memory, tid, -1);
            end
            task.subtasks(sub_idx) = sub;
            task_set(tid) = task;
            if all([task.subtasks.is_done] ~= 0) && all([task.subtasks.is_done] ~= -1)
                task_set(tid).is_done = 1;
                task_set(tid).start_time = min([task.subtasks.start_time]);
                task_set(tid).finish_time = max([task.subtasks.finish_time]);
            elseif all([task.subtasks.is_done] ~= 0)
                task_set(tid).is_done = -1;
            end
            continue;
        end

        % 檢查是否為事先確定的可分割任務
        if task_set(tid).is_partition == 1 && isfield(task_set(tid), 'allowed_partition_ratio') ...
                && ~isempty(task_set(tid).allowed_partition_ratio) && ...
                isfield(task_set(tid), 'partition_fixed') && task_set(tid).partition_fixed
            
            % 使用優化的預定義分割策略
            [task_set(tid), ES, partition_success] = execute_optimized_predefined_partition(...
                task_set(tid), ES, time, params);
            if partition_success
                ES = ES.remove_task(task_set(tid).workload, task_set(tid).storage, task_set(tid).memory, tid, 1);
                continue;
            end
        end
        
        % 增強的單核心執行
        [success, best_core, finish_time] = find_optimal_core_for_task(ES, task_set(tid), time, params);
        if success
            ES.core(best_core).running_time = finish_time;
            exec_time = (task_set(tid).workload / ES.core(best_core).rate) * 1000;
            task_set(tid).is_done = 1;
            task_set(tid).start_time = finish_time - exec_time;
            task_set(tid).finish_time = finish_time;
            ES = ES.remove_task(task_set(tid).workload, task_set(tid).storage, task_set(tid).memory, tid, 1);
        else
            % 嘗試任務遷移（如果有備份）
            migration_success = false;
            if isfield(task_set(tid), 'backup_ES_ID') && task_set(tid).backup_ES_ID > 0
                migration_success = attempt_task_migration(task_set, tid, all_ES_set, time, params);
            end
            
            if ~migration_success
                task_set(tid).is_done = -1;
                ES = ES.remove_task(task_set(tid).workload, task_set(tid).storage, task_set(tid).memory, tid, -1);
            end
        end
    end
end

function cost = calculate_enhanced_task_cost(task, params, time, ES)
    % === 增強的任務成本計算 ===
    
    % 基礎時間緊急度
    remain_time = task.expired_time - time;
    if remain_time <= 0
        cost = inf;
        return;
    end
    
    time_urgency = params.alpha / remain_time;
    
    % 分割獎勵
    partition_benefit = 0;
    if task.is_partition == 1 && isfield(task, 'allowed_partition_ratio') && ~isempty(task.allowed_partition_ratio)
        num_parts = length(task.allowed_partition_ratio);
        available_cores = sum([ES.core.running_time] <= time + 10);
        if available_cores >= 2
            partition_benefit = params.beta * (-0.2 * min(num_parts, available_cores));
        end
    end
    
    % 負載影響
    es_load = calculate_ES_load_ratio(ES);
    load_penalty = es_load * params.load_balance_weight;
    
    % 能耗考量
    energy_factor = estimate_energy_cost(task, ES, params) * 0.1;
    
    cost = time_urgency + partition_benefit + load_penalty + energy_factor;
end

function [task, ES, success] = execute_optimized_predefined_partition(task, ES, current_time, params)
    % === 優化的預定義分割執行 ===
    
    success = false;
    
    if ~isfield(task, 'partition_fixed') || ~task.partition_fixed || ...
       ~isfield(task, 'is_partition') || task.is_partition ~= 1 || ...
       ~isfield(task, 'allowed_partition_ratio') || isempty(task.allowed_partition_ratio)
        return;
    end
    
    ratios = task.allowed_partition_ratio;
    num_parts = length(ratios);
    if num_parts < 2 || abs(sum(ratios) - 1.0) > 1e-3
        return;
    end
    
    % 找出可用核心（更嚴格的時間檢查）
    available_cores = [];
    for c = 1:length(ES.core)
        if ES.core(c).running_time <= current_time + 3  % 縮短到3ms以提高精確度
            available_cores(end+1) = c;
        end
    end
    
    if length(available_cores) < 2
        return;
    end
    
    usable_cores_options = [length(available_cores), num_parts];
    usable_cores = min(usable_cores_options);  % 使用向量形式
    
    % 優化的分割開銷計算
    base_overhead = 0.15;  % 基礎開銷
    complexity_overhead = (num_parts - 2) * 0.05;  % 複雜度開銷
    total_overhead = base_overhead + complexity_overhead;
    
    % 檢查分割效益
    comm_overhead_ratio = estimate_communication_overhead(task, usable_cores);
    if comm_overhead_ratio > params.partition_overhead_limit
        return;  % 通信開銷過高，放棄分割
    end
    
    % 計算每片的最優分配
    part_finish = zeros(1, usable_cores);
    start_times = zeros(1, usable_cores);
    
    for i = 1:usable_cores
        core_id = available_cores(i);
        
        % 更智能的工作量分配
        if i <= num_parts
            wl_part = task.workload * ratios(i);
        else
            % 剩餘工作量分配給額外核心
            remain_ratio = sum(ratios(usable_cores+1:end));
            wl_part = task.workload * (remain_ratio / (length(available_cores) - usable_cores + 1));
        end
        
        exec_time = (wl_part / ES.core(core_id).rate) * 1000;
        st = max(current_time, ES.core(core_id).running_time);
        ft = st + exec_time + total_overhead;
        
        if ft > task.expired_time
            return;  % 任一片超時則放棄分割
        end
        
        start_times(i) = st;
        part_finish(i) = ft;
    end
    
    max_ft = max(part_finish);
    
    % 更嚴格的效益檢查
    fastest_core = available_cores(1);
    % === 修正：安全計算最快核心速率 ===
    available_rates = zeros(1, length(available_cores));
    for i = 1:length(available_cores)
        available_rates(i) = ES.core(available_cores(i)).rate;
    end
    fastest_rate = max(available_rates);  % 使用向量形式
    
    fastest_finish = max(ES.core(fastest_core).running_time, current_time) + ...
                     (task.workload / fastest_rate) * 1000;
    
    % 分割必須有顯著效益才執行
    efficiency_threshold = 0.90;  % 分割必須至少快10%
    if max_ft < fastest_finish * efficiency_threshold
        % 更新核心時間
        for i = 1:usable_cores
            c = available_cores(i);
            ES.core(c).running_time = part_finish(i);
        end
        
        task.start_time = min(start_times);
        task.finish_time = max_ft;
        task.is_done = 1;
        task.execution_strategy = sprintf('partition_%d_cores', usable_cores);
        success = true;
    end
end

function [success, best_core, finish_time] = find_optimal_core_for_task(ES, task, time, params)
    % === 尋找最優核心（考慮多重因素）===
    
    success = false;
    best_core = 0;
    finish_time = inf;
    best_score = inf;
    
    for c = 1:length(ES.core)
        avail = max(time, ES.core(c).running_time);
        exec_time = (task.workload / ES.core(c).rate) * 1000;
        ft = avail + exec_time;
        
        if ft > task.expired_time
            continue;  % 無法按時完成
        end
        
        % 多因素評分
        time_score = ft;  % 完成時間越早越好
        wait_score = (avail - time) * 0.5;  % 等待時間懲罰
        
        % === 修正：安全計算核心效率 ===
        all_rates = zeros(1, length(ES.core));
        for i = 1:length(ES.core)
            all_rates(i) = ES.core(i).rate;
        end
        max_rate = max(all_rates);
        core_efficiency = ES.core(c).rate / max_rate;  % 核心效率
        
        total_score = time_score + wait_score - core_efficiency * 100;
        
        if total_score < best_score
            best_score = total_score;
            finish_time = ft;
            best_core = c;
            success = true;
        end
    end
end

function migration_success = attempt_task_migration(task_set, task_id, all_ES_set, time, params)
    % === 嘗試任務遷移 ===
    
    migration_success = false;
    
    if ~isfield(task_set(task_id), 'backup_ES_ID') || task_set(task_id).backup_ES_ID <= 0
        return;
    end
    
    backup_ES_id = task_set(task_id).backup_ES_ID;
    if backup_ES_id > length(all_ES_set)
        return;
    end
    
    backup_ES = all_ES_set(backup_ES_id);
    
    % 檢查備份ES是否能處理
    if (backup_ES.queue_storage + task_set(task_id).storage) <= backup_ES.max_storage && ...
       (backup_ES.queue_memory + task_set(task_id).memory) <= backup_ES.max_memory
        [can_execute, best_core, finish_time] = find_optimal_core_for_task(backup_ES, task_set(task_id), time, params);
        
        if can_execute
            % 執行遷移
            all_ES_set(backup_ES_id) = all_ES_set(backup_ES_id).add_task(...
                task_set(task_id).workload, task_set(task_id).storage, task_set(task_id).memory, task_id);
            
            all_ES_set(backup_ES_id).core(best_core).running_time = finish_time;
            
            task_set(task_id).ES_ID = backup_ES_id;
            task_set(task_id).is_done = 1;
            task_set(task_id).start_time = max(time, all_ES_set(backup_ES_id).core(best_core).running_time);
            task_set(task_id).finish_time = finish_time;
            task_set(task_id).execution_strategy = 'migrated_to_backup';
            
            migration_success = true;
        end
    end
end

function [ES_set, task_set] = global_collaboration_optimization(ES_set, task_set, time, params)
    % === 全域協作優化（高負載時啟動）===
    
    % 找出高負載的ES
    overloaded_ES = [];
    underloaded_ES = [];
    
    for i = 1:length(ES_set)
        load_ratio = calculate_ES_load_ratio(ES_set(i));
        if load_ratio > 0.8
            overloaded_ES(end+1) = i;
        elseif load_ratio < 0.3
            underloaded_ES(end+1) = i;
        end
    end
    
    if isempty(overloaded_ES) || isempty(underloaded_ES)
        return;
    end
    
    % 嘗試負載重分配
    for i = 1:length(overloaded_ES)
        es_id = overloaded_ES(i);
        undone_tasks = ES_set(es_id).undone_task_ID_set;
        
        if isempty(undone_tasks)
            continue;
        end
        
        % 選擇適合遷移的任務（較小且不緊急的）
        migration_candidates = [];
        for j = 1:length(undone_tasks)
            task_id = undone_tasks(j);
            if task_id > 0 && task_id <= length(task_set)
                remain_time = task_set(task_id).expired_time - time;
                if remain_time > 20 && task_set(task_id).workload < 1.5e6  % 不太緊急且較小的任務
                    migration_candidates(end+1) = task_id;
                end
            end
        end
        
        % 嘗試遷移到負載較低的ES
        max_migrations = min(length(migration_candidates), 2);  % 最多遷移2個任務

        for k = 1:min(length(migration_candidates), 2)  % 最多遷移2個任務
            task_id = migration_candidates(k);
            
            for l = 1:length(underloaded_ES)
                target_es_id = underloaded_ES(l);
                
                % 檢查目標ES是否能接受任務
                if (ES_set(target_es_id).queue_storage + task_set(task_id).storage) <= ES_set(target_es_id).max_storage && ...
                   (ES_set(target_es_id).queue_memory + task_set(task_id).memory) <= ES_set(target_es_id).max_memory
                    [can_execute, ~, ~] = find_optimal_core_for_task(ES_set(target_es_id), task_set(task_id), time, params);
                    
                    if can_execute
                        % 執行任務遷移
                        ES_set(es_id) = ES_set(es_id).remove_task(...
                            task_set(task_id).workload, task_set(task_id).storage, task_set(task_id).memory, task_id, 0);
                        
                        ES_set(target_es_id) = ES_set(target_es_id).add_task(...
                            task_set(task_id).workload, task_set(task_id).storage, task_set(task_id).memory, task_id);
                        
                        task_set(task_id).ES_ID = target_es_id;
                        task_set(task_id).execution_strategy = 'load_balanced_migration';
                        
                        break;  % 成功遷移一個任務後跳出
                    end
                end
            end
        end
    end
end