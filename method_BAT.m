function method_BAT(ED_set, ES_set, task_set, filename, time, transfer_time, newTK_set)
    % === BAT Method: Discrete Bat Algorithm for Task Offloading ===
    % Based on BAT research paper from A_Multihop_Task_Offloading_Decision_Model_in_MEC-Enabled_Internet_of_Vehicles
    
    try
        % Load previous state if available
        if time ~= 1
            try
                load(filename, 'ED_set', 'ES_set', 'task_set');
            catch
                % If loading fails, use input parameters
            end
        else
            % For first execution, ensure complete fields
            if ~isempty(newTK_set)
                newTK_set = ensure_complete_task_fields(newTK_set);
            end
            task_set = newTK_set;
        end
        
        % BAT algorithm forces all tasks to be non-partitionable
        % This is intentional per the BAT paper which uses a discrete assignment approach
        if ~isempty(task_set)
            for i = 1:length(task_set)
                if isfield(task_set(i), 'is_partition')
                    task_set(i).is_partition = 0;
                end
                if isfield(task_set(i), 'allowed_partition_ratio')
                    task_set(i).allowed_partition_ratio = [];
                end
            end
        end
        
        % Similarly update new tasks
        if ~isempty(newTK_set)
            for i = 1:length(newTK_set)
                if isfield(newTK_set(i), 'is_partition')
                    newTK_set(i).is_partition = 0;
                end
                if isfield(newTK_set(i), 'allowed_partition_ratio')
                    newTK_set(i).allowed_partition_ratio = [];
                end
            end
        end
        
        % Safely merge new tasks with existing tasks
        if time ~= 1 && ~isempty(newTK_set)
            if ~isempty(task_set)
                % Unify fields between task sets
                task_set = unify_task_fields(task_set, newTK_set);
                newTK_set = unify_task_fields(newTK_set, task_set);

                % Ensure dimension consistency
                if size(task_set, 1) == 1 && size(newTK_set, 1) > 1
                    task_set = task_set';
                elseif size(task_set, 1) > 1 && size(newTK_set, 1) == 1
                    newTK_set = newTK_set';
                end

                task_set = [task_set, newTK_set];
            else
                task_set = newTK_set;
            end
        end

        % Record entry time for tasks being considered this round
        for i = 1:length(task_set)
            if task_set(i).is_done == 0 && task_set(i).enter_time == -1
                task_set(i).enter_time = time;
            end
        end

        % Mark expired tasks
        for i = 1:length(task_set)
            if task_set(i).is_done == 0 && task_set(i).expired_time <= time
                task_set(i).is_done = -1;
            end
        end

        % Collect tasks for BAT algorithm
        tasks = struct([]);
        task_indices = []; % Track indices in original task_set
        
        for i = 1:length(task_set)
            if task_set(i).is_done == 0
                tasks(end+1).C = task_set(i).workload;
                tasks(end).storage = task_set(i).storage;
                tasks(end).generate_time = task_set(i).generate_time;
                tasks(end).expired_time = task_set(i).expired_time;
                tasks(end).id = length(tasks); % Index in tasks array
                task_indices(end+1) = i; % Actual index in task_set
                
                % Set partition status (always 0 for BAT)
                tasks(end).is_partition = 0;
            end
        end

        % Collect candidate servers (vehicles in BAT paper)
        candidates = struct([]);
        candidate_indices = []; % Track indices in original ES_set
        
        for i = 1:length(ES_set)
            current_storage = ES_set(i).queue_storage;
            current_memory  = ES_set(i).queue_memory;
            if current_storage < ES_set(i).max_storage && current_memory < ES_set(i).max_memory
                % Calculate total processing capability
                total_capacity = sum([ES_set(i).core.rate]);
                candidates(end+1).fj = total_capacity;
                candidates(end).id = length(candidates); % Index in candidates array
                candidate_indices(end+1) = i; % Actual index in ES_set
                
                % Core count info for reference
                candidates(end).available_cores = length(ES_set(i).core);
            end
        end

        if isempty(tasks) || isempty(candidates)
            save(filename, 'ED_set', 'ES_set', 'task_set');
            return;
        end

        % Execute BAT algorithm
        N_pop = 40;  % Bat population size
        N_gen = 100; % Generation count
        bata = 0.85; % Loudness attenuation coefficient
        batr = 0.9;  % Pulse rate increase coefficient
        seed = time; % Random seed for reproducibility

        [~, best_sol] = bat_algorithm_selection(tasks, candidates, N_pop, N_gen, bata, batr, seed);

        % Ensure solution is valid
        best_sol = round(best_sol);
        best_sol(best_sol < 1) = 1;
        best_sol(best_sol > length(candidates)) = length(candidates);

        % Apply the best solution from BAT algorithm
        for idx = 1:length(best_sol)
            if idx <= length(tasks) && idx <= length(task_indices)
                task_idx = task_indices(idx); % Get actual task index
                
                % Validate task index
                if task_idx > length(task_set) || task_idx <= 0
                    continue;
                end
                
                candidate_idx = best_sol(idx);
                if candidate_idx > length(candidate_indices) || candidate_idx <= 0
                    continue;
                end
                
                selected_ES_id = candidate_indices(candidate_idx); % Get actual ES index
                
                % Validate ES index
                if selected_ES_id > length(ES_set) || selected_ES_id <= 0
                    continue;
                end

                % Check storage constraints
                required_storage = task_set(task_idx).storage;
                required_memory  = task_set(task_idx).memory;

                if ES_set(selected_ES_id).queue_storage + required_storage > ES_set(selected_ES_id).max_storage || ...
                   ES_set(selected_ES_id).queue_memory  + required_memory  > ES_set(selected_ES_id).max_memory
                    continue;
                end

                % Assign task to selected ES using single core (BAT doesn't use partitioning)
                [ES_set, task_set] = assign_single_core_task_bat(ES_set, task_set, task_idx, selected_ES_id, time);
            end
        end

        save(filename, 'ED_set', 'ES_set', 'task_set');
        
    catch ME
        fprintf('BAT execution error: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('Error location: %s, line: %d\n', ME.stack(1).name, ME.stack(1).line);
        end
        save(filename, 'ED_set', 'ES_set', 'task_set');
    end
end

function [ES_set, task_set] = assign_single_core_task_bat(ES_set, task_set, task_idx, es_id, time)
    % BAT method's task assignment logic
    
    % Find the best core based on earliest finish time
    core_times = zeros(1, length(ES_set(es_id).core));
    core_rates = zeros(1, length(ES_set(es_id).core));
    
    for j = 1:length(ES_set(es_id).core)
        core_times(j) = ES_set(es_id).core(j).running_time;
        core_rates(j) = ES_set(es_id).core(j).rate;
    end
    
    estimated_exec_times = roundn(task_set(task_idx).workload ./ core_rates * 1000, -3);
    estimated_finish_times = max(time, core_times) + estimated_exec_times;

    [estimated_finish_time, core_id] = min(estimated_finish_times);

    if estimated_finish_time <= task_set(task_idx).expired_time
        % Schedule the task
        ES_set(es_id).core(core_id).running_time = estimated_finish_time;
        ES_set(es_id).queue_storage = ES_set(es_id).queue_storage + task_set(task_idx).storage;
        ES_set(es_id).queue_memory  = ES_set(es_id).queue_memory + task_set(task_idx).memory;
        
        if ~isfield(ES_set(es_id), 'total_workloads')
            ES_set(es_id).total_workloads = 0;
        end
        ES_set(es_id).total_workloads = ES_set(es_id).total_workloads + task_set(task_idx).workload;
        
        if ~isfield(ES_set(es_id), 'undone_task_ID_set')
            ES_set(es_id).undone_task_ID_set = [];
        end
        ES_set(es_id).undone_task_ID_set(end+1) = task_idx;

        % Update task information
        task_set(task_idx).ES_ID = es_id;
        if ~isfield(task_set(task_idx), 'ES_path')
            task_set(task_idx).ES_path = [];
        end
        task_set(task_idx).ES_path(end+1) = es_id;
        task_set(task_idx).is_done = 1;
        task_set(task_idx).start_time = max(time, core_times(core_id));
        task_set(task_idx).finish_time = estimated_finish_time;
    end
end

function tasks = ensure_complete_task_fields(tasks)
    % Ensure all tasks have complete field structure
    required_fields = {'ID', 'is_done', 'retry_count', 'candidate_ES', 'route', ...
                      'ED_ID', 'ES_id', 'workload', 'storage', 'memory', 'is_partition', ...
                      'allowed_partition_ratio', 'expired_time', 'generate_time', ...
                      'start_time', 'finish_time', 'transfer_time', 'ES_path', ...
                      'last_ES_ID', 'fwd_ES_ID', 'Tcost', 'priority_value', ...
                      'status', 'assigned_time', 'enter_time'};
    
    for i = 1:length(tasks)
        for j = 1:length(required_fields)
            field_name = required_fields{j};
            if ~isfield(tasks(i), field_name)
                switch field_name
                    case {'start_time', 'finish_time', 'assigned_time', 'enter_time'}
                        tasks(i).(field_name) = -1;
                    case {'retry_count', 'last_ES_ID', 'fwd_ES_ID', 'ES_id'}
                        tasks(i).(field_name) = 0;
                    case {'candidate_ES', 'route', 'ES_path', 'allowed_partition_ratio'}
                        tasks(i).(field_name) = [];
                    case {'status'}
                        tasks(i).(field_name) = '';
                    case {'transfer_time', 'Tcost', 'priority_value', 'memory'}
                        tasks(i).(field_name) = 0;
                    case {'is_done', 'is_partition'}
                        tasks(i).(field_name) = 0;
                    otherwise
                        tasks(i).(field_name) = [];
                end
            end
        end
    end
end