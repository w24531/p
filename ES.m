% ES的定義
classdef ES
    
    properties
        % ***** 初始設定(部署ES時) *****
        ID;               % ES的ID
        x;                % ES的x座標
        y;                % ES的y座標
        max_storage;      % ES最大儲存空間(單位:Kbits)
        max_memory;       % ES最大記憶體容量(單位:MB)
        core_nums;        % 核心數量
        core_rate;        % 核心處理速度(單位:clock cycle/s)
        neighbor_ES = []; % 儲存鄰近伺服器(one-hop)的ID
        % 核心結構參數解釋
            % ID:第幾顆核心
            % rate:該核心處理速度
            % running_time:該核心目前已執行的時間點
        core = struct('ID', {}, ...
                      'rate', {}, ...
                      'running_time', {});
        
        % ***** 初始設定(部署ED時) *****
        is_hotspot = 0; % ES是否為hotspot(0代表不是，1代表是hs)
        
        total_workloads = 0; % 所有未完成的task的工作量總和(單位:clock cycle)
        queue_storage = 0;   % 未完成的task目前占用了多少儲存空間(單位:Kbits)
        queue_memory = 0;    % 未完成的task目前占用了多少記憶體(單位:MB)
        avg_workload;        % 記錄自己和鄰居的平均負載

        undone_task_ID_set = [];  % 未完成的任務之ID
        done_task_ID_set = [];    % 已完成的任務之ID
        expired_task_ID_set = []; % 逾期的任務之ID
    end
    
    methods
        function obj = ES(ID, x, y, max_storage, core_nums, core_rate, max_memory)
            %   ES Construct an instance of this class
            %   Detailed explanation goes here
            obj.ID = ID;
            obj.x = x;
            obj.y = y;
            obj.max_storage = max_storage;
            if nargin < 7
                max_memory = max_storage;
            end
            obj.max_memory = max_memory;
            obj.core_nums = core_nums;
            obj.core_rate = core_rate;
            for i = 1 : obj.core_nums
                obj.core(i).ID = i;
                obj.core(i).rate = core_rate;
                obj.core(i).running_time = 0;
                obj.core(i).start_time = -1; %新增
                obj.core(i).finish_time = 0; %新增
            end
        end
        
        % 找奇數排ES的鄰居伺服器
        function obj = odd_row(obj, row)
            
            neighbor_ID = []; % 存放鄰居的ID

            % row是奇數，代表一定會有左下、右下、左上、右上鄰居
            neighbor_ID(end+1) = obj.ID - 11; % 左下鄰居
            neighbor_ID(end+1) = obj.ID - 10; % 右下鄰居
            neighbor_ID(end+1) = obj.ID + 10; % 左上鄰居
            neighbor_ID(end+1) = obj.ID + 11; % 右上鄰居

            % 需判斷ES是在最左邊還是最右邊
            if obj.ID-floor(row/2)*21 == 1       % ES在最左邊，要加右邊鄰居
                neighbor_ID(end+1) = obj.ID + 1;
            elseif obj.ID-floor(row/2)*21 == 10  % ES在最右邊，要加左邊鄰居
                neighbor_ID(end+1) = obj.ID - 1;
            else                                 % ES不在最邊邊，兩邊鄰居都加
                neighbor_ID(end+1) = obj.ID + 1;
                neighbor_ID(end+1) = obj.ID - 1;
            end

            ID_is_in_range = (neighbor_ID > 0) & (neighbor_ID < 106); % ID要在1~105內的條件
            obj.neighbor_ES = neighbor_ID(ID_is_in_range);            % 篩選掉不是1~105範圍內的ID
        end

        % 找偶數排ES的鄰居伺服器
        function obj = even_row(obj, row)
            
            neighbor_ID = []; % 存放鄰居的ID
  
            if obj.ID-floor(row/2 - 1)*21 == 11       % ES在做左邊，要加右半部鄰居
                neighbor_ID(end+1) = obj.ID + 11; % 右上鄰居
                neighbor_ID(end+1) = obj.ID + 1;  % 右邊鄰居
                neighbor_ID(end+1) = obj.ID - 10; % 右下鄰居
            elseif obj.ID-floor(row/2 - 1)*21 == 21
                neighbor_ID(end+1) = obj.ID + 10; % 左上鄰居
                neighbor_ID(end+1) = obj.ID - 1;  % 左邊鄰居
                neighbor_ID(end+1) = obj.ID - 11; % 左下鄰居
            else
                neighbor_ID(end+1) = obj.ID + 10; % 左上鄰居
                neighbor_ID(end+1) = obj.ID + 11; % 右上鄰居
                neighbor_ID(end+1) = obj.ID - 1;  % 左邊鄰居
                neighbor_ID(end+1) = obj.ID + 1;  % 右邊鄰居
                neighbor_ID(end+1) = obj.ID - 11; % 左下鄰居
                neighbor_ID(end+1) = obj.ID - 10; % 右下鄰居
            end

            ID_is_in_range = (neighbor_ID > 0) & (neighbor_ID < 106); % ID要在1~105內的條件
            obj.neighbor_ES = neighbor_ID(ID_is_in_range);            % 篩選掉不是1~105範圍內的ID
        end

        % 任務加到ES，需更新ES的狀態
        function obj = add_task(obj, workload, storage, memory, task_id)
            obj.total_workloads = obj.total_workloads + workload;   % 更新ES未完成任務之工作量總和
            obj.queue_storage = obj.queue_storage + storage;        % 更新ES未完成任務所佔用的儲存空間
            obj.queue_memory  = obj.queue_memory + memory;          % 更新ES未完成任務所佔用的記憶體
            obj.undone_task_ID_set(end+1) = task_id;                % 將此任務加到undone_task_ID_set
        end

        % 任務被移除(完成、過期、轉發)，需更新ES的狀態
        function obj = remove_task(obj, workload, storage, memory, task_id, done_or_expired)
            obj.total_workloads = obj.total_workloads - workload;   % 更新ES未完成任務之工作量總和
            obj.queue_storage = obj.queue_storage - storage;        % 更新ES未完成任務所佔用的儲存空間
            obj.queue_memory  = obj.queue_memory - memory;          % 更新ES未完成任務所佔用的記憶體
            
            % 將任務從undone_task_ID_set中移除
            delete_idx = find(obj.undone_task_ID_set == task_id);
            obj.undone_task_ID_set(delete_idx) = [];

            % 看此任務是逾期還是完成，將任務加到對應的列表中(done_or_expired=1代表完成，done_or_expired=-1代表逾期，done_or_expired=0代表該任務被搶奪，只須更新ES狀態即可)
            if done_or_expired == 1  % 任務完成
                obj.done_task_ID_set(end+1) = task_id;
            elseif done_or_expired == -1  % 任務逾期
                obj.expired_task_ID_set(end+1) = task_id;
            end
        end
    end
end

