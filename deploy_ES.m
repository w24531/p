% 佈建邊緣伺服器(ES)的位置，設定他們的鄰居(one hop)有誰，並設定核心相關資訊
function [ES_set] = deploy_ES(max_storage, core_nums, core_rate, max_memory)
    % *** 參數解釋 ***
    % input
        % max_storage:ES最大儲存空間(單位:Kbits)
        % core_nums:各個ES的核心數
        % core_rate:核心處理速度(單位:clock cycle/s)
        % max_memory:ES最大記憶體容量(單位:MB)
    % output
        % ES_set:ES的集合

    if nargin < 4
        max_memory = max_storage;
    end
    ES_set = []; % ES集合，存放ES物件
    ES_id = 1;   % ES的ID從1開始編號
    row = 1;

    for y = 100:150:1450  % y座標
        
        if mod(row,2) == 1  % 奇數row
            for x = 100:150:1450  % x座標，從100開始，每次加150，加到1450
                ES_set = [ES_set, ES(ES_id, x, y, max_storage, core_nums, core_rate, max_memory)];
                ES_set(ES_id) = ES_set(ES_id).odd_row(row); % 找鄰居伺服器
                ES_id = ES_id + 1;
            end
        else                % 偶數row
            for x = 25:150:1525  % x座標，從25開始，每次加150，加到1525
                ES_set = [ES_set, ES(ES_id, x, y, max_storage, core_nums, core_rate, max_memory)];
                ES_set(ES_id) = ES_set(ES_id).even_row(row); % 找鄰居伺服器
                ES_id = ES_id + 1;
            end
        end

        row = row + 1;
        
    end
end