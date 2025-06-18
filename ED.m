% ED的類別定義
classdef ED
    
    properties
        % ***** 初始設定(部署ED時) *****
        ID; % ED的ID
        x;  % ED的x座標
        y;  % ED的y座標
        
        % ***** 初始設定(找可用的ES時) *****
        candidate_ES = []; % 附近可用的ES之ID集合(即附近可通訊的ES)(空的代表附近沒ES)
    end
    
    methods
        function obj = ED(ID, x, y)
            %   ED Construct an instance of this class
            %   Detailed explanation goes here
            obj.ID = ID;
            obj.x = x;
            obj.y = y;
        end
    end
end

