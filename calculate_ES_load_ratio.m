function load_ratio = calculate_ES_load_ratio(ES)
    % === 計算 ES 負載比例 ===
    % 將計算與儲存占用分開計算，避免單位混用

    % 工作量佔用比例
    workload_ratio = 0;
    if isfield(ES, 'total_workloads') && isfield(ES, 'core_rate') && isfield(ES, 'core_nums')
        capacity = ES.core_rate * ES.core_nums;
        workload_ratio = ES.total_workloads / max(capacity, 1);
    end

    % 儲存佔用比例
    storage_ratio = 0;
    if isfield(ES, 'queue_storage') && isfield(ES, 'max_storage')
        storage_ratio = ES.queue_storage / max(ES.max_storage, 1);
    end

    % 記憶體佔用比例
    memory_ratio = 0;
    if isfield(ES, 'queue_memory') && isfield(ES, 'max_memory')
        memory_ratio = ES.queue_memory / max(ES.max_memory, 1);
    end

    % 綜合負載比例
    load_ratio = (workload_ratio + storage_ratio + memory_ratio) / 3;
    load_ratio = max(0, min(load_ratio, 1.0));
end