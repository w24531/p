% ED找附近可用的ES(即找ED在哪些ES通訊範圍內)
function [ED_set] = ED_find_ESs(ED_set, ES_set, ES_radius)
    % ***** 參數解釋 *****
    % input
        % ED_set:ED的集合
        % ES_set:ES的集合
        % ES_radius:ES的通訊半徑
    % output
        % ED_set:ED的集合
    
    no_candidate_ED_count = 0; % 沒有在任一ES通訊範圍內的ED數量

    for ED_id = 1 : length(ED_set)
        
        for ES_id = 1 : length(ES_set)
            d = cal_2point_distance(ED_set(ED_id), ES_set(ES_id));
            
            if d <= ES_radius  % 代表ED在ES通訊範圍內
                ED_set(ED_id).candidate_ES(end+1) = ES_set(ES_id).ID;
            end
        end

        if isempty(ED_set(ED_id).candidate_ES) % ED沒找到任何的候選ES
            no_candidate_ED_count = no_candidate_ED_count + 1;
        end
        
    end

    fprintf('num of no candidate: %d\n', no_candidate_ED_count);
end

