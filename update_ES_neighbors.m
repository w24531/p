function ES_set = update_ES_neighbors(ES_set)
    % 更新ES的鄰居關係
    neighbor_radius = 200;  % 鄰居的最大距離
    
    for i = 1:length(ES_set)
        ES_set(i).neighbor_ES = [];
        xi = ES_set(i).x;
        yi = ES_set(i).y;
        
        for j = 1:length(ES_set)
            if i == j
                continue;
            end
            xj = ES_set(j).x;
            yj = ES_set(j).y;
            dist = sqrt((xi - xj)^2 + (yi - yj)^2);
            
            if dist <= neighbor_radius
                ES_set(i).neighbor_ES(end+1) = j;
            end
        end
    end
end