function method_TSM(ED_set, ES_set, task_set, filename, alpha, beta, time, transfer_time, newTK_set)
    % === TSM Method: Task Scheduling With Multicore Edge Computing ===
    % Based on TSM research paper
    
    try
        % Load previous state if available
        if time > 1
            try
                load(filename, 'ED_set', 'ES_set', 'task_set');
            catch
                % If loading fails, use input parameters
            end
        end
        
        % Safely merge new tasks with existing tasks
        if ~isempty(newTK_set)
            if ~isempty(task_set)
                task_set = unify_task_fields(task_set, newTK_set);
                newTK_set = unify_task_fields(newTK_set, task_set);
                task_set = [task_set, newTK_set];
            else
                task_set = newTK_set;
            end
        end

        % Stage 1: Task Assignment - TSM uses workload-based ES selection
        for newTK_idx = 1:length(newTK_set)
            select_ES_id = 0;
            min_workload = inf;

            newTK_id = newTK_set(newTK_idx).ID;
            
            if newTK_id > length(task_set) || newTK_id <= 0
                continue;
            end
            
            ED_id = task_set(newTK_id).ED_ID;
            
            if ED_id > length(ED_set) || ED_id <= 0 || isempty(ED_set(ED_id).candidate_ES)
                task_set(newTK_id).is_done = -1;
                continue;
            end

            % TSM selects ES with lowest workload
            for candidate_ES_idx = 1:length(ED_set(ED_id).candidate_ES)
                candidate_ES_id = ED_set(ED_id).candidate_ES(candidate_ES_idx);
                
                if candidate_ES_id > length(ES_set) || candidate_ES_id <= 0
                    continue;
                end
                
                % Check storage capacity
                if (ES_set(candidate_ES_id).queue_storage + task_set(newTK_id).storage) <= ES_set(candidate_ES_id).max_storage && ...
                   (ES_set(candidate_ES_id).queue_memory + task_set(newTK_id).memory) <= ES_set(candidate_ES_id).max_memory
                    % TSM considers total workload
                    ES_workload = ES_set(candidate_ES_id).total_workloads;
                    
                    if ES_workload < min_workload
                        min_workload = ES_workload;
                        select_ES_id = candidate_ES_id;
                    end
                end
            end

            if select_ES_id == 0
                task_set(newTK_id).is_done = -1;
            else
                ES_set(select_ES_id) = ES_set(select_ES_id).add_task(task_set(newTK_id).workload, task_set(newTK_id).storage, task_set(newTK_id).memory, newTK_id);
                task_set(newTK_id).ES_ID = select_ES_id;
                task_set(newTK_id).ES_path(end+1) = select_ES_id;
            end
        end

        % Stage 2: Process undone tasks with TSM's algorithm
        for ES_id = 1:length(ES_set)
            undone_task_id_set = ES_set(ES_id).undone_task_ID_set;
            
            if isempty(undone_task_id_set)
                continue;
            end

            % Update core times
            for i = 1:length(ES_set(ES_id).core)
                if ES_set(ES_id).core(i).running_time < time
                    ES_set(ES_id).core(i).running_time = time;
                end
            end

            % Process undone tasks with TSM algorithm
            [ES_set(ES_id), task_set] = process_undone_tasks_TSM(ES_set(ES_id), task_set, undone_task_id_set, time, alpha, beta);
        end

        save(filename, 'ED_set', 'ES_set', 'task_set');
        
    catch ME
        fprintf('TSM execution error: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('Error location: %s, line: %d\n', ME.stack(1).name, ME.stack(1).line);
        end
        save(filename, 'ED_set', 'ES_set', 'task_set');
    end
end

function [ES, task_set] = process_undone_tasks_TSM(ES, task_set, undone_task_id_set, time, alpha, beta)
    % TSM's task processing algorithm with partition support
    
    valid_tasks = [];
    valid_task_ids = [];
    
    % Collect valid tasks and calculate TSM costs
    for i = 1:length(undone_task_id_set)
        task_id = undone_task_id_set(i);
        
        if task_id <= 0 || task_id > length(task_set)
            continue;
        end
        
        % Remove expired tasks
        if task_set(task_id).expired_time <= time
            ES = ES.remove_task(task_set(task_id).workload, task_set(task_id).storage, task_set(task_id).memory, task_id, -1);
            task_set(task_id).is_done = -1;
        else
            % Calculate TSM cost function
            if isfield(ES, 'core_nums')
                core_nums = ES.core_nums;
            else
                core_nums = length(ES.core);
            end
            
            if isfield(ES.core(1), 'rate')
                core_rate = ES.core(1).rate;
            else
                core_rate = 5e7; % Default value if not available
            end
            
            task_set(task_id).Tcost = cal_Tcost_based_TSM(task_set(task_id), alpha, beta, core_nums, core_rate);
            
            valid_tasks = [valid_tasks, task_set(task_id)];
            valid_task_ids = [valid_task_ids, task_id];
            
            if task_set(task_id).enter_time == -1
                task_set(task_id).enter_time = time;
            end
        end
    end
    
    if isempty(valid_tasks)
        return;
    end
    
    % Sort tasks by TSM's cost function
    [~, sort_idx] = sort([valid_tasks.Tcost], 'ascend');
    sorted_tasks = valid_tasks(sort_idx);
    sorted_ids = valid_task_ids(sort_idx);
    
    % Process each task
    for i = 1:length(sorted_tasks)
        task_id = sorted_ids(i);
        
        if task_id <= 0 || task_id > length(task_set)
            continue;
        end
        
        % Check if task is partitionable
        if task_set(task_id).is_partition == 1 && isfield(task_set(task_id), 'allowed_partition_ratio') && ~isempty(task_set(task_id).allowed_partition_ratio)
            % Try TSM's partition execution
            [task_set(task_id), ES, partition_success] = execute_partition_TSM(task_set(task_id), ES, time);
            
            if partition_success
                ES = ES.remove_task(task_set(task_id).workload, task_set(task_id).storage, task_set(task_id).memory, task_id, 1);
                continue;
            end
        end
        
        % Fallback to single core execution
        [success, ES, task_set] = execute_single_core_TSM(ES, task_set, task_id, time);
        
        if success
            ES = ES.remove_task(task_set(task_id).workload, task_set(task_id).storage, task_set(task_id).memory, task_id, 1);
        else
            task_set(task_id).is_done = -1;
            ES = ES.remove_task(task_set(task_id).workload, task_set(task_id).storage, task_set(task_id).memory, task_id, -1);
        end
    end
end

function [task, ES, success] = execute_partition_TSM(task, ES, current_time)
    % TSM's partition execution logic - average cut task process
    success = false;
    
    % Check if task is partitionable
    if ~isfield(task, 'allowed_partition_ratio') || isempty(task.allowed_partition_ratio)
        return;
    end
    
    % Get cores that can be used
    test_cores = ES.core;
    can_use_coreID_set = [];
    start_time = [];
    finish_time = [];
    
    % Calculate remaining execution time
    need_execute_time = roundn(task.workload / ES.core(1).rate * 1000, -3);
    
    % Find cores that can be used
    for core_id = 1:length(test_cores)
        if (test_cores(core_id).running_time >= (current_time + 5)) || ...
           (test_cores(core_id).running_time >= task.expired_time)
            % Core is busy or would miss deadline
            continue;
        else
            can_use_coreID_set(end+1) = core_id;
        end
    end
    
    % Needs at least 2 cores for partitioning to be worthwhile
    if length(can_use_coreID_set) <= 1
        % Not enough cores available
        return;
    else
        % TSM approach: divide workload evenly among cores
        average_execute_time = roundn(need_execute_time / length(can_use_coreID_set), -3);
    end
    
    % Check if execution with partitioning will meet deadline
    for core_idx = 1:length(can_use_coreID_set)
        core_id = can_use_coreID_set(core_idx);
        
        if test_cores(core_id).running_time + average_execute_time > task.expired_time
            % One core would miss deadline - entire task fails
            return;
        else
            % Record execution times
            start_time(end+1) = test_cores(core_id).running_time;
            test_cores(core_id).running_time = test_cores(core_id).running_time + average_execute_time;
            finish_time(end+1) = test_cores(core_id).running_time;
        end
    end
    
    % All checks passed, apply the partition execution
    for core_idx = 1:length(can_use_coreID_set)
        core_id = can_use_coreID_set(core_idx);
        ES.core(core_id).running_time = test_cores(core_id).running_time;
    end
    
    % Update task status
    task.is_done = 1;
    task.start_time = min(start_time);
    task.finish_time = max(finish_time);
    success = true;
end

function [success, ES, task_set] = execute_single_core_TSM(ES, task_set, task_id, current_time)
    % TSM's single core execution logic
    success = false;
    
    % TSM selects the earliest available core
    [min_time, best_core] = min([ES.core.running_time]);
    
    % Calculate execution time
    executing_time = task_set(task_id).workload / ES.core(best_core).rate * 1000;
    
    % Check if execution will meet deadline
    exec_bound = task_set(task_id).expired_time - min_time;
    
    if executing_time <= exec_bound
        % Task can be completed in time
        ES.core(best_core).running_time = min_time + executing_time;
        task_set(task_id).is_done = 1;
        task_set(task_id).start_time = min_time;
        task_set(task_id).finish_time = min_time + executing_time;
        success = true;
    end
end

function Tcost = cal_Tcost_based_TSM(task, alpha, beta, core_nums, core_rate)
    % ***** 參數解釋 *****
    % input
    % task:要計算Tcost的任務結構  
    % alpha:調整任務剩餘可執行時間的權重
    % beta:調整任務執行時間的權重
    % core_nums:ES核心數量
    % core_rate:ES核心的處理速度
    % output
    % Tcost:任務的執行成本
    % TSM cost calculation - from original implementation

    % 任務不可分割(task.expired_time應該要改為原本學姊設的delay，即task.expired_time-task.generate_time)
    if task.is_partition == 0
        % For non-partitionable tasks, standard cost 
        Tcost = (alpha * task.expired_time + beta * task.workload/core_rate);
    else % 任務可分割
        % For partitionable tasks, TSM adjusts cost by core count
        % This encourages scheduling partitionable tasks on multi-core systems
        Tcost = (alpha * task.expired_time + beta * task.workload/core_rate * core_nums);
    end
end