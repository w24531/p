clc; clear; close all;
rng(0);

%% === 載入優化配置 ===
PROPOSAL_CONFIG = proposal_optimization_config();
fprintf('已載入 Proposal 優化配置 v%s\n', PROPOSAL_CONFIG.version);

%% === 優化參數設置：強化分割效果與方法差異 ===
simulation_times = 3;
time_slots       = 100;
run_algo_fq      = 10;
new_task_fq      = 8;
totalEDs_set     = [500, 1000, 1500, 2000, 2500, 3000];

% Partition ratios for different percentages
divisible_task_ratios = [0.00, 0.50, 1.00];
ED_is_uniform = 1;
ED_in_hs_nums = 30;
max_storage   = 100;

% Modified parameters to create a more challenging environment
core_nums     = 8;
core_rate     = 4e7;
ES_radius     = 100;

% === 動態調整參數策略 ===
% 根據設備密度自適應調整
max_eds = max(totalEDs_set);
if max_eds >= PROPOSAL_CONFIG.scenarios.high_density.ed_threshold
    fprintf('檢測到高密度場景 (>=%d EDs)，應用高密度優化策略\n', PROPOSAL_CONFIG.scenarios.high_density.ed_threshold);
    scenario_config = PROPOSAL_CONFIG.scenarios.high_density;
else
    fprintf('檢測到低密度場景 (<=%d EDs)，應用低密度優化策略\n', PROPOSAL_CONFIG.scenarios.low_density.ed_threshold);
    scenario_config = PROPOSAL_CONFIG.scenarios.low_density;
end

% Parameters for cost function - 將根據分割比例動態調整
alpha = 0.6;    % Time urgency weight (基礎值)
beta  = 0.4;    % Partition benefit weight (基礎值)
transfer_time = 2.5;

% Task parameters with more challenging workload
task_parm = struct(...
    'deadline',   [30, 60],     ... % Shorter deadlines
    'workload',   [1e6, 2e6],   ... % Higher workload
    'storage',    [3.0, 4.0],   ... % Same storage
    'is_partition',[0, 1]);

%% === 統計容器初始化 ===
for ratio_idx = 1:length(divisible_task_ratios)
    for ed_idx = 1:length(totalEDs_set)
        for f={'tsm','prop','bat'}
            % 完成率統計
            stats.(f{1}){ratio_idx, ed_idx} = [];
            % 延遲統計
            delay_stats.(f{1}){ratio_idx, ed_idx} = [];
            % 能耗統計
            energy_stats.(f{1}){ratio_idx, ed_idx} = [];
            energy_per_task.(f{1}){ratio_idx, ed_idx} = [];
            % 成功任務數統計
            success_stats.(f{1}){ratio_idx, ed_idx} = [];
        end
    end
end

%% === 主模擬循環 ===

% 先初始化那四個向量
total_tasks_success_prop   = zeros(1, length(divisible_task_ratios));
total_tasks_success_tsm    = zeros(1, length(divisible_task_ratios));
total_tasks_success_bat    = zeros(1, length(divisible_task_ratios));
total_tasks_generated      = zeros(1, length(divisible_task_ratios));

fprintf('=== 整合比較：TSM vs Enhanced Proposal vs BAT（完成率+延遲+能耗）===\n');

for sim = 1:simulation_times
    fprintf('\n--- 模擬回合: %d/%d ---\n', sim, simulation_times);
    
    for ratio_idx = 1:length(divisible_task_ratios)
        % --- (1) 為本次 ratio_idx 準備暫存陣列 ---
        tmp_prop_success = zeros(1, length(totalEDs_set));
        tmp_tsm_success  = zeros(1, length(totalEDs_set));
        tmp_bat_success  = zeros(1, length(totalEDs_set));
        tmp_generated    = zeros(1, length(totalEDs_set));
        
        divisible_ratio = divisible_task_ratios(ratio_idx);
        
        % === 關鍵新增：根據分割比例動態調整 Proposal 參數 ===
        if divisible_ratio == 0.0
            % 0% 可分割：專注於完成率
            alpha_prop = 0.8;  % 提高時間緊急度權重
            beta_prop = 0.2;   % 降低分割權重（因為沒有分割）
            fprintf('可分割任務比例: %.0f%% - 應用完成率優化策略 (α=%.1f, β=%.1f)\n', ...
                divisible_ratio*100, alpha_prop, beta_prop);
        elseif divisible_ratio == 0.5
            % 50% 可分割：平衡優化
            alpha_prop = 0.4;  % 平衡權重
            beta_prop = 0.6;   % 平衡權重
            fprintf('可分割任務比例: %.0f%% - 應用平衡優化策略 (α=%.1f, β=%.1f)\n', ...
                divisible_ratio*100, alpha_prop, beta_prop);
        else  % 100% 可分割
            % 100% 可分割：專注於延遲優化
            alpha_prop = 0.4;  % 適度降低時間權重
            beta_prop = 0.6;   % 提高分割獎勵權重
            fprintf('可分割任務比例: %.0f%% - 應用延遲優化策略 (α=%.1f, β=%.1f)\n', ...
                divisible_ratio*100, alpha_prop, beta_prop);
        end

        for nED_idx = 1:length(totalEDs_set)
            nED = totalEDs_set(nED_idx);
            fprintf('  UE數量: %d → ', nED);

            % === 統一環境初始化 ===
            ES_set_base = deploy_ES(max_storage, core_nums, core_rate);
            ES_set_base = update_ES_neighbors(ES_set_base);

            [ED_set_base, ES_set_base] = deploy_ED(nED, ED_is_uniform, ED_in_hs_nums, ES_set_base, nED/50, ES_radius);
            ED_set_base = ED_find_ESs(ED_set_base, ES_set_base, ES_radius);

            % 初始化任務集合
            task_set_prop = struct([]);
            task_set_tsm  = struct([]);
            task_set_bat  = struct([]);

            cleanup_temp_files();
            time = 0;
            total_task_cnt = 0;

            % === 時間步進循環 ===
            for tSlot = 1:time_slots
                time = time + 1;
                if mod(time, new_task_fq) == 1
                    new_task_num = max(1, round(nED * 0.15));
                    if time == 1
                        fprintf('    生成任務數: %d, ', new_task_num);
                    end

                    % 修正：使用 ED_generate_task 的事先隨機分割策略
                    [task_set_prop, newTK_prop] = ED_generate_task(ED_set_base, ES_set_base, task_set_prop, task_parm, new_task_num, time, divisible_ratio);
                    [task_set_tsm,  newTK_tsm ] = ED_generate_task(ED_set_base, ES_set_base, task_set_tsm,  task_parm, new_task_num, time, divisible_ratio);
                    [task_set_bat,  newTK_bat ] = ED_generate_task(ED_set_base, ES_set_base, task_set_bat,  task_parm, new_task_num, time, divisible_ratio);

                    total_task_cnt = total_task_cnt + length(newTK_prop);

                    if mod(time, run_algo_fq) == 1 || ~isempty(newTK_prop)
                        [prop_ED, prop_ES] = copy_environment(ED_set_base, ES_set_base);
                        [tsm_ED,  tsm_ES ] = copy_environment(ED_set_base, ES_set_base);
                        [bat_ED,  bat_ES ] = copy_environment(ED_set_base, ES_set_base);

                        try
                            % === Enhanced Proposal方法：應用優化策略 ===
                            if ~isempty(newTK_prop)
                                [prop_ES, task_set_prop] = enhanced_decentralized_collaboration(...
                                    prop_ES, task_set_prop, newTK_prop, time, PROPOSAL_CONFIG, divisible_ratio);
                            end
                            % 使用優化後的 method_proposal，傳入動態調整的參數
                            method_proposal(prop_ED, prop_ES, task_set_prop, 'prop_temp.mat', ...
                                alpha_prop, beta_prop, time, transfer_time, newTK_prop);
                            load('prop_temp.mat', 'task_set');
                            task_set_prop = task_set; clear task_set;
                        catch ME
                            fprintf('Enhanced Proposal執行錯誤: %s\n', ME.message);
                        end

                        try
                            % TSM 保持原始實現
                            method_TSM(tsm_ED, tsm_ES, task_set_tsm, 'tsm_temp.mat', alpha, beta, time, transfer_time, newTK_tsm);
                            load('tsm_temp.mat', 'task_set');
                            task_set_tsm = task_set; clear task_set;
                        catch ME
                            fprintf('TSM執行錯誤: %s\n', ME.message);
                        end

                        try
                            % BAT 保持原始實現
                            method_BAT(bat_ED, bat_ES, task_set_bat, 'bat_temp.mat', time, transfer_time, newTK_bat);
                            load('bat_temp.mat', 'task_set');
                            task_set_bat = task_set; clear task_set;
                        catch ME
                            fprintf('BAT執行錯誤: %s\n', ME.message);
                        end
                    end

                    fprintf('.');
                end
            end

            % === 統計結果：算出這組 nED_idx 的完成、延遲、能耗數值 ===
            prop_completed = sum([task_set_prop.is_done] == 1);
            tsm_completed  = sum([task_set_tsm.is_done] == 1);
            bat_completed  = sum([task_set_bat.is_done] == 1);

            % （2）把「這組 ED」的結果先寫入暫存
            tmp_prop_success(nED_idx) = prop_completed;
            tmp_tsm_success(nED_idx)  = tsm_completed;
            tmp_bat_success(nED_idx)  = bat_completed;
            tmp_generated(nED_idx)    = total_task_cnt;

            % 記錄成功任務數
            success_stats.prop{ratio_idx, nED_idx}(end+1) = prop_completed;
            success_stats.tsm{ratio_idx, nED_idx}(end+1)  = tsm_completed;
            success_stats.bat{ratio_idx, nED_idx}(end+1)  = bat_completed;

            % 計算成功率、延遲、能耗，並放到 stats、delay_stats、energy_stats
            prop_rate = prop_completed / max(length(task_set_prop), 1);
            stats.prop{ratio_idx, nED_idx}(end+1) = prop_rate;
            tsm_rate  = tsm_completed  / max(length(task_set_tsm),  1);
            stats.tsm{ratio_idx, nED_idx}(end+1)  = tsm_rate;
            bat_rate  = bat_completed  / max(length(task_set_bat),  1);
            stats.bat{ratio_idx, nED_idx}(end+1)  = bat_rate;

            [prop_delay, ~] = calculate_delay(task_set_prop, prop_ES, prop_ED, transfer_time);
            [tsm_delay,  ~] = calculate_delay(task_set_tsm,  tsm_ES,  tsm_ED,  transfer_time);
            [bat_delay,  ~] = calculate_delay(task_set_bat,  bat_ES,  bat_ED,  transfer_time);
            delay_stats.prop{ratio_idx, nED_idx}(end+1) = prop_delay;
            delay_stats.tsm{ratio_idx, nED_idx}(end+1)  = tsm_delay;
            delay_stats.bat{ratio_idx, nED_idx}(end+1)  = bat_delay;

            prop_energy = calculate_energy_consumption(task_set_prop, prop_ES, prop_ED, 'proposal');
            tsm_energy  = calculate_energy_consumption(task_set_tsm,  tsm_ES,  tsm_ED,  'tsm');
            bat_energy  = calculate_energy_consumption(task_set_bat,  bat_ES,  bat_ED,  'bat');
            energy_stats.prop{ratio_idx, nED_idx}(end+1) = prop_energy.total;
            energy_stats.tsm{ratio_idx, nED_idx}(end+1)  = tsm_energy.total;
            energy_stats.bat{ratio_idx, nED_idx}(end+1)  = bat_energy.total;
            energy_per_task.prop{ratio_idx, nED_idx}(end+1) = prop_energy.per_task;
            energy_per_task.tsm{ratio_idx, nED_idx}(end+1)  = tsm_energy.per_task;
            energy_per_task.bat{ratio_idx, nED_idx}(end+1)  = bat_energy.per_task;

            fprintf(' 完成! (Prop: %.1f%%, TSM: %.1f%%, BAT: %.1f%%)\n', ...
                prop_rate*100, tsm_rate*100, bat_rate*100);

            cleanup_temp_files();
        end

        % ===========================
        % （3）跑完所有 nED_idx 之後，把暫存的三組 ED 統計一次「加總」
        total_tasks_success_prop(ratio_idx) = sum(tmp_prop_success);
        total_tasks_success_tsm(ratio_idx)  = sum(tmp_tsm_success);
        total_tasks_success_bat(ratio_idx)  = sum(tmp_bat_success);
        total_tasks_generated(ratio_idx)    = sum(tmp_generated);
        % ===========================
    end
end


%% === 結果分析與輸出（整合版本）===
fprintf('\n=== 計算最終結果（完成率+延遲+能耗）===\n');

[avg_props, avg_tsms, avg_bats] = calculate_success_rates(stats, divisible_task_ratios, totalEDs_set);
[avg_success_props, avg_success_tsms, avg_success_bats] = calculate_avg_success_counts(success_stats, divisible_task_ratios, totalEDs_set);
[avg_delay_props, avg_delay_tsms, avg_delay_bats] = calculate_delays(delay_stats, divisible_task_ratios, totalEDs_set);
[avg_energy_props, avg_energy_tsms, avg_energy_bats] = calculate_avg_energy(energy_stats, divisible_task_ratios, totalEDs_set);

[avg_energy_per_task_props, avg_energy_per_task_tsms, avg_energy_per_task_bats] = calculate_avg_energy(energy_per_task, divisible_task_ratios, totalEDs_set);

% === 能量效率計算 (bit/J) ===
bits_per_task_list = [2500];
for bit_idx = 1:length(bits_per_task_list)
    bits_per_task = bits_per_task_list(bit_idx);

    avg_eff_props = (avg_success_props * bits_per_task) ./ avg_energy_props;
    avg_eff_tsms  = (avg_success_tsms  * bits_per_task) ./ avg_energy_tsms;
    avg_eff_bats  = (avg_success_bats  * bits_per_task) ./ avg_energy_bats;

    fprintf('\n--- 任務大小 %d bit ---\n', bits_per_task);
    display_results_integrated(...
        divisible_task_ratios, totalEDs_set, ...
        avg_props, avg_tsms, avg_bats, ...
        avg_success_props, avg_success_tsms, avg_success_bats, ...
        avg_delay_props, avg_delay_tsms, avg_delay_bats, ...
        avg_energy_props, avg_energy_tsms, avg_energy_bats, ...
        avg_eff_props, avg_eff_tsms, avg_eff_bats, ...
        total_tasks_success_prop, total_tasks_success_tsm, ...
        total_tasks_success_bat, total_tasks_generated);

    create_energy_efficiency_plots(totalEDs_set, divisible_task_ratios, ...
        avg_eff_tsms, avg_eff_props, avg_eff_bats, ...
        sprintf('bits%d', bits_per_task));
end

% 創建所有圖表
create_integrated_plots(totalEDs_set, divisible_task_ratios, avg_tsms, avg_props, avg_bats, ...
                      avg_delay_tsms, avg_delay_props, avg_delay_bats, ...
                      avg_energy_tsms, avg_energy_props, avg_energy_bats);

create_proposal_partition_plot(totalEDs_set, divisible_task_ratios, avg_props);
create_tsm_partition_plot(totalEDs_set, divisible_task_ratios, avg_tsms);
create_energy_plots(totalEDs_set, divisible_task_ratios, avg_energy_tsms, avg_energy_props, avg_energy_bats);
create_energy_per_task_plot(totalEDs_set, divisible_task_ratios, avg_energy_per_task_props, avg_energy_per_task_tsms, avg_energy_per_task_bats);

fprintf('\n=== 整合比較程序執行完畢 ===\n');

%% === 輔助函數 ===
function cleanup_temp_files()
    temp_files = {'prop_temp.mat', 'tsm_temp.mat', 'bat_temp.mat', 'prop.mat', 'tsm.mat', 'bat.mat'};
    for i = 1:length(temp_files)
        if exist(temp_files{i}, 'file')
            delete(temp_files{i});
        end
    end
end

function [ED_copy, ES_copy] = copy_environment(ED_set, ES_set)
    ED_copy = ED_set;
    ES_copy = ES_set;
    
    % 重置ES狀態
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

function [avg_props, avg_tsms, avg_bats] = calculate_success_rates(stats, divisible_task_ratios, totalEDs_set)
    num_ratios = length(divisible_task_ratios);
    num_EDs    = length(totalEDs_set);
    
    avg_props = nan(num_ratios, num_EDs);
    avg_tsms  = nan(num_ratios, num_EDs);
    avg_bats  = nan(num_ratios, num_EDs);
    
    for ratio_idx = 1:num_ratios
        for ed_idx = 1:num_EDs
            if ~isempty(stats.prop{ratio_idx, ed_idx})
                avg_props(ratio_idx, ed_idx) = mean(stats.prop{ratio_idx, ed_idx});
            end
            
            if ~isempty(stats.tsm{ratio_idx, ed_idx})
                avg_tsms(ratio_idx, ed_idx) = mean(stats.tsm{ratio_idx, ed_idx});
            end
            
            if ~isempty(stats.bat{ratio_idx, ed_idx})
                avg_bats(ratio_idx, ed_idx) = mean(stats.bat{ratio_idx, ed_idx});
            end
        end
    end
end

function [avg_delay_props, avg_delay_tsms, avg_delay_bats] = calculate_delays(delay_stats, divisible_task_ratios, totalEDs_set)
    num_ratios = length(divisible_task_ratios);
    num_EDs    = length(totalEDs_set);
    
    avg_delay_props = nan(num_ratios, num_EDs);
    avg_delay_tsms  = nan(num_ratios, num_EDs);
    avg_delay_bats  = nan(num_ratios, num_EDs);
    
    for ratio_idx = 1:num_ratios
        for ed_idx = 1:num_EDs
            if ~isempty(delay_stats.prop{ratio_idx, ed_idx})
                avg_delay_props(ratio_idx, ed_idx) = mean(delay_stats.prop{ratio_idx, ed_idx});
            end
            
            if ~isempty(delay_stats.tsm{ratio_idx, ed_idx})
                avg_delay_tsms(ratio_idx, ed_idx) = mean(delay_stats.tsm{ratio_idx, ed_idx});
            end
            
            if ~isempty(delay_stats.bat{ratio_idx, ed_idx})
                avg_delay_bats(ratio_idx, ed_idx) = mean(delay_stats.bat{ratio_idx, ed_idx});
            end
        end
    end
end

function [avg_props, avg_tsms, avg_bats] = calculate_avg_energy(stats, divisible_task_ratios, totalEDs_set)
    avg_props = zeros(length(divisible_task_ratios), length(totalEDs_set));
    avg_tsms = zeros(length(divisible_task_ratios), length(totalEDs_set));
    avg_bats = zeros(length(divisible_task_ratios), length(totalEDs_set));
    
    for ratio_idx = 1:length(divisible_task_ratios)
        for ed_idx = 1:length(totalEDs_set)
            if ~isempty(stats.prop{ratio_idx, ed_idx})
                avg_props(ratio_idx, ed_idx) = mean(stats.prop{ratio_idx, ed_idx});
                avg_tsms(ratio_idx, ed_idx) = mean(stats.tsm{ratio_idx, ed_idx});
                avg_bats(ratio_idx, ed_idx) = mean(stats.bat{ratio_idx, ed_idx});
            else
                avg_props(ratio_idx, ed_idx) = nan;
                avg_tsms(ratio_idx, ed_idx) = nan;
                avg_bats(ratio_idx, ed_idx) = nan;
            end
        end
    end
end

function display_results_integrated(divisible_task_ratios, totalEDs_set, ...
                                    avg_props, avg_tsms, avg_bats, ...
                                    avg_success_props, avg_success_tsms, avg_success_bats, ...
                                    avg_delay_props, avg_delay_tsms, avg_delay_bats, ...
                                    avg_energy_props, avg_energy_tsms, avg_energy_bats, ...
                                    avg_eff_props, avg_eff_tsms, avg_eff_bats, ...
                                    varargin)
    % display_results_integrated：以纯文本方式打印"完成率 + 延迟 + 能耗"结果
    
    % 先从 varargin 里分配"成功任务数/总生成任务数"这 4 个可选向量
    if length(varargin) == 4
        total_tasks_success_prop = varargin{1};
        total_tasks_success_tsm  = varargin{2};
        total_tasks_success_bat  = varargin{3};
        total_tasks_generated    = varargin{4};
    else
        total_tasks_success_prop = [];
        total_tasks_success_tsm  = [];
        total_tasks_success_bat  = [];
        total_tasks_generated    = [];
    end
    
    % 1) 平均任務完成率
    fprintf('\n=== 平均任務完成率結果 ===\n');
    for r = 1:length(divisible_task_ratios)
        ratio = divisible_task_ratios(r);
        fprintf('--- Divisible Task Ratio: %.2f ---\n', ratio);
        for i = 1:length(totalEDs_set)
            ed = totalEDs_set(i);
            p_rate = avg_props(r,i) * 100;    % Proposal 完成率（%）
            t_rate = avg_tsms(r,i)  * 100;    % TSM 完成率（%）
            b_rate = avg_bats(r,i)  * 100;    % BAT 完成率（%）
            fprintf('UE數量 = %5d → TSM: %6.2f%%, Proposal: %6.2f%%, BAT: %6.2f%%\n', ...
                    ed, t_rate, p_rate, b_rate);
        end
        
        % 如果有传进"成功任务数/总生成任务数"，就打印
        if ~isempty(total_tasks_success_prop) && ~isempty(total_tasks_generated)
            sum_prop = total_tasks_success_prop(r);
            sum_tsm  = total_tasks_success_tsm(r);
            sum_bat  = total_tasks_success_bat(r);
            tot_gen  = total_tasks_generated(r);
            fprintf('[Proposal] 成功任務數：%d / %d\n', sum_prop, tot_gen);
            fprintf('[TSM]      成功任務數：%d / %d\n', sum_tsm,  tot_gen);
            fprintf('[BAT]      成功任務數：%d / %d\n', sum_bat,  tot_gen);
        end

        fprintf('\n');
    end

    % 1.5) 平均成功任務數 (依可分割比例)
    fprintf('=== 平均成功任務數 (依可分割比例) ===\n');
    for r = 1:length(divisible_task_ratios)
        ratio = divisible_task_ratios(r);
        fprintf('--- Divisible Task Ratio: %.2f ---\n', ratio);
        for i = 1:length(totalEDs_set)
            ed = totalEDs_set(i);
            p_cnt = avg_success_props(r,i);
            t_cnt = avg_success_tsms(r,i);
            b_cnt = avg_success_bats(r,i);
            fprintf('UE數量 = %5d → TSM: %8.2f, Proposal: %8.2f, BAT: %8.2f\n', ...
                    ed, t_cnt, p_cnt, b_cnt);
        end
        fprintf('\n');
    end

    % 1.6) 各UE數量的平均成功任務數 (跨可分割比例)
    fprintf('=== 各UE數量平均成功任務數 ===\n');
    avg_by_ed_prop = mean(avg_success_props, 1, 'omitnan');
    avg_by_ed_tsm  = mean(avg_success_tsms, 1, 'omitnan');
    avg_by_ed_bat  = mean(avg_success_bats, 1, 'omitnan');
    for i = 1:length(totalEDs_set)
        ed = totalEDs_set(i);
        fprintf('UE數量 = %5d → TSM: %8.2f, Proposal: %8.2f, BAT: %8.2f\n', ...
                ed, avg_by_ed_tsm(i), avg_by_ed_prop(i), avg_by_ed_bat(i));
    end
    fprintf('\n');

    % 2) 平均延遲
    fprintf('=== 平均延遲結果（單位 ms）===\n');
    for r = 1:length(divisible_task_ratios)
        ratio = divisible_task_ratios(r);
        fprintf('--- Divisible Task Ratio: %.2f ---\n', ratio);
        for i = 1:length(totalEDs_set)
            ed = totalEDs_set(i);
            p_delay = avg_delay_props(r,i) * 1000;   % Proposal 延遲 (秒→毫秒)
            t_delay = avg_delay_tsms(r,i)  * 1000;   % TSM 延遲
            b_delay = avg_delay_bats(r,i)  * 1000;   % BAT 延遲
            fprintf('UE數量 = %5d → TSM: %6.2f ms, Proposal: %6.2f ms, BAT: %6.2f ms\n', ...
                    ed, t_delay, p_delay, b_delay);
        end
        fprintf('\n');
    end
    
    % 3) 平均能耗
    fprintf('=== 平均總能耗結果（單位 J）===\n');
    for r = 1:length(divisible_task_ratios)
        ratio = divisible_task_ratios(r);
        fprintf('--- Divisible Task Ratio: %.2f ---\n', ratio);
        for i = 1:length(totalEDs_set)
            ed = totalEDs_set(i);
            p_e = avg_energy_props(r,i);   % Proposal 總能耗
            t_e = avg_energy_tsms(r,i);    % TSM 總能耗
            b_e = avg_energy_bats(r,i);    % BAT 總能耗
            fprintf('UE數量 = %5d → TSM: %8.2f J, Proposal: %8.2f J, BAT: %8.2f J\n', ...
                    ed, t_e, p_e, b_e);
        end
        fprintf('\n');
    end

    % 4) 平均能量效率 (bit/J)
    fprintf('=== 平均任務能量效率 (bit/J) ===\n');
    for r = 1:length(divisible_task_ratios)
        ratio = divisible_task_ratios(r);
        fprintf('--- Divisible Task Ratio: %.2f ---\n', ratio);
        for i = 1:length(totalEDs_set)
            ed = totalEDs_set(i);
            p_eff = avg_eff_props(r,i);
            t_eff = avg_eff_tsms(r,i);
            b_eff = avg_eff_bats(r,i);
            fprintf('UE數量 = %5d → TSM: %8.2f, Proposal: %8.2f, BAT: %8.2f\n', ...
                    ed, t_eff, p_eff, b_eff);
        end
        fprintf('\n');
    end
end

function create_integrated_plots(totalEDs_set, divisible_task_ratios, avg_tsms, avg_props, avg_bats, ...
                               avg_delay_tsms, avg_delay_props, avg_delay_bats, ...
                               avg_energy_tsms, avg_energy_props, avg_energy_bats)
    
    % 創建結果保存目錄
    if ~exist('results', 'dir')
        mkdir('results');
    end
    
    % 設定顏色
    colors = {[0.0 0.4470 0.7410], [0.8500 0.3250 0.0980], [0.4660 0.6740 0.1880]};
    method_names = {'TSM', 'Proposal', 'BAT'};
    
    % === 1. 綜合比較圖（三個指標併排）===
    for ratio_idx = 1:length(divisible_task_ratios)
        figure('Position', [100, 100, 1200, 400]);
        
        % 子圖1：完成率
        subplot(1,3,1);
        hold on;
        plot(totalEDs_set, avg_tsms(ratio_idx, :)*100, '-o', 'LineWidth', 2, 'Color', colors{1}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_props(ratio_idx, :)*100, '-s', 'LineWidth', 2, 'Color', colors{2}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_bats(ratio_idx, :)*100, '-^', 'LineWidth', 2, 'Color', colors{3}, 'MarkerSize', 6);
        legend(method_names, 'Location', 'best', 'FontSize', 10);
        xlabel('UE數量', 'FontSize', 11);
        ylabel('完成率 (%)', 'FontSize', 11);
        title('任務完成率', 'FontSize', 12);
        grid on;
        ylim([0 100]);
        
        % 子圖2：延遲
        subplot(1,3,2);
        hold on;
        plot(totalEDs_set, avg_delay_tsms(ratio_idx, :)*1000, '-o', 'LineWidth', 2, 'Color', colors{1}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_delay_props(ratio_idx, :)*1000, '-s', 'LineWidth', 2, 'Color', colors{2}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_delay_bats(ratio_idx, :)*1000, '-^', 'LineWidth', 2, 'Color', colors{3}, 'MarkerSize', 6);
        legend(method_names, 'Location', 'best', 'FontSize', 10);
        xlabel('UE數量', 'FontSize', 11);
        ylabel('平均延遲 (ms)', 'FontSize', 11);
        title('平均延遲', 'FontSize', 12);
        grid on;
        
        % 子圖3：能耗
        subplot(1,3,3);
        hold on;
        plot(totalEDs_set, avg_energy_tsms(ratio_idx, :), '-o', 'LineWidth', 2, 'Color', colors{1}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_energy_props(ratio_idx, :), '-s', 'LineWidth', 2, 'Color', colors{2}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_energy_bats(ratio_idx, :), '-^', 'LineWidth', 2, 'Color', colors{3}, 'MarkerSize', 6);
        legend(method_names, 'Location', 'best', 'FontSize', 10);
        xlabel('UE數量', 'FontSize', 11);
        ylabel('總能耗 (J)', 'FontSize', 11);
        title('總能耗', 'FontSize', 12);
        grid on;
        
        % 設定整體標題
        sgtitle(sprintf('整合比較: %.0f%%可分割任務', divisible_task_ratios(ratio_idx)*100), 'FontSize', 14);
        
        % 保存圖片
        saveas(gcf, sprintf('results/integrated_comparison_%.0f_percent.png', divisible_task_ratios(ratio_idx)*100));
        close;

        % === 分開圖表：完成率 ===
        figure('Position', [100, 100, 400, 400]);
        hold on;
        plot(totalEDs_set, avg_tsms(ratio_idx, :)*100, '-o', 'LineWidth', 2, 'Color', colors{1}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_props(ratio_idx, :)*100, '-s', 'LineWidth', 2, 'Color', colors{2}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_bats(ratio_idx, :)*100, '-^', 'LineWidth', 2, 'Color', colors{3}, 'MarkerSize', 6);
        legend(method_names, 'Location', 'best', 'FontSize', 10);
        xlabel('UE數量', 'FontSize', 11);
        ylabel('完成率 (%)', 'FontSize', 11);
        title(sprintf('任務完成率 - %.0f%%可分割', divisible_task_ratios(ratio_idx)*100), 'FontSize', 12);
        grid on;
        ylim([0 100]);
        saveas(gcf, sprintf('results/integrated_success_%.0f_percent.png', divisible_task_ratios(ratio_idx)*100));
        close;

        % === 分開圖表：延遲 ===
        figure('Position', [100, 100, 400, 400]);
        hold on;
        plot(totalEDs_set, avg_delay_tsms(ratio_idx, :)*1000, '-o', 'LineWidth', 2, 'Color', colors{1}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_delay_props(ratio_idx, :)*1000, '-s', 'LineWidth', 2, 'Color', colors{2}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_delay_bats(ratio_idx, :)*1000, '-^', 'LineWidth', 2, 'Color', colors{3}, 'MarkerSize', 6);
        legend(method_names, 'Location', 'best', 'FontSize', 10);
        xlabel('UE數量', 'FontSize', 11);
        ylabel('平均延遲 (ms)', 'FontSize', 11);
        title(sprintf('平均延遲 - %.0f%%可分割', divisible_task_ratios(ratio_idx)*100), 'FontSize', 12);
        grid on;
        saveas(gcf, sprintf('results/integrated_delay_%.0f_percent.png', divisible_task_ratios(ratio_idx)*100));
        close;

        % === 分開圖表：能耗 ===
        figure('Position', [100, 100, 400, 400]);
        hold on;
        plot(totalEDs_set, avg_energy_tsms(ratio_idx, :), '-o', 'LineWidth', 2, 'Color', colors{1}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_energy_props(ratio_idx, :), '-s', 'LineWidth', 2, 'Color', colors{2}, 'MarkerSize', 6);
        plot(totalEDs_set, avg_energy_bats(ratio_idx, :), '-^', 'LineWidth', 2, 'Color', colors{3}, 'MarkerSize', 6);
        legend(method_names, 'Location', 'best', 'FontSize', 10);
        xlabel('UE數量', 'FontSize', 11);
        ylabel('總能耗 (J)', 'FontSize', 11);
        title(sprintf('總能耗 - %.0f%%可分割', divisible_task_ratios(ratio_idx)*100), 'FontSize', 12);
        grid on;
        saveas(gcf, sprintf('results/integrated_energy_%.0f_percent.png', divisible_task_ratios(ratio_idx)*100));
        close;
    end
end

function create_proposal_partition_plot(totalEDs_set, divisible_task_ratios, avg_props)
    figure('Position', [100, 100, 800, 600]);
    hold on;
    
    colors = {'r-o', 'm-s', 'c-^'};
    labels = {'不可分割 (0%)', '部分可分割 (50%)', '完全可分割 (100%)'};
    
    for ratio_idx = 1:length(divisible_task_ratios)
        plot(totalEDs_set, avg_props(ratio_idx, :)*100, colors{ratio_idx}, ...
             'LineWidth', 2.5, 'MarkerSize', 7);
    end
    
    legend(labels, 'Location', 'Best', 'FontSize', 12);
    xlabel('Number of Edge Devices (EDs)', 'FontSize', 12);
    ylabel('Task Success Rate (%)', 'FontSize', 12);
    title('Proposal Method: Success Rate vs Partition Ratios', 'FontSize', 14);
    grid on;
    xticks(totalEDs_set);
    ylim([40 100]);
    
    % 保存到results目錄
    if ~exist('results', 'dir')
        mkdir('results');
    end
    saveas(gcf, 'results/proposal_partition_analysis.png');
    hold off;
    close;
end

function create_tsm_partition_plot(totalEDs_set, divisible_task_ratios, avg_tsms)
    figure('Position', [100, 100, 800, 600]);
    hold on;
    
    colors = {'b-o', 'm-s', 'c-^'};
    labels = {'不可分割 (0%)', '部分可分割 (50%)', '完全可分割 (100%)'};
    
    for ratio_idx = 1:length(divisible_task_ratios)
        plot(totalEDs_set, avg_tsms(ratio_idx, :)*100, colors{ratio_idx}, ...
             'LineWidth', 2.5, 'MarkerSize', 7);
    end
    
    legend(labels, 'Location', 'Best', 'FontSize', 12);
    xlabel('Number of Edge Devices (EDs)', 'FontSize', 12);
    ylabel('Task Success Rate (%)', 'FontSize', 12);
    title('TSM Method: Success Rate vs Partition Ratios', 'FontSize', 14);
    grid on;
    xticks(totalEDs_set);
    ylim([40 100]);
    
    % 保存到results目錄
    if ~exist('results', 'dir')
        mkdir('results');
    end
    saveas(gcf, 'results/tsm_partition_analysis.png');
    hold off;
    close;
end

function [ES_set, task_set] = decentralized_collaboration(ES_set, task_set, newTK_set, current_time)
    % === Proposal方法的去中心化協作機制 ===
    % 實現論文中提到的分散式資源管理與多節點協作
    
    if isempty(newTK_set) || isempty(ES_set)
        return;
    end
    
    % 1. 計算全域負載狀況
    total_ratio = 0;
    for i = 1:length(ES_set)
        total_ratio = total_ratio + calculate_ES_load_ratio(ES_set(i));
    end

    system_load_ratio = total_ratio / length(ES_set);
    
    % 2. 動態調整協作策略
    if system_load_ratio > 0.7
        collaboration_mode = 'high_load';
        priority_threshold = 0.8;
    elseif system_load_ratio > 0.4
        collaboration_mode = 'medium_load';
        priority_threshold = 0.6;
    else
        collaboration_mode = 'low_load';
        priority_threshold = 0.4;
    end
    
    % 3. 為新任務進行協作式預分配評估
    for i = 1:length(newTK_set)
        task_id = newTK_set(i).ID;
        
        if task_id > length(task_set) || task_id <= 0
            continue;
        end
        
        % 計算任務緊急度
        remain_time = task_set(task_id).expired_time - current_time;
        if remain_time <= 0
            continue;
        end
        
        urgency_score = 1 / remain_time;
        
        % 分割任務獲得協作優先權
        if task_set(task_id).is_partition == 1 && ...
           isfield(task_set(task_id), 'allowed_partition_ratio') && ...
           ~isempty(task_set(task_id).allowed_partition_ratio)
            collaboration_priority = urgency_score * 1.3; % 30%優先權提升
        else
            collaboration_priority = urgency_score;
        end
        
        % 高優先權任務觸發協作機制
        if collaboration_priority > priority_threshold
            % 尋找最佳協作ES組合
            [best_es_ids, collaboration_benefit] = find_collaboration_partners(...
                ES_set, task_set(task_id), collaboration_mode);
            
            if ~isempty(best_es_ids) && collaboration_benefit > 0.1
                % 標記為協作任務
                task_set(task_id).collaboration_mode = collaboration_mode;
                task_set(task_id).preferred_ES_ids = best_es_ids;
                task_set(task_id).collaboration_priority = collaboration_priority;
            end
        end
    end
end

function [best_es_ids, benefit] = find_collaboration_partners(ES_set, task, mode)
    % 尋找最佳協作夥伴ES
    best_es_ids = [];
    benefit = 0;
    
    if task.is_partition ~= 1 || ~isfield(task, 'allowed_partition_ratio') || ...
       isempty(task.allowed_partition_ratio)
        return;
    end
    
    num_parts = length(task.allowed_partition_ratio);
    
    % 尋找負載較低的ES作為協作夥伴
    es_loads = zeros(1, length(ES_set));
    for i = 1:length(ES_set)
        es_loads(i) = calculate_ES_load_ratio(ES_set(i));
    end
    
    [~, sorted_indices] = sort(es_loads);
    
    % 根據協作模式選擇ES數量
    switch mode
        case 'high_load'
            max_partners = min(num_parts, 2); % 高負載時限制協作數量
        case 'medium_load'
            max_partners = min(num_parts, 3);
        case 'low_load'
            max_partners = min(num_parts, length(ES_set));
    end
    
    % 選擇負載最低的ES作為協作夥伴
    selected_count = 0;
    for i = 1:length(sorted_indices)
        es_id = sorted_indices(i);
        
        % 檢查該ES是否有足夠容量
        if (ES_set(es_id).queue_storage + task.storage) <= ES_set(es_id).max_storage
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
        parallel_exec_time = task.workload / (length(best_es_ids) * ES_set(best_es_ids(1)).core(1).rate);
        
        benefit = (single_exec_time - parallel_exec_time) / single_exec_time;
    end
end

function [avg_props, avg_tsms, avg_bats] = calculate_avg_success_counts(stats, divisible_task_ratios, totalEDs_set)
    % 計算平均成功任務數
    avg_props = nan(length(divisible_task_ratios), length(totalEDs_set));
    avg_tsms  = nan(length(divisible_task_ratios), length(totalEDs_set));
    avg_bats  = nan(length(divisible_task_ratios), length(totalEDs_set));

    for ratio_idx = 1:length(divisible_task_ratios)
        for ed_idx = 1:length(totalEDs_set)
            if ~isempty(stats.prop{ratio_idx, ed_idx})
                avg_props(ratio_idx, ed_idx) = mean(stats.prop{ratio_idx, ed_idx});
            end

            if ~isempty(stats.tsm{ratio_idx, ed_idx})
                avg_tsms(ratio_idx, ed_idx) = mean(stats.tsm{ratio_idx, ed_idx});
            end

            if ~isempty(stats.bat{ratio_idx, ed_idx})
                avg_bats(ratio_idx, ed_idx) = mean(stats.bat{ratio_idx, ed_idx});
            end
        end
    end
end