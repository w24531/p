% 在延遲計算開始前添加檢查
function [avg_delay, delays] = calculate_delay(task_set, ES_set, ED_set, transfer_time)
    % === 統一延遲計算：確保所有方法使用相同邏輯 ===
    
    delays = [];
    
    % 確保所有方法使用相同的基礎參數
    BASE_UPLOAD_RATE = 1000000;     % 1Mbps
    BASE_DOWNLOAD_RATE = 1500000;   % 1.5Mbps
    
    % 系統負載檢測（統一標準）
    system_load_ratio = calculate_system_load_ratio(ES_set);
    
    for i = 1:length(task_set)
        if task_set(i).is_done == 1
            % 傳輸延遲計算（統一公式）
            upload_data_size = 800 + task_set(i).workload * 0.00004;   
            download_data_size = 400 + task_set(i).storage * 0.05;
            
            congestion_factor = 1 + system_load_ratio * 0.25; 
            network_efficiency = 1.0;
            
            actual_upload_rate = BASE_UPLOAD_RATE * network_efficiency / congestion_factor;
            actual_download_rate = BASE_DOWNLOAD_RATE * network_efficiency / congestion_factor;
            
            tx_delay = upload_data_size / actual_upload_rate;
            rx_delay = download_data_size / actual_download_rate;
            
            % 處理延遲計算（移除方法特定的優化）
            if isfield(task_set(i), 'ES_ID') && task_set(i).ES_ID > 0 && task_set(i).ES_ID <= length(ES_set)
                es_id = task_set(i).ES_ID;
                
                if isfield(task_set(i), 'finish_time') && isfield(task_set(i), 'start_time') && ...
                   task_set(i).finish_time > 0 && task_set(i).start_time > 0
                    base_proc_time = (task_set(i).finish_time - task_set(i).start_time) / 1000;
                else
                    avg_core_rate = ES_set(es_id).core_rate;
                    base_proc_time = task_set(i).workload / avg_core_rate;
                end
                
                % 統一的處理延遲計算
                es_load_ratio = calculate_ES_load_ratio(ES_set(es_id));
                num_concurrent_tasks = length(ES_set(es_id).undone_task_ID_set);
                
                queue_delay = base_proc_time * es_load_ratio * (0.5 + num_concurrent_tasks * 0.05);
                contention_delay = base_proc_time * 0.1 * es_load_ratio;
                context_switch_delay = 0.001 * (0.8 + num_concurrent_tasks * 0.05);
                
                proc_delay = base_proc_time + queue_delay + contention_delay + context_switch_delay;
                
            else
                proc_delay = task_set(i).workload / 5e7;
            end
            
            % 分割任務的並行處理（統一加速比，不區分方法）
            if isfield(task_set(i), 'is_partition') && task_set(i).is_partition == 1
                if isfield(task_set(i), 'allowed_partition_ratio') && ~isempty(task_set(i).allowed_partition_ratio)
                    num_parts = length(task_set(i).allowed_partition_ratio);
                    
                    % 統一的並行加速比（不因方法而異）
                    parallel_efficiency = 0.85;
                    speedup = min(num_parts * parallel_efficiency, num_parts * 0.9);
                    partition_overhead = 0.0006 * num_parts;
                    
                    original_proc_delay = proc_delay;
                    proc_delay = (proc_delay / speedup) + partition_overhead;
                    proc_delay = max(proc_delay, original_proc_delay * 0.1);
                end
            end
            
            % 其餘計算保持不變...
            forward_delay = 0;
            if isfield(task_set(i), 'ES_path') && length(task_set(i).ES_path) > 1
                num_hops = length(task_set(i).ES_path) - 1;
                forward_delay = num_hops * transfer_time / 1200;
            end
            
            total_delay = tx_delay + proc_delay + rx_delay + forward_delay;
            total_delay = max(total_delay, 0.001);
            total_delay = min(total_delay, 1.0);
            
            delays(end+1) = total_delay;
        end
    end
    
    if ~isempty(delays)
        avg_delay = mean(delays);
    else
        avg_delay = 0.005;
    end
end

function load_ratio = calculate_system_load_ratio(ES_set)
    % === 計算系統負載比例 ===
    if isempty(ES_set)
        load_ratio = 0;
        return;
    end

    total_ratio = 0;
    for i = 1:length(ES_set)
        total_ratio = total_ratio + calculate_ES_load_ratio(ES_set(i));
    end

    load_ratio = total_ratio / length(ES_set);
end