function alpha_beta_sensitivity_experiment()
    % === Parameter Sensitivity Experiment ===
    % Scan different alpha/beta pairs for the Proposal method

    clc; clear; close all; %#ok<CLSCR>
    rng(0);

    alphas = 0.1:0.1:0.9;
    betas  = 1 - alphas;

    num_cases = length(alphas);
    success_rates = zeros(1, num_cases);
    avg_delays = zeros(1, num_cases);

    % Fixed simulation settings
    nED = 1000;                    % number of edge devices
    time_slots = 50;               % simulation horizon
    new_task_fq = 8;               % task generation frequency
    task_ratio = 0.15;             % task arrival ratio
    divisible_ratio = 1.0;         % all tasks are divisible

    max_storage = 100;
    core_nums   = 8;
    core_rate   = 4e7;
    ES_radius   = 100;
    ED_is_uniform = 1;
    ED_in_hs_nums = 30;
    transfer_time = 2.5;

    task_parm = struct('deadline', [30, 60], ...
                       'workload', [1e6, 2e6], ...
                       'storage', [3.0, 4.0], ...
                       'is_partition', [0, 1]);

    for idx = 1:num_cases
        alpha = alphas(idx);
        beta  = betas(idx);

        % ==== Environment initialization ====
        ES_set = deploy_ES(max_storage, core_nums, core_rate);
        ES_set = update_ES_neighbors(ES_set);
        [ED_set, ES_set] = deploy_ED(nED, ED_is_uniform, ED_in_hs_nums, ES_set, nED/50, ES_radius);
        ED_set = ED_find_ESs(ED_set, ES_set, ES_radius);

        task_set = struct([]);
        cleanup_temp_files();

        % ==== Time stepping simulation ====
        for t = 1:time_slots
            newTK = [];
            if mod(t, new_task_fq) == 1
                new_task_num = max(1, round(nED * task_ratio));
                [task_set, newTK] = ED_generate_task(ED_set, ES_set, task_set, task_parm, new_task_num, t, divisible_ratio);
            end

            method_proposal(ED_set, ES_set, task_set, 'prop_tmp.mat', alpha, beta, t, transfer_time, newTK, divisible_ratio);
            load('prop_tmp.mat', 'ED_set', 'ES_set', 'task_set');
        end

        completed = sum([task_set.is_done] == 1);
        total_tasks = length(task_set);
        success_rates(idx) = completed / max(total_tasks,1) * 100;

        [delay, ~] = calculate_delay(task_set, ES_set, ED_set, transfer_time, 1.0);
        avg_delays(idx) = delay * 1000;  % convert to ms
    end

    %% === Plotting ===
    if ~exist('result', 'dir')
        mkdir('result');
    end

    figure('Position',[100,100,800,600]);
    plot(alphas, success_rates, '-o', 'LineWidth', 2, 'MarkerSize', 6);
    grid on;
    xlabel('\alpha');
    ylabel('Success Rate (%)');
    title('\alpha/\beta 對任務完成率的影響');
    xlim([0.1 0.9]);
    xticks(alphas);
    saveas(gcf, 'result/alpha_beta_success_rate.png');
    close;

    figure('Position',[100,100,800,600]);
    plot(alphas, avg_delays, '-o', 'LineWidth', 2, 'MarkerSize', 6);
    grid on;
    xlabel('\alpha');
    ylabel('Average Delay (ms)');
    title('\alpha/\beta 對平均延遲的影響');
    xlim([0.1 0.9]);
    xticks(alphas);
    saveas(gcf, 'result/alpha_beta_delay.png');
    close;
end

function cleanup_temp_files()
    temp_files = {'prop_tmp.mat'};
    for i = 1:length(temp_files)
        if exist(temp_files{i}, 'file')
            delete(temp_files{i});
        end
    end
end
