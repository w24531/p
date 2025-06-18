function nearest_id = find_nearest_ES(ED, ES_set)
% === 傳回最近的 Edge Server ID ===
% 根據輸入的 ED 與所有 ES 座標，計算最近距離並回傳 ES ID

    if isempty(ES_set)
        error('ES_set 為空，無法判斷最近 ES');
    end

    min_dist = inf;
    nearest_id = -1;

    for i = 1:length(ES_set)
        dx = ES_set(i).x - ED.x;
        dy = ES_set(i).y - ED.y;
        dist = sqrt(dx^2 + dy^2);

        if dist < min_dist
            min_dist = dist;
            nearest_id = i;
        end
    end
end
