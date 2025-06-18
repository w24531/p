function [ES_set, task_set] = decentralized_collaboration(ES_set, task_set, new_tasks, time)
    % 實現論文中的去中心化協作機制
    % 每個ES獨立決策並與鄰居協商
    
    if isempty(new_tasks)
        return;
    end
    
    % 第一階段：各ES獨立評估本地資源狀況
    local_decisions = cell(length(ES_set), 1);
    
    for es_id = 1:length(ES_set)
        local_decisions{es_id} = evaluate_local_capacity(ES_set(es_id), new_tasks, time);
    end
    
    % 第二階段：與鄰居ES進行協商
    for es_id = 1:length(ES_set)
        if ~isempty(ES_set(es_id).neighbor_ES)
            % 獲取鄰居的決策信息
            neighbor_info = collect_neighbor_info(ES_set, es_id, local_decisions);
            
            % 基於鄰居信息調整決策
            local_decisions{es_id} = negotiate_with_neighbors(ES_set(es_id), ...
                local_decisions{es_id}, neighbor_info, time);
        end
    end
    
    % 第三階段：應用協商結果
    for es_id = 1:length(ES_set)
        [ES_set(es_id), task_set] = apply_decentralized_decisions(ES_set(es_id), ...
            task_set, local_decisions{es_id}, time);
    end
end

function local_capacity = evaluate_local_capacity(ES, tasks, time)
    % 評估ES的本地容量和可接受的任務
    local_capacity = struct();
    local_capacity.es_id = ES.ID;
    local_capacity.available_storage = ES.max_storage - ES.queue_storage;
    local_capacity.available_memory  = ES.max_memory - ES.queue_memory;
    local_capacity.core_availability = zeros(1, length(ES.core));
    
    for c = 1:length(ES.core)
        local_capacity.core_availability(c) = max(0, time - ES.core(c).running_time);
    end
    
    % 評估可接受的任務
    local_capacity.acceptable_tasks = [];
    for i = 1:length(tasks)
        if tasks(i).storage <= local_capacity.available_storage
            % 簡單的接受度評估
            min_exec_time = tasks(i).workload / max([ES.core.rate]);
            if (tasks(i).expired_time - time) > min_exec_time
                local_capacity.acceptable_tasks(end+1) = tasks(i).ID;
            end
        end
    end
    
    local_capacity.load_ratio = calculate_ES_load_ratio(ES);
end

function neighbor_info = collect_neighbor_info(ES_set, es_id, local_decisions)
    % 收集鄰居ES的資源信息
    neighbor_info = [];
    
    if isfield(ES_set(es_id), 'neighbor_ES') && ~isempty(ES_set(es_id).neighbor_ES)
        for i = 1:length(ES_set(es_id).neighbor_ES)
            nb_id = ES_set(es_id).neighbor_ES(i);
            if nb_id > 0 && nb_id <= length(ES_set)
                neighbor_info(end+1) = local_decisions{nb_id};
            end
        end
    end
end

function adjusted_decision = negotiate_with_neighbors(ES, local_decision, neighbor_info, time)
    % 基於鄰居信息調整本地決策
    adjusted_decision = local_decision;
    
    if isempty(neighbor_info)
        return;
    end
    
    % 計算平均鄰居負載
    neighbor_loads = [neighbor_info.load_ratio];
    avg_neighbor_load = mean(neighbor_loads);
    
    % 如果本地負載顯著高於鄰居，減少接受任務
    if local_decision.load_ratio > avg_neighbor_load * 1.3
        % 減少50%的接受任務
        num_reduce = ceil(length(local_decision.acceptable_tasks) * 0.5);
        if num_reduce > 0
            adjusted_decision.acceptable_tasks = ...
                local_decision.acceptable_tasks(1:end-num_reduce);
        end
    end
    
    % 如果本地負載顯著低於鄰居，可以考慮接受更多任務
    if local_decision.load_ratio < avg_neighbor_load * 0.7
        adjusted_decision.cooperation_bonus = 0.9; % 給予合作獎勵
    else
        adjusted_decision.cooperation_bonus = 1.0;
    end
end

function [ES, task_set] = apply_decentralized_decisions(ES, task_set, decision, time)
    % 應用去中心化決策結果
    
    for i = 1:length(decision.acceptable_tasks)
        task_id = decision.acceptable_tasks(i);
        
        if task_id <= 0 || task_id > length(task_set)
            continue;
        end
        
        % 檢查任務是否已被分配
        if task_set(task_id).is_done ~= 0 || ...
           (isfield(task_set(task_id), 'ES_ID') && task_set(task_id).ES_ID > 0)
            continue;
        end
        
        % 應用協作獎勵到成本計算
        if isfield(decision, 'cooperation_bonus')
            task_set(task_id).cooperation_factor = decision.cooperation_bonus;
        end
        
        % 分配任務到此ES
        ES = ES.add_task(task_set(task_id).workload, task_set(task_id).storage, task_set(task_id).memory, task_id);
        task_set(task_id).ES_ID = ES.ID;
        if ~isfield(task_set(task_id), 'ES_path')
            task_set(task_id).ES_path = [];
        end
        task_set(task_id).ES_path(end+1) = ES.ID;
        task_set(task_id).enter_time = time;
    end
end