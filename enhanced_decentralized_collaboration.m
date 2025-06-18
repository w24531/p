function [ES_set, task_set] = enhanced_decentralized_collaboration(ES_set, task_set, newTK_set, time, config, divisible_ratio)
    % === Enhanced Decentralized Collaboration ===
    % 強化版的去中心化協作機制，適應不同分割比例和系統負載
    
    if isempty(newTK_set) || isempty(ES_set)
        return;
    end
    
    % 1. 計算全域負載狀況
    total_ratio = 0;
    for i = 1:length(ES_set)
        total_ratio = total_ratio + calculate_ES_load_ratio(ES_set(i));
    end
    system_load_ratio = total_ratio / length(ES_set);
    
    % 2. 根據分割比例和系統負載調整協作策略
    if divisible_ratio == 0  % 0% 可分割 - 專注於提高完成率
        collaboration_mode = 'completion_focused';
        priority_threshold = 0.3;  % 降低門檻，提高協作機率
        load_avoidance_strength = 2.0;  % 強化負載迴避
    elseif divisible_ratio == 0.5  % 50% 可分割 - 平衡策略
        collaboration_mode = 'balanced';
        priority_threshold = 0.5;
        load_avoidance_strength = 1.5;
    else  % 100% 可分割 - 專注於減少延遲
        collaboration_mode = 'latency_focused';
        priority_threshold = 0.7;  % 提高門檻，只有高優先任務才協作
        load_avoidance_strength = 1.0;
    end
    
    % 再根據系統負載進行調整
    if system_load_ratio > config.load_thresholds.high  % 高負載
        priority_threshold = priority_threshold * 0.8;  % 降低協作門檻
        load_avoidance_strength = load_avoidance_strength * 1.3;  % 增加負載迴避
    elseif system_load_ratio < config.load_thresholds.low  % 低負載
        priority_threshold = priority_threshold * 1.2;  % 提高協作門檻
        load_avoidance_strength = load_avoidance_strength * 0.8;  % 減少負載迴避
    end
    
    % 3. 為新任務進行協作式預分配評估
    for i = 1:length(newTK_set)
        task_id = newTK_set(i).ID;
        
        if task_id > length(task_set) || task_id <= 0
            continue;
        end
        
        % 計算任務緊急度
        remain_time = task_set(task_id).expired_time - time;
        if remain_time <= 0
            continue;
        end
        
        urgency_score = 1 / remain_time;
        
        % 根據任務類型調整協作優先權
        if task_set(task_id).is_partition == 1 && ...
           isfield(task_set(task_id), 'allowed_partition_ratio') && ...
           ~isempty(task_set(task_id).allowed_partition_ratio)
            % 可分割任務獲得更高優先權
            partition_bonus = config.partitioning.efficiency_threshold;
            collaboration_priority = urgency_score * (1 + partition_bonus);
        else
            % 不可分割任務
            if divisible_ratio == 0  % 0%分割環境下，提高不可分割任務協作優先權
                collaboration_priority = urgency_score * 1.5;
            else
                collaboration_priority = urgency_score;
            end
        end
        
        % 高優先權任務觸發協作機制
        if collaboration_priority > priority_threshold
            % 尋找最佳協作ES組合
            [best_es_ids, collaboration_benefit] = find_enhanced_collaboration_partners(...
                ES_set, task_set(task_id), collaboration_mode, load_avoidance_strength, config);
            
            if ~isempty(best_es_ids) && collaboration_benefit > config.collaboration.collaboration_threshold
                % 標記為協作任務
                task_set(task_id).collaboration_mode = collaboration_mode;
                task_set(task_id).preferred_ES_ids = best_es_ids;
                task_set(task_id).collaboration_priority = collaboration_priority;
                
                % 記錄協作強度和效益估計
                task_set(task_id).collaboration_benefit = collaboration_benefit;
                task_set(task_id).load_avoidance_factor = load_avoidance_strength;
            end
        end
    end
end

function [best_es_ids, benefit] = find_enhanced_collaboration_partners(ES_set, task, mode, load_avoidance_strength, config)
    % === 強化版：尋找最佳協作夥伴ES ===
    
    best_es_ids = [];
    benefit = 0;
    
    % 針對不同任務類型採用不同策略
    if task.is_partition == 1 && isfield(task, 'allowed_partition_ratio') && ~isempty(task.allowed_partition_ratio)
        % 可分割任務：尋找最適合分割執行的ES組合
        num_parts = length(task.allowed_partition_ratio);
        
        % 根據模式決定協作方式
        switch mode
            case 'latency_focused'
                max_partners = min(num_parts, config.collaboration.max_collaborators);
            case 'balanced'
                max_partners = min(num_parts, floor(config.collaboration.max_collaborators * 0.75));
            case 'completion_focused'
                max_partners = min(num_parts, 2);  % 限制協作者數量
            otherwise
                max_partners = min(num_parts, 3);
        end
        
        % 尋找負載較低的ES作為協作夥伴
        es_scores = zeros(1, length(ES_set));
        for i = 1:length(ES_set)
            % 計算綜合分數（負載、核心可用性）
            load_factor = calculate_ES_load_ratio(ES_set(i));
            load_score = load_factor * load_avoidance_strength;
            
            % 核心可用性評分
            core_availability = 0;
            for c = 1:length(ES_set(i).core)
                if ES_set(i).core(c).running_time < 10  % 10ms內可用
                    core_availability = core_availability + 1;
                end
            end
            core_score = (1 - (core_availability / length(ES_set(i).core))) * 0.5;
            
            es_scores(i) = load_score + core_score;
        end
        
        [~, sorted_indices] = sort(es_scores);
        
        % 選擇分數最低的ES作為協作夥伴
        selected_count = 0;
        for i = 1:length(sorted_indices)
            es_id = sorted_indices(i);
            
            % 檢查該ES是否有足夠容量
            if (ES_set(es_id).queue_storage + task.storage) <= ES_set(es_id).max_storage && ...
               (ES_set(es_id).queue_memory + task.memory) <= ES_set(es_id).max_memory
                best_es_ids(end+1) = es_id;
                selected_count = selected_count + 1;
                
                if selected_count >= max_partners
                    break;
                end
            end
        end
        
        % 計算協作效益
        if length(best_es_ids) >= 2
            % 估算並行執行的時間節省
            single_exec_time = task.workload / ES_set(best_es_ids(1)).core(1).rate;
            efficiency_factor = config.partitioning.efficiency_threshold;  % 並行效率因子
            parallel_exec_time = task.workload / (length(best_es_ids) * ES_set(best_es_ids(1)).core(1).rate * efficiency_factor);
            
            benefit = (single_exec_time - parallel_exec_time) / single_exec_time;
        end
    else
        % 不可分割任務：考慮複製策略（備份方案）
        if mode == 'completion_focused' && load_avoidance_strength > 1.5
            % 計算ES的負載分數
            es_scores = zeros(1, length(ES_set));
            for i = 1:length(ES_set)
                load_factor = calculate_ES_load_ratio(ES_set(i));
                es_scores(i) = load_factor;
            end
            
            [~, sorted_indices] = sort(es_scores);
            
            % 選擇兩個負載最低的ES作為主要和備份
            selected_count = 0;
            for i = 1:min(3, length(sorted_indices))
                es_id = sorted_indices(i);
                
                % 檢查該ES是否有足夠容量
                if (ES_set(es_id).queue_storage + task.storage) <= ES_set(es_id).max_storage && ...
                   (ES_set(es_id).queue_memory + task.memory) <= ES_set(es_id).max_memory
                    best_es_ids(end+1) = es_id;
                    selected_count = selected_count + 1;
                    
                    if selected_count >= 2
                        break;
                    end
                end
            end
            
            % 計算複製策略的效益
            if length(best_es_ids) >= 2
                primary_load = calculate_ES_load_ratio(ES_set(best_es_ids(1)));
                backup_load = calculate_ES_load_ratio(ES_set(best_es_ids(2)));
                
                load_balance_factor = abs(primary_load - backup_load);
                benefit = 0.3 * (1 - primary_load) + 0.2 * (1 - backup_load) + 0.1 * load_balance_factor;
            end
        else
            % 其他模式下，選擇單一最佳ES
            es_scores = zeros(1, length(ES_set));
            for i = 1:length(ES_set)
                load_factor = calculate_ES_load_ratio(ES_set(i));
                es_scores(i) = load_factor;
            end
            
            [~, best_idx] = min(es_scores);
            
            if (ES_set(best_idx).queue_storage + task.storage) <= ES_set(best_idx).max_storage && ...
               (ES_set(best_idx).queue_memory + task.memory) <= ES_set(best_idx).max_memory
                best_es_ids = [best_idx];
                benefit = 0.2 * (1 - es_scores(best_idx));
            end
        end
    end
end