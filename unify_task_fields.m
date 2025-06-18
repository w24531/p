function result = unify_task_fields(tk, task_set)
    % 修正版：解決陣列維度不一致問題
    
    % 如果兩個都為空，返回空
    if isempty(task_set) && isempty(tk)
        result = struct();
        return;
    end
    
    % 如果 task_set 為空，直接返回 tk
    if isempty(task_set)
        result = tk;
        return;
    end
    
    % 如果 tk 為空，返回 task_set
    if isempty(tk)
        result = task_set;
        return;
    end

    try
        % 確保兩個都是結構體
        if ~isstruct(tk) || ~isstruct(task_set)
            result = tk;
            return;
        end
        
        % 獲取所有欄位名稱
        tk_fields = fieldnames(tk);
        task_fields = fieldnames(task_set);
        all_fields = unique([tk_fields; task_fields]);
        
        % 為 tk 添加缺失的欄位
        for i = 1:numel(tk)
            for j = 1:length(all_fields)
                field_name = all_fields{j};
                if ~isfield(tk(i), field_name)
                    tk(i).(field_name) = get_default_value(field_name);
                end
            end
        end
        
        % 重新排列欄位順序以匹配
        result_tk = struct();
        for i = 1:numel(tk)
            for j = 1:length(all_fields)
                field_name = all_fields{j};
                result_tk(i).(field_name) = tk(i).(field_name);
            end
        end
        
        result = result_tk;
        
    catch ME
        warning('unify_task_fields發生錯誤: %s', ME.message);
        result = tk;
    end
end

function val = get_default_value(field)
    % 根據欄位名稱返回合適的預設值
    switch lower(field)
        case {'start_time', 'finish_time', 'assigned_time', 'enter_time'}
            val = -1;
        case {'retry_count', 'last_es_id', 'fwd_es_id', 'es_id', 'id', 'ed_id'}
            val = 0;
        case {'candidate_es', 'route', 'es_path', 'allowed_partition_ratio', 'subtasks'}
            val = [];
        case {'status'}
            val = '';
        case {'transfer_time', 'tcost', 'priority_value', 'workload', 'storage', 'memory'}
            val = 0;
        case {'is_done', 'is_partition'}
            val = 0;
        case {'expired_time', 'generate_time'}
            val = 0;
        otherwise
            val = [];
    end
end