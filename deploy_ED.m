% 佈建終端設備(ED)的位置，若ED為不均勻分佈，還會設定熱點ES的屬性
function [ED_set, ES_set] = deploy_ED(totalEDs, uniform, ED_in_hs_nums, ES_set, total_hsESs, ES_radius)
    % *** 參數解釋 ***
    % input
        % totalEDs:ED總數量
        % uniform:ED分佈狀況(0代表不均勻分佈，1代表均勻分佈)
        % ED_in_hs_nums：設置熱點ES固定的ED數量
        % ES_set：ES的集合
        % total_hsESs：熱點ES的數量
        % ES_radius：ES通訊半徑
    % output
        % ED_set：ED的集合。
        % ES_set：ES的集合。
    
    ED_set = []; % ED的集合，存放ED物件

    if uniform == 1 % ED均勻分佈
        x = round(0 + 1550 * rand(totalEDs)); % x座標
        y = round(0 + 1550 * rand(totalEDs)); % y座標
        for i = 1 : totalEDs
            ED_set = [ED_set, ED(i, x(i), y(i))];
        end
    else            % ED不均勻分佈(需亂數選出產生熱點的基地台ID)
        ED_ID = 1;    % 紀錄目前存到第幾個ED
        hsES_ID = []; % 紀錄哪些ES是hs

        while total_hsESs > 0
            while 1
                rand_ID = round(1 + (length(ES_set) - 1) * rand(1, 1)); % 亂數隨機產生熱點的基地台ID)

                if any(hsES_ID == rand_ID)  % 如果重複選到就重選
                    continue;
                else                        % 成功選到
                    hsES_ID(end+1) = rand_ID;       % 將該ID紀錄hsES_ID中
                    ES_set(rand_ID).is_hotspot = 1; % 將ES熱點屬性打開

                    r = ES_radius * sqrt(rand(1, ED_in_hs_nums));
                    seta = 2 * pi * rand(1, ED_in_hs_nums);

                    x = round(ES_set(rand_ID).x + r .* cos(seta));
                    y = round(ES_set(rand_ID).y + r .* sin(seta));

                    % 在該熱點ES下產生ED_in_hs_nums個ED
                    for i = 1 : ED_in_hs_nums
                        ED_set = [ED_set, ED(ED_ID, x(i), y(i))];
                        ED_ID = ED_ID + 1;
                    end

                    total_hsESs = total_hsESs - 1;
                    break; % 找下一個熱點ES
                end

            end
        end

        % 還要產生(所有ED數-所有熱點ES下的ED)個ED
        x = round(0 + 1550 * rand(totalEDs - ED_ID + 1), 1); % x座標
        y = round(0 + 1550 * rand(totalEDs - ED_ID + 1), 1); % y座標
        for i = 1 : (totalEDs - ED_ID + 1)
            ED_set = [ED_set, ED(ED_ID, x(i), y(i))];
            ED_ID = ED_ID + 1;
        end
    end
end

