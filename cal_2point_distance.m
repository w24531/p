% 求兩點距離
function [distance] = cal_2point_distance(a, b)
    distance = sqrt((a.x - b.x)^2 + (a.y - b.y)^2);
end

