% Reference implementation for energy optimization through task classification
% This function shows how task classification could be used to optimize energy
% consumption, but is NOT directly integrated into the main workflow

function [task_set] = energy_optimized_task_classification(task_set, ES_set, current_time)
    % System parameters
    LOCAL_ENERGY_PER_CYCLE = 1.5e-9;    % Energy per CPU cycle on mobile device (J)
    TX_ENERGY_PER_BIT = 2e-7;           % Energy per bit for transmission (J)
    SERVER_ENERGY_PER_CYCLE = 5e-10;    % Energy per CPU cycle on server (J)
    BASE_THRESHOLD = 0.9;               % Base deadline threshold
    
    % Calculate system load
    system_load = calculate_system_load_internal(ES_set);
    
    % Adaptive threshold
    threshold = BASE_THRESHOLD * (1 - system_load * 0.2);
    
    % Static clustering parameters
    WORKLOAD_THRESHOLDS = [5e5, 2e6];   % Thresholds for low/medium/high workload
    DATA_SIZE_THRESHOLDS = [2, 4];      % Thresholds for small/medium/large data
    COMPUTATION_INTENSITY_THRESHOLDS = [1e5, 5e5]; % Workload/size thresholds
    
    % Create cluster matrix - each row represents a task's cluster properties
    % [workload_class, data_size_class, computation_intensity_class]
    cluster_matrix = zeros(length(task_set), 3);
    
    % Process each task
    for i = 1:length(task_set)
        % Skip already processed tasks
        if isfield(task_set(i), 'is_done') && task_set(i).is_done ~= 0
            continue;
        end
        
        % Calculate energy consumption for local execution
        local_energy = task_set(i).workload * LOCAL_ENERGY_PER_CYCLE;
        
        % Calculate energy consumption for offloading
        tx_energy = task_set(i).storage * TX_ENERGY_PER_BIT;
        server_energy = task_set(i).workload * SERVER_ENERGY_PER_CYCLE;
        offload_energy = tx_energy + server_energy;
        
        % Calculate delays
        local_delay = task_set(i).workload / 5e7; % Assuming local CPU is 50 MIPS
        
        % Estimate offloading delay (simplified model)
        % TX delay + queueing delay + processing delay
        tx_delay = task_set(i).storage / 1e6; % Assuming 1 Mbps upload
        
        % Find best ES for estimation
        best_es_id = find_best_es_internal(task_set(i), ES_set);
        if best_es_id > 0
            queue_delay = estimate_queue_delay_internal(ES_set(best_es_id));
            process_delay = task_set(i).workload / (ES_set(best_es_id).core_rate * 1000); % Convert to seconds
        else
            % Default estimates if no suitable ES found
            queue_delay = 0.01; % 10ms
            process_delay = task_set(i).workload / 5e7; % Assuming 50 MIPS
        end
        
        offload_delay = tx_delay + queue_delay + process_delay;
        
        % Deadline constraint with threshold
        deadline_constraint = task_set(i).expired_time - current_time;
        
        % Make offloading decision
        if (local_energy <= offload_energy) || (offload_delay > deadline_constraint * threshold)
            task_set(i).allow_offload = 0; % Execute locally
        else
            task_set(i).allow_offload = 1; % Allow offloading
        end
        
        % Perform static clustering
        % Workload classification (1=low, 2=medium, 3=high)
        if task_set(i).workload < WORKLOAD_THRESHOLDS(1)
            cluster_matrix(i, 1) = 1;
        elseif task_set(i).workload < WORKLOAD_THRESHOLDS(2)
            cluster_matrix(i, 1) = 2;
        else
            cluster_matrix(i, 1) = 3;
        end
        
        % Data size classification (1=small, 2=medium, 3=large)
        if task_set(i).storage < DATA_SIZE_THRESHOLDS(1)
            cluster_matrix(i, 2) = 1;
        elseif task_set(i).storage < DATA_SIZE_THRESHOLDS(2)
            cluster_matrix(i, 2) = 2;
        else
            cluster_matrix(i, 2) = 3;
        end
        
        % Computation intensity (workload/data size ratio)
        computation_intensity = task_set(i).workload / task_set(i).storage;
        if computation_intensity < COMPUTATION_INTENSITY_THRESHOLDS(1)
            cluster_matrix(i, 3) = 1; % Low intensity
        elseif computation_intensity < COMPUTATION_INTENSITY_THRESHOLDS(2)
            cluster_matrix(i, 3) = 2; % Medium intensity
        else
            cluster_matrix(i, 3) = 3; % High intensity
        end
        
        % Store clustering info in task
        task_set(i).cluster_info = cluster_matrix(i, :);
        
        % Store energy estimates for later use
        task_set(i).local_energy = local_energy;
        task_set(i).offload_energy = offload_energy;
        task_set(i).energy_saving_ratio = (local_energy - offload_energy) / local_energy;
    end
    
    % Dynamic clustering - adjust priority based on system state
    task_set = dynamic_clustering_adjustment_internal(task_set, ES_set, system_load, current_time);
end

% Internal function for dynamic clustering adjustment
function task_set = dynamic_clustering_adjustment_internal(task_set, ES_set, system_load, current_time)
    % Prioritize based on dynamic system state
    
    % Under high load, prioritize energy efficiency
    if system_load > 0.7
        energy_weight = 0.7;
        deadline_weight = 0.3;
    % Under medium load, balance energy and deadline
    elseif system_load > 0.4
        energy_weight = 0.5;
        deadline_weight = 0.5;
    % Under light load, prioritize meeting deadlines
    else
        energy_weight = 0.3;
        deadline_weight = 0.7;
    end
    
    for i = 1:length(task_set)
        if isfield(task_set(i), 'is_done') && task_set(i).is_done ~= 0
            continue;
        end
        
        if ~isfield(task_set(i), 'allow_offload') || task_set(i).allow_offload == 0
            continue;
        end
        
        % Calculate priority score
        % Higher score = higher priority
        if isfield(task_set(i), 'energy_saving_ratio')
            energy_score = task_set(i).energy_saving_ratio;
        else
            energy_score = 0;
        end
        
        if isfield(task_set(i), 'expired_time')
            deadline_score = 1 / max(0.001, task_set(i).expired_time - current_time);
        else
            deadline_score = 0;
        end
        
        % Combine scores
        task_set(i).priority_score = energy_weight * energy_score + deadline_weight * deadline_score;
        
        % Add cluster-based adjustments
        if isfield(task_set(i), 'cluster_info')
            % High computation intensity tasks get priority boost when offloading
            if task_set(i).cluster_info(3) == 3
                task_set(i).priority_score = task_set(i).priority_score * 1.2;
            end
            
            % Penalize large data size tasks under high load
            if system_load > 0.7 && task_set(i).cluster_info(2) == 3
                task_set(i).priority_score = task_set(i).priority_score * 0.8;
            end
        end
    end
end

% Internal function to calculate system load
function load = calculate_system_load_internal(ES_set)
    % Calculate average system load
    total_load = 0;
    total_capacity = 0;
    
    for i = 1:length(ES_set)
        if isfield(ES_set(i), 'queue_storage') && isfield(ES_set(i), 'max_storage')
            total_load = total_load + ES_set(i).queue_storage;
            total_capacity = total_capacity + ES_set(i).max_storage;
        end
    end
    
    if total_capacity > 0
        load = total_load / total_capacity;
    else
        load = 0.5; % Default medium load
    end
    
    % Bound between 0 and 1
    load = min(1, max(0, load));
end

% Internal function to find the best ES
function best_es_id = find_best_es_internal(task, ES_set)
    best_es_id = 0;
    min_load = inf;
    
    for es_id = 1:length(ES_set)
        % Check storage capacity
        if isfield(ES_set(es_id), 'queue_storage') && isfield(ES_set(es_id), 'max_storage')
            if ES_set(es_id).queue_storage + task.storage <= ES_set(es_id).max_storage
                % Calculate load ratio
                load_ratio = ES_set(es_id).queue_storage / ES_set(es_id).max_storage;
                
                if load_ratio < min_load
                    min_load = load_ratio;
                    best_es_id = es_id;
                end
            end
        end
    end
end

% Internal function to estimate queue delay
function delay = estimate_queue_delay_internal(ES)
    % Estimate queueing delay based on current core utilization
    if isfield(ES, 'core') && length(ES.core) > 0
        core_times = zeros(1, length(ES.core));
        for i = 1:length(ES.core)
            if isfield(ES.core(i), 'running_time')
                core_times(i) = ES.core(i).running_time;
            end
        end
        
        avg_running_time = mean(core_times);
        current_time = min(core_times); % Current simulation time
        
        % Calculate average waiting time
        delay = max(0, avg_running_time - current_time) / 1000; % Convert to seconds
    else
        delay = 0.01; % Default 10ms delay
    end
end