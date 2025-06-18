function create_energy_per_task_plot(totalEDs_set, divisible_task_ratios, avg_energy_props, avg_energy_tsms, avg_energy_bats)
    % 创建每任务能耗比较图
    % 输入:
    %   totalEDs_set: 终端设备数量集合
    %   divisible_task_ratios: 可分割任务比例集合
    %   avg_energy_props: Proposal方法平均能耗数据
    %   avg_energy_tsms: TSM方法平均能耗数据
    %   avg_energy_bats: BAT方法平均能耗数据
    % 输出:
    %   生成并保存每任务能耗比较图表

    % 设置颜色和线型
    colors = {[0.0 0.4470 0.7410], [0.8500 0.3250 0.0980], [0.9290 0.6940 0.1250]};
    markers = {'o', 's', 'd'};
    line_styles = {'-', '--', ':'};
    
    % 设置图例
    method_names = {'TSM', 'Proposal', 'BAT'};
    
    % 创建保存图表的文件夹
    if ~exist('results', 'dir')
        mkdir('results');
    end
    
    % 假设每个设备生成任务的比例
    task_ratio = 0.15;
    
    % ===== 每任务能耗比较图 =====
    for r = 1:length(divisible_task_ratios)
        % 设置图形
        figure('Position', [100, 100, 800, 600]);
        hold on;
        
        % 计算每个任务的平均能耗
        tsm_energy_per_task = zeros(size(totalEDs_set));
        prop_energy_per_task = zeros(size(totalEDs_set));
        bat_energy_per_task = zeros(size(totalEDs_set));
        
        for i = 1:length(totalEDs_set)
            ed_count = totalEDs_set(i);
            estimated_tasks = round(ed_count * task_ratio);
            
            % 防止除零
            if estimated_tasks > 0
                tsm_energy_per_task(i) = avg_energy_tsms(r,i);
                prop_energy_per_task(i) = avg_energy_props(r,i);
                bat_energy_per_task(i) = avg_energy_bats(r,i);
            end
        end
        
        % 绘制三种方法的曲线
        plot(totalEDs_set, tsm_energy_per_task, 'Color', colors{1}, 'LineStyle', line_styles{1}, 'LineWidth', 2, 'Marker', markers{1}, 'MarkerSize', 8, 'MarkerFaceColor', colors{1});
        plot(totalEDs_set, prop_energy_per_task, 'Color', colors{2}, 'LineStyle', line_styles{2}, 'LineWidth', 2, 'Marker', markers{2}, 'MarkerSize', 8, 'MarkerFaceColor', colors{2});
        plot(totalEDs_set, bat_energy_per_task, 'Color', colors{3}, 'LineStyle', line_styles{3}, 'LineWidth', 2, 'Marker', markers{3}, 'MarkerSize', 8, 'MarkerFaceColor', colors{3});
        
        % 设置图形属性
        grid on;
        xlabel('終端設備數量', 'FontSize', 14);
        ylabel('每任務平均能耗 (焦耳/任務)', 'FontSize', 14);
        title(sprintf('可分割任務比例 %.0f%%的每任務平均能耗', divisible_task_ratios(r)*100), 'FontSize', 16);
        legend(method_names, 'Location', 'best', 'FontSize', 12, 'Box', 'off');
        
        % 添加网格
        ax = gca;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridLineStyle = ':';
        ax.GridAlpha = 0.3;
        
        % 设置X轴刻度
        xticks(totalEDs_set);
        
        % 自动设置Y轴范围以美化图表
        y_data = [tsm_energy_per_task, prop_energy_per_task, bat_energy_per_task];
        y_data(y_data == 0) = NaN; % 忽略零值
        y_min = max(0, nanmin(y_data(:))*0.9);
        y_max = nanmax(y_data(:))*1.1;
        ylim([y_min y_max]);
        
        % 保存图形
        saveas(gcf, sprintf('results/energy_per_task_ratio%.0f.png', divisible_task_ratios(r)*100));
        saveas(gcf, sprintf('results/energy_per_task_ratio%.0f.fig', divisible_task_ratios(r)*100));
        
        hold off;
        close;
    end

    % ===== 每任务能耗效率提升分析 =====
    for r = 1:length(divisible_task_ratios)
        figure('Position', [100, 100, 800, 600]);
        hold on;
        
        % 计算每个任务的平均能耗
        tsm_energy_per_task = zeros(size(totalEDs_set));
        prop_energy_per_task = zeros(size(totalEDs_set));
        bat_energy_per_task = zeros(size(totalEDs_set));
        
        for i = 1:length(totalEDs_set)
            ed_count = totalEDs_set(i);
            estimated_tasks = round(ed_count * task_ratio);
            
            % 防止除零
            if estimated_tasks > 0
                tsm_energy_per_task(i) = avg_energy_tsms(r,i);
                prop_energy_per_task(i) = avg_energy_props(r,i);
                bat_energy_per_task(i) = avg_energy_bats(r,i);
            end
        end
        
        % 计算每任务能耗节省率
        tsm_energy_reduction = (tsm_energy_per_task - prop_energy_per_task) ./ tsm_energy_per_task * 100; % 百分比
        bat_energy_reduction = (bat_energy_per_task - prop_energy_per_task) ./ bat_energy_per_task * 100; % 百分比
        
        % 替换NaN和无限值
        tsm_energy_reduction(isnan(tsm_energy_reduction) | isinf(tsm_energy_reduction)) = 0;
        bat_energy_reduction(isnan(bat_energy_reduction) | isinf(bat_energy_reduction)) = 0;
        
        % 绘制能耗效率提升曲线
        plot(totalEDs_set, tsm_energy_reduction, 'Color', colors{1}, 'LineStyle', line_styles{1}, 'LineWidth', 2, 'Marker', markers{1}, 'MarkerSize', 8, 'MarkerFaceColor', colors{1});
        plot(totalEDs_set, bat_energy_reduction, 'Color', colors{3}, 'LineStyle', line_styles{3}, 'LineWidth', 2, 'Marker', markers{3}, 'MarkerSize', 8, 'MarkerFaceColor', colors{3});
        
        % 绘制零线
        plot(totalEDs_set, zeros(size(totalEDs_set)), 'k--', 'LineWidth', 1);
        
        % 设置图形属性
        grid on;
        xlabel('終端設備數量', 'FontSize', 14);
        ylabel('每任務能耗節省率 (%)', 'FontSize', 14);
        title(sprintf('Proposal在%.0f%%可分割任務下的每任務能耗效率提升', divisible_task_ratios(r)*100), 'FontSize', 16);
        legend({'vs. TSM', 'vs. BAT', 'No change'}, 'Location', 'best', 'FontSize', 12, 'Box', 'off');
        
        % 添加网格
        ax = gca;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridLineStyle = ':';
        ax.GridAlpha = 0.3;
        
        % 设置X轴刻度
        xticks(totalEDs_set);
        
        % 自动设置Y轴范围以美化图表
        y_data = [tsm_energy_reduction, bat_energy_reduction];
        y_min = min(min(y_data)-5, -5);  % 确保零线可见
        y_max = max(max(y_data)+5, 5);   % 确保零线可见
        ylim([y_min, y_max]);
        
        % 保存图形（禁用效率提升圖輸出）
        % saveas(gcf, sprintf('results/energy_per_task_reduction_ratio%.0f.png', divisible_task_ratios(r)*100));
        % saveas(gcf, sprintf('results/energy_per_task_reduction_ratio%.0f.fig', divisible_task_ratios(r)*100));
        
        hold off;
        close;
    end
    
    % ===== 综合每任务能耗图 =====
    figure('Position', [100, 100, 1000, 600]);
    
    for r = 1:length(divisible_task_ratios)
        subplot(1, length(divisible_task_ratios), r);
        hold on;
        
        % 计算每个任务的平均能耗
        tsm_energy_per_task = zeros(size(totalEDs_set));
        prop_energy_per_task = zeros(size(totalEDs_set));
        bat_energy_per_task = zeros(size(totalEDs_set));
        
        for i = 1:length(totalEDs_set)
            ed_count = totalEDs_set(i);
            estimated_tasks = round(ed_count * task_ratio);
            
            % 防止除零
            if estimated_tasks > 0
                tsm_energy_per_task(i) = avg_energy_tsms(r,i);
                prop_energy_per_task(i) = avg_energy_props(r,i);
                bat_energy_per_task(i) = avg_energy_bats(r,i);
            end
        end
        
        % 绘制三种方法的曲线
        plot(totalEDs_set, tsm_energy_per_task, 'Color', colors{1}, 'LineStyle', line_styles{1}, 'LineWidth', 2, 'Marker', markers{1}, 'MarkerSize', 6, 'MarkerFaceColor', colors{1});
        plot(totalEDs_set, prop_energy_per_task, 'Color', colors{2}, 'LineStyle', line_styles{2}, 'LineWidth', 2, 'Marker', markers{2}, 'MarkerSize', 6, 'MarkerFaceColor', colors{2});
        plot(totalEDs_set, bat_energy_per_task, 'Color', colors{3}, 'LineStyle', line_styles{3}, 'LineWidth', 2, 'Marker', markers{3}, 'MarkerSize', 6, 'MarkerFaceColor', colors{3});
        
        % 设置图形属性
        grid on;
        xlabel('終端設備數量', 'FontSize', 11);
        ylabel('每任務能耗 (焦耳/任務)', 'FontSize', 11);
        title(sprintf('可分割任務比例 %.0f%%', divisible_task_ratios(r)*100), 'FontSize', 12);
        
        % 添加网格
        ax = gca;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridLineStyle = ':';
        ax.GridAlpha = 0.3;
        
        % 自动设置Y轴范围
        y_data = [tsm_energy_per_task, prop_energy_per_task, bat_energy_per_task];
        y_data(y_data == 0) = NaN; % 忽略零值
        y_min = max(0, nanmin(y_data(:))*0.9);
        y_max = nanmax(y_data(:))*1.1;
        ylim([y_min y_max]);
        
        hold off;
    end
    
    % 添加总体图例
    hL = legend(method_names, 'Orientation', 'horizontal');
    newPosition = [0.5, 0.95, 0.001, 0.001]; 
    set(hL, 'Position', newPosition, 'Units', 'normalized');
    
    % 保存综合图表
    saveas(gcf, 'results/combined_energy_per_task.png');
    saveas(gcf, 'results/combined_energy_per_task.fig');
    close;
    
    % ===== 分割比例对每任务能耗的影响 =====
    % 为每个ED数量创建柱状图
    for ed_idx = 1:length(totalEDs_set)
        figure('Position', [100, 100, 800, 600]);
        hold on;
        
        % 提取该ED数量下的所有方法、所有分割比例的每任务能耗数据
        tsm_values = zeros(1, length(divisible_task_ratios));
        prop_values = zeros(1, length(divisible_task_ratios));
        bat_values = zeros(1, length(divisible_task_ratios));
        
        ed_count = totalEDs_set(ed_idx);
        estimated_tasks = round(ed_count * task_ratio);
        
        if estimated_tasks > 0
            for r = 1:length(divisible_task_ratios)
                tsm_values(r) = avg_energy_tsms(r, ed_idx) / estimated_tasks;
                prop_values(r) = avg_energy_props(r, ed_idx) / estimated_tasks;
                bat_values(r) = avg_energy_bats(r, ed_idx) / estimated_tasks;
            end
        end
        
        % 创建分组柱状图
        x_categories = categorical(arrayfun(@(x) sprintf('%.0f%%', x*100), divisible_task_ratios, 'UniformOutput', false));
        
        % 修复：确保数据维度匹配 - 创建正确维度的数据矩阵
        bar_data = [tsm_values; prop_values; bat_values]';  % 转置以匹配维度
        
        % 创建分组柱状图
        bar_h = bar(x_categories, bar_data);
        
        % 设置柱状图颜色
        for i = 1:length(bar_h)
            bar_h(i).FaceColor = colors{i};
        end
        
        % 设置图形属性
        grid on;
        xlabel('可分割任務比例', 'FontSize', 13);
        ylabel('每任務能耗 (焦耳/任務)', 'FontSize', 13);
        title(sprintf('%d個終端設備下不同分割比例的每任務能耗', totalEDs_set(ed_idx)), 'FontSize', 15);
        legend(method_names, 'Location', 'best', 'FontSize', 12, 'Box', 'off');
        
        % 添加数据标签
        for i = 1:length(divisible_task_ratios)
            for j = 1:3
                if j <= length(bar_h) && i <= size(bar_data, 1)
                    x_pos = bar_h(j).XEndPoints(i);
                    y_pos = bar_h(j).YEndPoints(i);
                    text(x_pos, y_pos+max(bar_data(:))*0.03, sprintf('%.2f', bar_data(i,j)), ...
                         'HorizontalAlignment', 'center', 'FontSize', 9);
                end
            end
        end
        
        % 添加网格
        ax = gca;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridLineStyle = ':';
        ax.GridAlpha = 0.3;
        
        % 自动设置Y轴范围
        y_min = 0;
        y_max = max(bar_data(:))*1.2;
        ylim([y_min, y_max]);
        
        % 保存圖形（禁用個別ED每任務能耗圖輸出）
        % saveas(gcf, sprintf('results/energy_per_task_analysis_ED%d.png', totalEDs_set(ed_idx)));
        % saveas(gcf, sprintf('results/energy_per_task_analysis_ED%d.fig', totalEDs_set(ed_idx)));
        
        hold off;
        close;
    end
end
