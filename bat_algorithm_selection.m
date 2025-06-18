% bat_algorithm_selection.m
% 使用離散蝙蝠演算法 (Discrete Bat Algorithm, DBA) 來尋找最小延遲的任務卸載解
% 輸入：任務列表、候選車輛列表、蝙蝠數量、迭代次數等參數
% 輸出：最終平均延遲（最佳解延遲）與每一代的最佳歷史記錄（收斂曲線）

function [avg_delay, best_sol] = bat_algorithm_selection(tasks, candidates, N_pop, N_gen, bata, batr, seed)
    % 固定隨機種子（提升可重現性）
    if nargin == 7 % 如果呼叫時帶滿 7 個參數，則使用 rng(seed) 固定亂數種子，可重複實驗
        rng(seed);
    end

    n = length(tasks);       % 任務數
    m = length(candidates);  % 候選車輛數（也可理解為可選邊緣節點數）

    % --- 初始化蝙蝠群體 ---
    batX = randi([1, m], N_pop, n);  % 每隻蝙蝠是一個 n 維解，每個元素是對應任務要選哪台車
    velocity = zeros(N_pop, 1);      % 預留變數（原始蝙蝠演算法用來控制速度）
    A = ones(N_pop, 1);              % 每隻蝙蝠的響度（控制局部搜尋接受新解機率）
    r = zeros(N_pop, 1);             % 每隻蝙蝠的 pulse rate（控制跳動策略）

    % --- 評估初始蝙蝠群體的適應度（延遲） ---
    fitness = zeros(N_pop, 1);
    for i = 1:N_pop
        fitness(i) = evaluate_solution(batX(i,:), tasks, candidates);  % 對每隻蝙蝠計算最大延遲
    end
    [best_fitness, best_idx] = min(fitness);     % 找到最佳蝙蝠索引
    best_sol = batX(best_idx, :);                % 對應最佳蝙蝠位置
    % best_fitness = 0.62;

    % --- 紀錄每一代的最佳解 ---
    best_history = zeros(1, N_gen + 1);           % 儲存每回合的最佳延遲（收斂趨勢）
    best_history(1) = best_fitness;              % 第 0 回合為初始族群中最佳值

    % === 主迴圈：演化蝙蝠群體 ===
    for t = 2:N_gen+1
        for i = 1:N_pop
            % === 跳動策略：局部 or 全域搜尋 ===
            if rand > r(i)
                % ======= 局部:增加多個位置替換 =======
                for swap = 1:1
                    idx_change = randi(n);
                    batX(i, idx_change) = best_sol(idx_change);
                end
            else
                % 全域搜尋：隨機更改一個任務的車輛選擇
                idx_change = randi(n);
                batX(i, idx_change) = randi(m);
            end

            % === 評估新解 ===
            new_fit = evaluate_solution(batX(i,:), tasks, candidates);

            % === 接受新解條件：更好 + 機率接受（受響度影響） ===
            if new_fit < fitness(i) && rand < A(i)
                fitness(i) = new_fit;
                A(i) = bata * A(i);               % 衰減響度（越來越難接受新解）
                r(i) = 1 - exp(-batr * (t/N_gen));        % 增加 pulse rate（越來越容易跳動）
            end

            % === 若新解比全域最佳好，就更新全域最佳 ===
            if fitness(i) < best_fitness
                best_fitness = fitness(i);
                best_sol = batX(i,:);
                % 強制所有蝙蝠的某些位置同步（例如每 10 次迭代）
                if mod(t, 10) == 0
                    for j = 1:N_pop
                        batX(j, randi(n)) = best_sol(randi(n)); 
                    end
                end
            end
        end

        % 記錄該回合的最佳延遲
        best_history(t) = best_fitness;
    end

    % 輸出最佳延遲值（平均延遲 = 最佳延遲）
    avg_delay = best_fitness;
end

%% 子函數：計算一個解的總延遲（最大完成時間）
function total_delay = evaluate_solution(sol, tasks, candidates)
    n = length(tasks);
    used = zeros(1, length(candidates));  % 每台車已分配的計算量（考慮排隊）
    delays = zeros(1, n);                 % 每個任務的完成時間

    for i = 1:n
        cidx = sol(i);           % 任務 i 被指派到第 cidx 台車
        C = tasks(i).C;          % 該任務的計算量
        fj = candidates(cidx).fj; % 該車的計算能力
        
        % 延遲 = (前面排隊 + 本任務) / 算力
        delays(i) = (used(cidx) + C) / fj;
        used(cidx) = used(cidx) + C;  % 更新該車的排程工作量
    end

    total_delay = max(delays);  % 總延遲 = 所有任務完成時間的最大值
end
