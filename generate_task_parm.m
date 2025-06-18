% 根據任務參數範圍，隨機產生任務的各個參數
function [r] = generate_task_parm(a, b, is_round)
    if is_round == 1  % 四捨五入到整數
        r = round(a + (b - a) * rand(1, 1));
    else              % 四捨五入到小數點後第二位
        r = roundn(a + (b - a) * rand(1, 1), -2);
    end
end
