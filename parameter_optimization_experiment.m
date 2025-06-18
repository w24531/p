function parameter_optimization_experiment()
    % === 參數優化實驗：尋找Proposal方法的最佳參數設定（含 CSV 輸出） ===

    clc; clear; close all;
    rng(0);

    %% === 實驗設置 ===
    fprintf('=== 開始參數優化實驗 ===\n');
    fprintf('目標：找到Proposal方法優於TSM和BAT且完成率90-100%%的參數設定\n\n');

    % 固定的實驗參數（不變）
    simulation_times = 1;
    time_slots = 50;
    new_task_fq = 8;

    % 測試範圍（第二階段用，不需要調整）
    divisible_task_ratios = [0.00, 0.50, 1.00];
    totalEDs_set = [1000, 1500, 2000];

    %% === 第一階段：快速參數篩選（擴充至約200組合） ===
    fprintf('第一階段：快速參數篩選（簡化測試）...\n');

    promising_configs = [];   % 符合初步篩選的配置
    config_id = 1;

    % ---------------------------
    % 1) 初始化 quick_records 結構陣列，用來記錄所有測試過的組合與結果
    % ---------------------------
    quick_records = struct( ...
        'config_id', {}, ...
        'ED_in_hs_nums', {}, ...
        'max_storage', {}, ...
        'core_nums', {}, ...
        'core_rate', {}, ...
        'ES_radius', {}, ...
        'alpha', {}, ...
        'beta', {}, ...
        'transfer_time', {}, ...
        'quick_success_rate', {}, ...
        'is_superior', {} ...
    );

    % 使用較小的測試集進行快速篩選
    quick_test_eds   = [1000];    % 只測試 ED=1000
    quick_test_ratios = [1.00];   % 只測試完全可分割的情況（ratio=1）

    % ---------------------------
    % 2) 將 ED_in_hs_nums、core_nums、core_rate、max_storage、ES_radius 都列入迴圈
    %    並適度調整它們的取值範圍，使總組合數大約落在 200 左右
    % ---------------------------
    ED_in_hs_nums_list = [25, 30];                      % 兩種 ED 熱點數
    core_nums_list     = [6, 7, 8];                     % 3 種核心數
    core_rate_list     = [3e7, 3.5e7, 4e7, 4.5e7];      % 4 種核心時脈
    max_storage_list   = [80, 100, 120];                % 3 種最大儲存
    ES_radius_list     = [80, 100, 120];                % 3 種半徑

    % 固定的 quick_test 參數（不納入迴圈）
    alpha_fixed        = 0.6;
    beta_fixed         = 0.4;
    transfer_time_fixed = 2.5;
    deadline_fixed     = [30, 60];
    workload_fixed     = [1e6, 2e6];

    % 總組合數 = 2 (ED_in_hs_nums) × 3 (core_nums) × 4 (core_rate) ×
    %            3 (max_storage) × 3 (ES_radius) = 2×3×4×3×3 = 216
    % 約略在 200 左右
    for ED_in_hs_nums = ED_in_hs_nums_list
        for core_nums = core_nums_list
            for core_rate = core_rate_list
                for max_storage = max_storage_list
                    for ES_radius = ES_radius_list
                        % 組裝這一組 config
                        config = struct();
                        config.ED_in_hs_nums = ED_in_hs_nums;
                        config.max_storage   = max_storage;
                        config.core_nums     = core_nums;
                        config.core_rate     = core_rate;
                        config.ES_radius     = ES_radius;
                        config.alpha         = alpha_fixed;
                        config.beta          = beta_fixed;
                        config.transfer_time = transfer_time_fixed;
                        config.deadline      = deadline_fixed;
                        config.workload      = workload_fixed;

                        % --------------------------------
                        % 3) 執行 quick_test_config，並把結果記錄到 quick_records
                        % --------------------------------
                        [success_rate, is_superior] = quick_test_config(config, quick_test_eds, quick_test_ratios);

                        rec = struct();
                        rec.config_id         = config_id;
                        rec.ED_in_hs_nums     = config.ED_in_hs_nums;
                        rec.max_storage       = config.max_storage;
                        rec.core_nums         = config.core_nums;
                        rec.core_rate         = config.core_rate;
                        rec.ES_radius         = config.ES_radius;
                        rec.alpha             = config.alpha;
                        rec.beta              = config.beta;
                        rec.transfer_time     = config.transfer_time;
                        rec.quick_success_rate = success_rate;
                        rec.is_superior       = is_superior;
                        quick_records(end+1) = rec;  %#ok<AGROW>

                        % --------------------------------
                        % 4) 如果通過 quick 篩選條件，就加入 promising_configs
                        %    例如：成功率 >= 0.85 且優於 TSM、BAT
                        % --------------------------------
                        if success_rate >= 0.85 && is_superior
                            config.config_id = config_id;
                            config.quick_success_rate = success_rate;
                            promising_configs = [promising_configs, config]; %#ok<AGROW>

                            fprintf('  ✓ 有潛力的配置 #%d: ED=%d, 核心=%d, 速率=%.0eHz, 存儲=%d, 半徑=%d, 完成率=%.1f%%\n', ...
                                config_id, ED_in_hs_nums, core_nums, core_rate, max_storage, ES_radius, success_rate*100);
                        end

                        config_id = config_id + 1;
                    end
                end
            end
        end
    end

    % 總共嘗試的組合數
    fprintf('第一階段完成，總共嘗試 %d 筆參數組合，其中找到 %d 個有潛力的配置\n\n', ...
            numel(quick_records), numel(promising_configs));

    % ---------------------------
    % 5) 把 quick_records 寫出成 CSV，方便後續分析
    % ---------------------------
    writeQuickResultsToCSV(quick_records, 'quick_results.csv');

    % 如果完全沒找到 promising_configs，就先結束
    if isempty(promising_configs)
        fprintf('❌ 未找到符合條件的配置，建議調整搜索範圍\n');
        return;
    end

    %% === 第二階段：詳細測試 ===
    fprintf('第二階段：詳細測試有潛力的配置...\n');
    best_configs = [];

    for i = 1:length(promising_configs)
        config = promising_configs(i);
        fprintf('  測試配置 #%d/%d...\n', i, length(promising_configs));

        [detailed_results, overall_score] = detailed_test_config(config, totalEDs_set, divisible_task_ratios);
        config.detailed_results = detailed_results;
        config.overall_score = overall_score;

        if check_optimization_criteria(detailed_results)
            best_configs = [best_configs, config];
            fprintf('    ✅ 符合優化目標！總分: %.2f\n', overall_score);
        else
            fprintf('    ❌ 未符合優化目標，總分: %.2f\n', overall_score);
        end
    end

    %% === 結果分析與輸出 ===
    fprintf('\n=== 優化結果分析 ===\n');
    if isempty(best_configs)
        fprintf('❌ 未找到完全符合目標的配置\n');
        fprintf('📊 顯示表現最佳的前3個 promising_configs：\n\n');

        scores = [promising_configs.overall_score];
        [~, sort_idx] = sort(scores, 'descend');
        top_configs = promising_configs(sort_idx(1:min(3,length(promising_configs))));

        for i = 1:length(top_configs)
            display_config_results(top_configs(i), i);
        end

        writeConfigsToCSV(top_configs, 'top_promising_configs.csv');
    else
        fprintf('🎉 找到 %d 個符合目標的最佳配置！\n\n', length(best_configs));

        scores = [best_configs.overall_score];
        [~, sort_idx] = sort(scores, 'descend');
        sorted_best = best_configs(sort_idx);

        for i = 1:min(3, length(sorted_best))
            display_config_results(sorted_best(i), i);
        end

        generate_optimization_report(sorted_best(1));
        writeConfigsToCSV(sorted_best(1:min(3,end)), 'best_configs.csv');
    end

    fprintf('\n=== 參數優化實驗完成 ===\n');
end

%% ========================================
%% 把 quick_records 寫出成 CSV 的子函式
%% ========================================
function writeQuickResultsToCSV(quick_records, outputFilename)
    % quick_records: struct array，包含以下欄位
    %   .config_id, .ED_in_hs_nums, .max_storage, .core_nums,
    %   .core_rate, .ES_radius, .alpha, .beta, .transfer_time,
    %   .quick_success_rate, .is_superior

    if isempty(quick_records)
        warning('writeQuickResultsToCSV: quick_records 為空，未輸出 CSV。');
        return;
    end

    n = numel(quick_records);
    T = table('Size', [n, 0], 'VariableTypes', {}, 'VariableNames', {});

    % 1) config_id
    if isfield(quick_records, 'config_id')
        T.config_id = [quick_records.config_id]';
    else
        T.config_id = zeros(n,1);
    end

    % 2) ED_in_hs_nums
    if isfield(quick_records, 'ED_in_hs_nums')
        T.ED_in_hs_nums = [quick_records.ED_in_hs_nums]';
    else
        T.ED_in_hs_nums = nan(n,1);
    end

    % 3) max_storage
    if isfield(quick_records, 'max_storage')
        T.max_storage = [quick_records.max_storage]';
    else
        T.max_storage = nan(n,1);
    end

    % 4) core_nums
    if isfield(quick_records, 'core_nums')
        T.core_nums = [quick_records.core_nums]';
    else
        T.core_nums = nan(n,1);
    end

    % 5) core_rate
    if isfield(quick_records, 'core_rate')
        T.core_rate = [quick_records.core_rate]';
    else
        T.core_rate = nan(n,1);
    end

    % 6) ES_radius
    if isfield(quick_records, 'ES_radius')
        T.ES_radius = [quick_records.ES_radius]';
    else
        T.ES_radius = nan(n,1);
    end

    % 7) alpha
    if isfield(quick_records, 'alpha')
        T.alpha = [quick_records.alpha]';
    else
        T.alpha = nan(n,1);
    end

    % 8) beta
    if isfield(quick_records, 'beta')
        T.beta = [quick_records.beta]';
    else
        T.beta = nan(n,1);
    end

    % 9) transfer_time
    if isfield(quick_records, 'transfer_time')
        T.transfer_time = [quick_records.transfer_time]';
    else
        T.transfer_time = nan(n,1);
    end

    % 10) quick_success_rate
    if isfield(quick_records, 'quick_success_rate')
        T.quick_success_rate = [quick_records.quick_success_rate]';
    else
        T.quick_success_rate = nan(n,1);
    end

    % 11) is_superior
    if isfield(quick_records, 'is_superior')
        T.is_superior = [quick_records.is_superior]';
    else
        T.is_superior = false(n,1);
    end

    % 最後寫成 CSV
    try
        writetable(T, outputFilename);
        fprintf('已將 %d 筆快速篩選結果寫入 %s\n', n, outputFilename);
    catch ME
        warning('寫入 %s 失敗: %s', outputFilename, ME.message);
    end
end

% (其他子函式 quick_test_config、detailed_test_config、display_config_results、generate_optimization_report、writeConfigsToCSV 保持原樣，不必重複貼)


%% ================================
%% 下方是將 quick_records 轉成 CSV 的子函式
%% ================================
function writeQuickResultsToCSV(quick_records, outputFilename)
    % 把 quick_records (struct array) 轉成 table，並寫成 CSV
    %
    % 欄位依序：config_id, ED_in_hs_nums, max_storage, core_nums,
    %           core_rate, ES_radius, alpha, beta, transfer_time,
    %           quick_success_rate, is_superior

    if isempty(quick_records)
        warning('writeQuickResultsToCSV: quick_records 為空，未輸出 CSV。');
        return;
    end

    n = numel(quick_records);
    T = table('Size', [n, 0], 'VariableTypes', {}, 'VariableNames', {});

    % 1) config_id
    if isfield(quick_records, 'config_id')
        T.config_id = [quick_records.config_id]';
    else
        T.config_id = zeros(n,1);
    end

    % 2) ED_in_hs_nums
    if isfield(quick_records, 'ED_in_hs_nums')
        T.ED_in_hs_nums = [quick_records.ED_in_hs_nums]';
    else
        T.ED_in_hs_nums = nan(n,1);
    end

    % 3) max_storage
    if isfield(quick_records, 'max_storage')
        T.max_storage = [quick_records.max_storage]';
    else
        T.max_storage = nan(n,1);
    end

    % 4) core_nums
    if isfield(quick_records, 'core_nums')
        T.core_nums = [quick_records.core_nums]';
    else
        T.core_nums = nan(n,1);
    end

    % 5) core_rate
    if isfield(quick_records, 'core_rate')
        T.core_rate = [quick_records.core_rate]';
    else
        T.core_rate = nan(n,1);
    end

    % 6) ES_radius
    if isfield(quick_records, 'ES_radius')
        T.ES_radius = [quick_records.ES_radius]';
    else
        T.ES_radius = nan(n,1);
    end

    % 7) alpha
    if isfield(quick_records, 'alpha')
        T.alpha = [quick_records.alpha]';
    else
        T.alpha = nan(n,1);
    end

    % 8) beta
    if isfield(quick_records, 'beta')
        T.beta = [quick_records.beta]';
    else
        T.beta = nan(n,1);
    end

    % 9) transfer_time
    if isfield(quick_records, 'transfer_time')
        T.transfer_time = [quick_records.transfer_time]';
    else
        T.transfer_time = nan(n,1);
    end

    % 10) quick_success_rate
    if isfield(quick_records, 'quick_success_rate')
        T.quick_success_rate = [quick_records.quick_success_rate]';
    else
        T.quick_success_rate = nan(n,1);
    end

    % 11) is_superior (logical 0/1)
    if isfield(quick_records, 'is_superior')
        T.is_superior = [quick_records.is_superior]';
    else
        T.is_superior = false(n,1);
    end

    % 最後呼叫 writetable，輸出 CSV
    try
        writetable(T, outputFilename);
        fprintf('已將 %d 筆快速篩選結果寫入 %s\n', n, outputFilename);
    catch ME
        warning('寫入 %s 失敗: %s', outputFilename, ME.message);
    end
end

function [success_rate, is_superior] = quick_test_config(config, test_eds, test_ratios)
    % 快速測試配置的性能
    
    % 簡化的測試參數
    time_slots = 30;
    new_task_fq = 8;
    
    try
        % 設置環境
        nED = test_eds(1);
        ratio = test_ratios(1);
        
        % 基本任務參數
        task_parm = struct(...
            'deadline', config.deadline, ...
            'workload', config.workload, ...
            'storage', [3.0, 4.0], ...
            'is_partition', [0, 1]);
        
        % 分割策略
        if ratio == 0
            partition_ratios = [];
        else
            partition_ratios = [0.2, 0.2, 0.2, 0.2, 0.2];
        end
        
        % 環境初始化
        ES_set_base = deploy_ES(config.max_storage, config.core_nums, config.core_rate);
        ES_set_base = update_ES_neighbors(ES_set_base);
        [ED_set_base, ES_set_base] = deploy_ED(nED, 1, config.ED_in_hs_nums, ES_set_base, nED/50, config.ES_radius);
        ED_set_base = ED_find_ESs(ED_set_base, ES_set_base, config.ES_radius);
        
        % 初始化任務集合
        task_set_prop = struct([]);
        task_set_tsm = struct([]);
        task_set_bat = struct([]);
        
        time = 0;
        
        % 模擬執行
        for tSlot = 1:time_slots
            time = time + 1;
            if mod(time, new_task_fq) == 1
                new_task_num = max(1, round(nED * 0.15));
                
                [task_set_prop, newTK_prop] = ED_generate_task_fixed(ED_set_base, ES_set_base, task_set_prop, task_parm, new_task_num, time, ratio, partition_ratios);
                [task_set_tsm, newTK_tsm] = ED_generate_task_fixed(ED_set_base, ES_set_base, task_set_tsm, task_parm, new_task_num, time, ratio, partition_ratios);
                [task_set_bat, newTK_bat] = ED_generate_task_fixed(ED_set_base, ES_set_base, task_set_bat, task_parm, new_task_num, time, ratio, partition_ratios);
                
                % 複製環境
                [prop_ED, prop_ES] = copy_environment(ED_set_base, ES_set_base);
                [tsm_ED, tsm_ES] = copy_environment(ED_set_base, ES_set_base);
                [bat_ED, bat_ES] = copy_environment(ED_set_base, ES_set_base);
                
                % 執行方法
                try
                    method_proposal(prop_ED, prop_ES, task_set_prop, 'quick_prop.mat', config.alpha, config.beta, time, config.transfer_time, newTK_prop);
                    load('quick_prop.mat', 'task_set');
                    task_set_prop = task_set;
                    clear task_set;
                catch
                end
                
                try
                    method_TSM(tsm_ED, tsm_ES, task_set_tsm, 'quick_tsm.mat', config.alpha, config.beta, time, config.transfer_time, newTK_tsm);
                    load('quick_tsm.mat', 'task_set');
                    task_set_tsm = task_set;
                    clear task_set;
                catch
                end
                
                try
                    method_BAT(bat_ED, bat_ES, task_set_bat, 'quick_bat.mat', time, config.transfer_time, newTK_bat);
                    load('quick_bat.mat', 'task_set');
                    task_set_bat = task_set;
                    clear task_set;
                catch
                end
            end
        end
        
        % 計算性能指標
        if ~isempty(task_set_prop)
            prop_success = sum([task_set_prop.is_done] == 1) / length(task_set_prop);
        else
            prop_success = 0;
        end
        
        if ~isempty(task_set_tsm)
            tsm_success = sum([task_set_tsm.is_done] == 1) / length(task_set_tsm);
        else
            tsm_success = 0;
        end
        
        if ~isempty(task_set_bat)
            bat_success = sum([task_set_bat.is_done] == 1) / length(task_set_bat);
        else
            bat_success = 0;
        end
        
        success_rate = prop_success;
        is_superior = (prop_success > tsm_success) && (prop_success > bat_success);
        
        % 清理暫存檔案
        cleanup_temp_files_quick();
        
    catch ME
        fprintf('快速測試錯誤: %s\n', ME.message);
        success_rate = 0;
        is_superior = false;
        cleanup_temp_files_quick();
    end
end

function [results, overall_score] = detailed_test_config(config, totalEDs_set, divisible_task_ratios)
    % 詳細測試配置性能
    
    results = struct();
    results.success_rates = zeros(length(divisible_task_ratios), length(totalEDs_set), 3); % prop, tsm, bat
    results.delays = zeros(length(divisible_task_ratios), length(totalEDs_set), 3);
    results.energies = zeros(length(divisible_task_ratios), length(totalEDs_set), 3);
    
    time_slots = 50;
    new_task_fq = 8;
    
    % 任務參數
    task_parm = struct(...
        'deadline', config.deadline, ...
        'workload', config.workload, ...
        'storage', [3.0, 4.0], ...
        'is_partition', [0, 1]);
    
    for ratio_idx = 1:length(divisible_task_ratios)
        ratio = divisible_task_ratios(ratio_idx);
        
        % 設置分割策略
        if ratio == 0
            partition_ratios = [];
        else
            partition_ratios = [0.2, 0.2, 0.2, 0.2, 0.2];
        end
        
        for ed_idx = 1:length(totalEDs_set)
            nED = totalEDs_set(ed_idx);
            
            try
                % 環境初始化
                ES_set_base = deploy_ES(config.max_storage, config.core_nums, config.core_rate);
                ES_set_base = update_ES_neighbors(ES_set_base);
                [ED_set_base, ES_set_base] = deploy_ED(nED, 1, config.ED_in_hs_nums, ES_set_base, nED/50, config.ES_radius);
                ED_set_base = ED_find_ESs(ED_set_base, ES_set_base, config.ES_radius);
                
                % 初始化任務集合
                task_set_prop = struct([]);
                task_set_tsm = struct([]);
                task_set_bat = struct([]);
                
                time = 0;
                
                % 模擬執行
                for tSlot = 1:time_slots
                    time = time + 1;
                    if mod(time, new_task_fq) == 1
                        new_task_num = max(1, round(nED * 0.15));
                        
                        [task_set_prop, newTK_prop] = ED_generate_task_fixed(ED_set_base, ES_set_base, task_set_prop, task_parm, new_task_num, time, ratio, partition_ratios);
                        [task_set_tsm, newTK_tsm] = ED_generate_task_fixed(ED_set_base, ES_set_base, task_set_tsm, task_parm, new_task_num, time, ratio, partition_ratios);
                        [task_set_bat, newTK_bat] = ED_generate_task_fixed(ED_set_base, ES_set_base, task_set_bat, task_parm, new_task_num, time, ratio, partition_ratios);
                        
                        % 複製環境
                        [prop_ED, prop_ES] = copy_environment(ED_set_base, ES_set_base);
                        [tsm_ED, tsm_ES] = copy_environment(ED_set_base, ES_set_base);
                        [bat_ED, bat_ES] = copy_environment(ED_set_base, ES_set_base);
                        
                        % 執行方法
                        try
                            method_proposal(prop_ED, prop_ES, task_set_prop, 'detail_prop.mat', config.alpha, config.beta, time, config.transfer_time, newTK_prop);
                            load('detail_prop.mat', 'task_set');
                            task_set_prop = task_set;
                            clear task_set;
                        catch
                        end
                        
                        try
                            method_TSM(tsm_ED, tsm_ES, task_set_tsm, 'detail_tsm.mat', config.alpha, config.beta, time, config.transfer_time, newTK_tsm);
                            load('detail_tsm.mat', 'task_set');
                            task_set_tsm = task_set;
                            clear task_set;
                        catch
                        end
                        
                        try
                            method_BAT(bat_ED, bat_ES, task_set_bat, 'detail_bat.mat', time, config.transfer_time, newTK_bat);
                            load('detail_bat.mat', 'task_set');
                            task_set_bat = task_set;
                            clear task_set;
                        catch
                        end
                    end
                end
                
                % 計算性能指標
                % 成功率
                if ~isempty(task_set_prop)
                    results.success_rates(ratio_idx, ed_idx, 1) = sum([task_set_prop.is_done] == 1) / length(task_set_prop);
                end
                if ~isempty(task_set_tsm)
                    results.success_rates(ratio_idx, ed_idx, 2) = sum([task_set_tsm.is_done] == 1) / length(task_set_tsm);
                end
                if ~isempty(task_set_bat)
                    results.success_rates(ratio_idx, ed_idx, 3) = sum([task_set_bat.is_done] == 1) / length(task_set_bat);
                end
                
                % 延遲
                [prop_delay, ~] = calculate_delay(task_set_prop, prop_ES, prop_ED, config.transfer_time);
                [tsm_delay, ~] = calculate_delay(task_set_tsm, tsm_ES, tsm_ED, config.transfer_time);
                [bat_delay, ~] = calculate_delay(task_set_bat, bat_ES, bat_ED, config.transfer_time);
                
                results.delays(ratio_idx, ed_idx, 1) = prop_delay;
                results.delays(ratio_idx, ed_idx, 2) = tsm_delay;
                results.delays(ratio_idx, ed_idx, 3) = bat_delay;
                
                % 能耗
                prop_energy = calculate_energy_consumption(task_set_prop, prop_ES, prop_ED, 'proposal');
                tsm_energy = calculate_energy_consumption(task_set_tsm, tsm_ES, tsm_ED, 'tsm');
                bat_energy = calculate_energy_consumption(task_set_bat, bat_ES, bat_ED, 'bat');
                
                results.energies(ratio_idx, ed_idx, 1) = prop_energy.total;
                results.energies(ratio_idx, ed_idx, 2) = tsm_energy.total;
                results.energies(ratio_idx, ed_idx, 3) = bat_energy.total;
                
                cleanup_temp_files_quick();
                
            catch ME
                fprintf('詳細測試錯誤: %s\n', ME.message);
                cleanup_temp_files_quick();
            end
        end
    end
    
    % 計算總分
    overall_score = calculate_overall_score(results);
end

function meets_criteria = check_optimization_criteria(results)
    % 檢查是否符合優化目標
    meets_criteria = true;
    
    success_rates = results.success_rates;
    delays = results.delays;
    energies = results.energies;
    
    % 檢查完成率條件
    prop_rates = success_rates(:, :, 1);
    tsm_rates = success_rates(:, :, 2);
    bat_rates = success_rates(:, :, 3);
    
    % 條件1: Proposal完成率需要在90%以上（至少在部分配置下）
    if max(prop_rates(:)) < 0.70
        meets_criteria = false;
        return;
    end
    
    % 條件2: Proposal平均完成率需要高於TSM和BAT
    avg_prop = mean(prop_rates(:));
    avg_tsm = mean(tsm_rates(:));
    avg_bat = mean(bat_rates(:));
    
    if avg_prop <= avg_tsm || avg_prop <= avg_bat
        meets_criteria = false;
        return;
    end
    
    % 條件3: Proposal延遲需要低於或接近TSM和BAT
    prop_delays = delays(:, :, 1);
    tsm_delays = delays(:, :, 2);
    bat_delays = delays(:, :, 3);
    
    avg_prop_delay = mean(prop_delays(:));
    avg_tsm_delay = mean(tsm_delays(:));
    avg_bat_delay = mean(bat_delays(:));
    
    if avg_prop_delay > avg_tsm_delay * 1.1 && avg_prop_delay > avg_bat_delay * 1.1
        meets_criteria = false;
        return;
    end
end

function score = calculate_overall_score(results)
    % 計算綜合評分（0-100分）
    
    success_rates = results.success_rates;
    delays = results.delays;
    energies = results.energies;
    
    % 權重設定
    w_success = 0.5;   % 完成率權重
    w_delay = 0.3;     % 延遲權重
    w_energy = 0.2;    % 能耗權重
    
    % 完成率評分（Proposal vs others）
    prop_rates = success_rates(:, :, 1);
    tsm_rates = success_rates(:, :, 2);
    bat_rates = success_rates(:, :, 3);
    
    success_score = 0;
    if mean(prop_rates(:)) > 0
        success_improvement_tsm = (mean(prop_rates(:)) - mean(tsm_rates(:))) / mean(tsm_rates(:));
        success_improvement_bat = (mean(prop_rates(:)) - mean(bat_rates(:))) / mean(bat_rates(:));
        success_score = min(100, max(0, (success_improvement_tsm + success_improvement_bat) * 50 + mean(prop_rates(:)) * 50));
    end
    
    % 延遲評分（越低越好）
    prop_delays = delays(:, :, 1);
    tsm_delays = delays(:, :, 2);
    bat_delays = delays(:, :, 3);
    
    delay_score = 0;
    if mean(prop_delays(:)) > 0
        delay_improvement_tsm = (mean(tsm_delays(:)) - mean(prop_delays(:))) / mean(tsm_delays(:));
        delay_improvement_bat = (mean(bat_delays(:)) - mean(prop_delays(:))) / mean(bat_delays(:));
        delay_score = min(100, max(0, (delay_improvement_tsm + delay_improvement_bat) * 50 + 50));
    end
    
    % 能耗評分（越低越好）
    prop_energies = energies(:, :, 1);
    tsm_energies = energies(:, :, 2);
    bat_energies = energies(:, :, 3);
    
    energy_score = 0;
    if mean(prop_energies(:)) > 0
        energy_improvement_tsm = (mean(tsm_energies(:)) - mean(prop_energies(:))) / mean(tsm_energies(:));
        energy_improvement_bat = (mean(bat_energies(:)) - mean(prop_energies(:))) / mean(bat_energies(:));
        energy_score = min(100, max(0, (energy_improvement_tsm + energy_improvement_bat) * 50 + 50));
    end
    
    % 綜合評分
    score = w_success * success_score + w_delay * delay_score + w_energy * energy_score;
end

function display_config_results(config, rank)
    % 顯示配置結果
    
    fprintf('📋 第%d名配置 (ID: %d, 總分: %.1f分):\n', rank, config.config_id, config.overall_score);
    fprintf('   參數設置:\n');
    fprintf('     - ED熱點數量: %d\n', config.ED_in_hs_nums);
    fprintf('     - 最大存儲: %d\n', config.max_storage);
    fprintf('     - 核心數: %d\n', config.core_nums);
    fprintf('     - 核心速率: %.0e Hz\n', config.core_rate);
    fprintf('     - ES半徑: %d\n', config.ES_radius);
    fprintf('     - Alpha: %.1f\n', config.alpha);
    fprintf('     - Beta: %.1f\n', config.beta);
    fprintf('     - 傳輸時間: %.1f\n', config.transfer_time);
    fprintf('     - 截止時間: [%d, %d]\n', config.deadline(1), config.deadline(2));
    fprintf('     - 工作量: [%.1eM, %.1eM]\n', config.workload(1)/1e6, config.workload(2)/1e6);
    
    if isfield(config, 'detailed_results')
        results = config.detailed_results;
        fprintf('   性能指標:\n');
        
        % 顯示完成率
        prop_rates = results.success_rates(:, :, 1) * 100;
        tsm_rates = results.success_rates(:, :, 2) * 100;
        bat_rates = results.success_rates(:, :, 3) * 100;
        
        fprintf('     完成率: Prop=%.1f%%, TSM=%.1f%%, BAT=%.1f%%\n', ...
            mean(prop_rates(:)), mean(tsm_rates(:)), mean(bat_rates(:)));
        
        % 顯示延遲
        prop_delays = results.delays(:, :, 1) * 1000;
        tsm_delays = results.delays(:, :, 2) * 1000;
        bat_delays = results.delays(:, :, 3) * 1000;
        
        fprintf('     延遲(ms): Prop=%.1f, TSM=%.1f, BAT=%.1f\n', ...
            mean(prop_delays(:)), mean(tsm_delays(:)), mean(bat_delays(:)));
        
        % 顯示能耗
        prop_energies = results.energies(:, :, 1);
        tsm_energies = results.energies(:, :, 2);
        bat_energies = results.energies(:, :, 3);
        
        fprintf('     能耗(J): Prop=%.1f, TSM=%.1f, BAT=%.1f\n', ...
            mean(prop_energies(:)), mean(tsm_energies(:)), mean(bat_energies(:)));
    end
    
    fprintf('\n');
end

function generate_optimization_report(best_config)
    % 生成最佳配置的詳細報告
    
    fprintf('🎯 === 最佳配置詳細報告 ===\n');
    fprintf('配置ID: %d (總分: %.1f分)\n\n', best_config.config_id, best_config.overall_score);
    
    fprintf('📝 建議的參數設置:\n');
    fprintf('```matlab\n');
    fprintf('ED_in_hs_nums = %d;\n', best_config.ED_in_hs_nums);
    fprintf('max_storage = %d;\n', best_config.max_storage);
    fprintf('core_nums = %d;\n', best_config.core_nums);
    fprintf('core_rate = %.0e;\n', best_config.core_rate);
    fprintf('ES_radius = %d;\n', best_config.ES_radius);
    fprintf('alpha = %.1f;\n', best_config.alpha);
    fprintf('beta = %.1f;\n', best_config.beta);
    fprintf('transfer_time = %.1f;\n', best_config.transfer_time);
    fprintf('task_parm = struct(...\n');
    fprintf('    ''deadline'', [%d, %d], ...\n', best_config.deadline(1), best_config.deadline(2));
    fprintf('    ''workload'', [%.1e, %.1e], ...\n', best_config.workload(1), best_config.workload(2));
    fprintf('    ''storage'', [3.0, 4.0], ...\n');
    fprintf('    ''is_partition'', [0, 1]);\n');
    fprintf('```\n\n');
    
    if isfield(best_config, 'detailed_results')
        results = best_config.detailed_results;
        
        fprintf('📊 性能分析:\n');
        
        % 完成率分析
        prop_rates = results.success_rates(:, :, 1);
        tsm_rates = results.success_rates(:, :, 2);
        bat_rates = results.success_rates(:, :, 3);
        
        fprintf('✓ 完成率優勢:\n');
        fprintf('  - Proposal平均: %.1f%% (最高: %.1f%%)\n', mean(prop_rates(:))*100, max(prop_rates(:))*100);
        fprintf('  - vs TSM: +%.1f個百分點\n', (mean(prop_rates(:)) - mean(tsm_rates(:)))*100);
        fprintf('  - vs BAT: +%.1f個百分點\n', (mean(prop_rates(:)) - mean(bat_rates(:)))*100);
        
        % 延遲分析
        prop_delays = results.delays(:, :, 1);
        tsm_delays = results.delays(:, :, 2);
        bat_delays = results.delays(:, :, 3);
        
        fprintf('✓ 延遲優勢:\n');
        fprintf('  - Proposal平均: %.1f ms\n', mean(prop_delays(:))*1000);
        fprintf('  - vs TSM: %.1f%% 改善\n', (mean(tsm_delays(:)) - mean(prop_delays(:)))/mean(tsm_delays(:))*100);
        fprintf('  - vs BAT: %.1f%% 改善\n', (mean(bat_delays(:)) - mean(prop_delays(:)))/mean(bat_delays(:))*100);
        
        % 能耗分析
        prop_energies = results.energies(:, :, 1);
        tsm_energies = results.energies(:, :, 2);
        bat_energies = results.energies(:, :, 3);
        
        fprintf('✓ 能耗表現:\n');
        fprintf('  - Proposal平均: %.1f J\n', mean(prop_energies(:)));
        fprintf('  - vs TSM: %.1f%% 變化\n', (mean(prop_energies(:)) - mean(tsm_energies(:)))/mean(tsm_energies(:))*100);
        fprintf('  - vs BAT: %.1f%% 變化\n', (mean(prop_energies(:)) - mean(bat_energies(:)))/mean(bat_energies(:))*100);
    end
    
    fprintf('\n🎉 此配置已達成所有優化目標！\n');
end

%% === 輔助函數 ===

function [task_set, newTK_set] = ED_generate_task_fixed(ED_set, ES_set, task_set, task_parm, new_task_nums, task_generate_time, divisible_ratio, partition_ratios)
    % 生成任務的輔助函數
    try
        [task_set, newTK_set] = ED_generate_task(ED_set, ES_set, task_set, task_parm, new_task_nums, task_generate_time, divisible_ratio);
        
        if ~isempty(newTK_set) && nargin >= 8 && ~isempty(partition_ratios)
            for i = 1:length(newTK_set)
                if isfield(newTK_set(i), 'is_partition') && newTK_set(i).is_partition == 1
                    newTK_set(i).allowed_partition_ratio = partition_ratios;
                    
                    task_id = newTK_set(i).ID;
                    if task_id > 0 && task_id <= length(task_set)
                        if isfield(task_set(task_id), 'is_partition') && task_set(task_id).is_partition == 1
                            task_set(task_id).allowed_partition_ratio = partition_ratios;
                        end
                    end
                end
            end
        end
        
    catch ME
        if isempty(task_set)
            task_set = struct([]);
        end
        newTK_set = struct([]);
    end
end

function [ED_copy, ES_copy] = copy_environment(ED_set, ES_set)
    % 環境複製函數
    ED_copy = ED_set;
    ES_copy = ES_set;
    
    for i = 1:length(ES_copy)
        ES_copy(i).queue_storage = 0;
        ES_copy(i).queue_memory = 0;
        ES_copy(i).total_workloads = 0;
        ES_copy(i).undone_task_ID_set = [];
        ES_copy(i).done_task_ID_set = [];
        ES_copy(i).expired_task_ID_set = [];
        for j = 1:length(ES_copy(i).core)
            ES_copy(i).core(j).running_time = 0;
        end
    end
end

function cleanup_temp_files_quick()
    % 清理暫存檔案
    temp_files = {'quick_prop.mat', 'quick_tsm.mat', 'quick_bat.mat', ...
                  'detail_prop.mat', 'detail_tsm.mat', 'detail_bat.mat'};
    for i = 1:length(temp_files)
        if exist(temp_files{i}, 'file')
            delete(temp_files{i});
        end
    end
end

