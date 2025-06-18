clc; clear; close all;
rng(0);

%% === 優化參數設置：強化分割效果與方法差異 ===
simulation_times = 1;
time_slots       = 100;
run_algo_fq      = 10;
new_task_fq      = 8;
totalEDs_set     = [1000, 1500, 2000, 2500, 3000, 3500];

% 可分割的任務比例：0% 50% 100%
divisible_task_ratios = [0.00, 0.50, 1.00];

ED_is_uniform = 1;
ED_in_hs_nums = 30;
max_storage   = 100;

core_nums     = 8;
core_rate     = 5e7;
ES_radius     = 100;

alpha = 0.6;
beta  = 0.4;
transfer_time = 2;

base_partition_ratios = {
    [],
    [0.2,0.2,0.2,0.2,0.2],
    [0.2,0.2,0.2,0.2,0.2]
};

task_parm = struct(...
    'deadline',   [30, 60], ...
    'workload',   [1e6, 2e6], ...
    'storage',    [3.0, 4.0], ...
    'is_partition',[0, 1]);

%% === 能耗統計容器初始化 ===
for ratio_idx = 1:length(divisible_task_ratios)
    for ed_idx = 1:length(totalEDs_set)
        for f={'prop','tsm','bat'}
            energy_stats.(f{1}){ratio_idx, ed_idx} = [];
            energy_per_task.(f{1}){ratio_idx, ed_idx} = [];
        end
    end
end

%% === 能耗主模擬循環 ===
fprintf('=== 能耗比較：TSM vs Proposal vs BAT ===\n');

for sim = 1:simulation_times
    fprintf('\n--- 能耗模擬回合: %d/%d ---\n', sim, simulation_times);
    
    for ratio_idx = 1:length(divisible_task_ratios)
        divisible_ratio = divisible_task_ratios(ratio_idx);
        current_partition_ratios = base_partition_ratios{ratio_idx};
        
        fprintf('可分割任務比例: %.0f%% (分割策略: %s)\n', ...
                divisible_ratio*100, mat2str(current_partition_ratios));
        
        for nED_idx = 1:length(totalEDs_set)
            nED = totalEDs_set(nED_idx);
            fprintf('  ED數量: %d → ', nED);

            % === 統一環境初始化 ===
            ES_set_base = deploy_ES(max_storage, core_nums, core_rate);
            ES_set_base = update_ES_neighbors(ES_set_base);
            [ED_set_base, ES_set_base] = deploy_ED(nED, ED_is_uniform, ED_in_hs_nums, ES_set_base, nED/50, ES_radius);
            ED_set_base = ED_find_ESs(ED_set_base, ES_set_base, ES_radius);
            
            task_set_prop = struct([]);
            task_set_tsm = struct([]);
            task_set_bat = struct([]);
            cleanup_temp_files();
            time = 0;

            for tSlot = 1:time_slots
                time = time + 1;
                if mod(time, new_task_fq) == 1
                    task_ratio = 0.15;
                    new_task_num = max(1, round(nED * task_ratio));
                    if time == 1
                        fprintf('    生成任務數: %d, ', new_task_num);
                    end
                    [task_set_prop, newTK_prop] = ED_generate_task_fixed(ED_set_base, ES_set_base, task_set_prop, task_parm, new_task_num, time, divisible_ratio, current_partition_ratios);
                    [task_set_tsm, newTK_tsm] = ED_generate_task_fixed(ED_set_base, ES_set_base, task_set_tsm, task_parm, new_task_num, time, divisible_ratio, current_partition_ratios);
                    [task_set_bat, newTK_bat] = ED_generate_task_fixed(ED_set_base, ES_set_base, task_set_bat, task_parm, new_task_num, time, divisible_ratio, current_partition_ratios);
                    % 執行三種方法（僅為能耗分析，可不需載入回來延遲/完成率）
                    [prop_ED, prop_ES] = copy_environment(ED_set_base, ES_set_base);
                    [tsm_ED, tsm_ES] = copy_environment(ED_set_base, ES_set_base);
                    [bat_ED, bat_ES] = copy_environment(ED_set_base, ES_set_base);
                    try
                        method_proposal(prop_ED, prop_ES, task_set_prop, 'prop_temp.mat', alpha, beta, time, transfer_time, newTK_prop);
                        load('prop_temp.mat', 'task_set');
                        task_set_prop = task_set; clear task_set;
                    catch
                        fprintf('Proposal執行錯誤\n');
                    end
                    try
                        method_TSM(tsm_ED, tsm_ES, task_set_tsm, 'tsm_temp.mat', alpha, beta, time, transfer_time, newTK_tsm);
                        load('tsm_temp.mat', 'task_set');
                        task_set_tsm = task_set; clear task_set;
                    catch
                        fprintf('TSM執行錯誤\n');
                    end
                    try
                        method_BAT(bat_ED, bat_ES, task_set_bat, 'bat_temp.mat', time, transfer_time, newTK_bat);
                        load('bat_temp.mat', 'task_set');
                        task_set_bat = task_set; clear task_set;
                    catch
                        fprintf('BAT執行錯誤\n');
                    end
                end
            end

            % === 能耗統計 ===
            prop_energy = calculate_energy_consumption(task_set_prop, prop_ES, prop_ED, 'proposal');
            tsm_energy  = calculate_energy_consumption(task_set_tsm, tsm_ES, tsm_ED, 'tsm');
            bat_energy  = calculate_energy_consumption(task_set_bat, bat_ES, bat_ED, 'bat');
            
            energy_stats.prop{ratio_idx, nED_idx}(end+1) = prop_energy.total;
            energy_stats.tsm{ratio_idx, nED_idx}(end+1)  = tsm_energy.total;
            energy_stats.bat{ratio_idx, nED_idx}(end+1)  = bat_energy.total;

            energy_per_task.prop{ratio_idx, nED_idx}(end+1) = prop_energy.per_task;
            energy_per_task.tsm{ratio_idx, nED_idx}(end+1)  = tsm_energy.per_task;
            energy_per_task.bat{ratio_idx, nED_idx}(end+1)  = bat_energy.per_task;

            fprintf(' 能耗計算完成!\n');
            cleanup_temp_files();
        end
    end
end

%% === 平均能耗結果分析 ===
[avg_prop_energy, avg_tsm_energy, avg_bat_energy] = calculate_avg_energy(energy_stats, divisible_task_ratios, totalEDs_set);
[avg_prop_per_task, avg_tsm_per_task, avg_bat_per_task] = calculate_avg_energy(energy_per_task, divisible_task_ratios, totalEDs_set);

% 能耗圖表
create_energy_plots(totalEDs_set, divisible_task_ratios, avg_tsm_energy, avg_prop_energy, avg_bat_energy);
create_energy_per_task_plot(totalEDs_set, divisible_task_ratios, avg_prop_per_task, avg_tsm_per_task, avg_bat_per_task);

% ===== 數值輸出（每任務平均能耗表格） =====
for ratio_idx = 1:length(divisible_task_ratios)
    fprintf('\n===== 可分割任務比例 %.0f%% =====\n', divisible_task_ratios(ratio_idx)*100);
    fprintf('ED數量\tTSM能耗\tProposal能耗\tBAT能耗\n');
    for nED_idx = 1:length(totalEDs_set)
        fprintf('%d\t%.4f\t%.4f\t%.4f\n', totalEDs_set(nED_idx), ...
            avg_tsm_energy(ratio_idx, nED_idx), ...
            avg_prop_energy(ratio_idx, nED_idx), ...
            avg_bat_energy(ratio_idx, nED_idx));
    end
end

for ratio_idx = 1:length(divisible_task_ratios)
    fprintf('\n--- 平均單任務能耗 (%.0f%% 可分割) ---\n', divisible_task_ratios(ratio_idx)*100);
    fprintf('ED數量\tTSM\tProposal\tBAT\n');
    for nED_idx = 1:length(totalEDs_set)
        fprintf('%d\t%.6f\t%.6f\t%.6f\n', totalEDs_set(nED_idx), ...
            avg_tsm_per_task(ratio_idx, nED_idx), ...
            avg_prop_per_task(ratio_idx, nED_idx), ...
            avg_bat_per_task(ratio_idx, nED_idx));
    end
end


%% === 輔助函數 ===
function cleanup_temp_files()
    temp_files = {'prop_temp.mat', 'tsm_temp.mat', 'bat_temp.mat', 'prop.mat', 'tsm.mat', 'bat.mat'};
    for i = 1:length(temp_files)
        if exist(temp_files{i}, 'file')
            delete(temp_files{i});
        end
    end
end

function [task_set, newTK_set] = ED_generate_task_fixed(ED_set, ES_set, task_set, task_parm, new_task_nums, task_generate_time, divisible_ratio, partition_ratios)
    % === 修正版：帶有固定分割比例的任務生成函數 ===
    
    try
        % 首先生成基本任務
        [task_set, newTK_set] = ED_generate_task(ED_set, ES_set, task_set, task_parm, new_task_nums, task_generate_time, divisible_ratio);
        
        % 然後設置分割比例
        if ~isempty(newTK_set) && nargin >= 8 && ~isempty(partition_ratios)
            % 為新生成的可分割任務設定固定分割比例
            for i = 1:length(newTK_set)
                if isfield(newTK_set(i), 'is_partition') && newTK_set(i).is_partition == 1
                    newTK_set(i).allowed_partition_ratio = partition_ratios;
                    
                    % 同時更新task_set中對應的任務
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
        fprintf('ED_generate_task_fixed 執行錯誤: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('錯誤位置: %s, 行號: %d\n', ME.stack(1).name, ME.stack(1).line);
        end
        
        % 錯誤時返回空結構
        if isempty(task_set)
            task_set = struct([]);
        end
        newTK_set = struct([]);
    end
end

function [ED_copy, ES_copy] = copy_environment(ED_set, ES_set)
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
