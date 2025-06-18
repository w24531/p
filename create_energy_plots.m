function create_energy_plots(totalEDs_set, divisible_task_ratios, avg_energy_tsms, avg_energy_props, avg_energy_bats)
    % 创建能耗比较图
    % 输入:
    %   totalEDs_set: 终端设备数量集合
    %   divisible_task_ratios: 可分割任务比例集合
    %   avg_energy_tsms: TSM方法平均能耗数据 (按分割比例和ED数量组织)
    %   avg_energy_props: Proposal方法平均能耗数据
    %   avg_energy_bats: BAT方法平均能耗数据
    % 输出:
    %   生成并保存能耗比较图表

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
    
    % ===== 能耗比较图 =====
    for r = 1:length(divisible_task_ratios)
        % 设置图形
        figure('Position', [100, 100, 800, 600]);
        hold on;
        
        % 绘制三种方法的曲线
        plot(totalEDs_set, avg_energy_tsms(r,:), 'Color', colors{1}, 'LineStyle', line_styles{1}, 'LineWidth', 2, 'Marker', markers{1}, 'MarkerSize', 8, 'MarkerFaceColor', colors{1});
        plot(totalEDs_set, avg_energy_props(r,:), 'Color', colors{2}, 'LineStyle', line_styles{2}, 'LineWidth', 2, 'Marker', markers{2}, 'MarkerSize', 8, 'MarkerFaceColor', colors{2});
        plot(totalEDs_set, avg_energy_bats(r,:), 'Color', colors{3}, 'LineStyle', line_styles{3}, 'LineWidth', 2, 'Marker', markers{3}, 'MarkerSize', 8, 'MarkerFaceColor', colors{3});
        
        % 设置图形属性
        grid on;
        xlabel('終端設備數量', 'FontSize', 14);
        ylabel('平均能耗 (焦耳)', 'FontSize', 14);
        title(sprintf('可分割任務比例 %.0f%%的平均能耗', divisible_task_ratios(r)*100), 'FontSize', 16);
        legend(method_names, 'Location', 'best', 'FontSize', 12, 'Box', 'off');
        
        % 添加网格
        ax = gca;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridLineStyle = ':';
        ax.GridAlpha = 0.3;
        
        % 自动设置Y轴范围以美化图表
        y_data = [avg_energy_tsms(r,:), avg_energy_props(r,:), avg_energy_bats(r,:)];
        y_min = max(0, min(y_data)*0.9);
        y_max = max(y_data)*1.1;
        ylim([y_min, y_max]);
        
        % 设置X轴刻度
        xticks(totalEDs_set);
        
        % 保存图形
        saveas(gcf, sprintf('results/energy_ratio%.0f.png', divisible_task_ratios(r)*100));
        saveas(gcf, sprintf('results/energy_ratio%.0f.fig', divisible_task_ratios(r)*100));
        
        hold off;
        close;
    end
    
    % ===== 综合能耗图 =====
    figure('Position', [100, 100, 1000, 600]);
    
    for r = 1:length(divisible_task_ratios)
        subplot(1, length(divisible_task_ratios), r);
        hold on;
        
        % 绘制三种方法的曲线
        plot(totalEDs_set, avg_energy_tsms(r,:), 'Color', colors{1}, 'LineStyle', line_styles{1}, 'LineWidth', 2, 'Marker', markers{1}, 'MarkerSize', 6, 'MarkerFaceColor', colors{1});
        plot(totalEDs_set, avg_energy_props(r,:), 'Color', colors{2}, 'LineStyle', line_styles{2}, 'LineWidth', 2, 'Marker', markers{2}, 'MarkerSize', 6, 'MarkerFaceColor', colors{2});
        plot(totalEDs_set, avg_energy_bats(r,:), 'Color', colors{3}, 'LineStyle', line_styles{3}, 'LineWidth', 2, 'Marker', markers{3}, 'MarkerSize', 6, 'MarkerFaceColor', colors{3});
        
        % 设置图形属性
        grid on;
        xlabel('終端設備數量', 'FontSize', 11);
        ylabel('平均能耗 (焦耳)', 'FontSize', 11);
        title(sprintf('可分割任務比例 %.0f%%', divisible_task_ratios(r)*100), 'FontSize', 12);
        
        % 添加网格
        ax = gca;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridLineStyle = ':';
        ax.GridAlpha = 0.3;
        
        % 自动设置Y轴范围
        y_data = [avg_energy_tsms(r,:), avg_energy_props(r,:), avg_energy_bats(r,:)];
        y_min = max(0, min(y_data)*0.9);
        y_max = max(y_data)*1.1;
        ylim([y_min, y_max]);
        
        hold off;
    end
    
    % 添加总体图例
    hL = legend(method_names, 'Orientation', 'horizontal');
    newPosition = [0.5, 0.95, 0.001, 0.001]; 
    set(hL, 'Position', newPosition, 'Units', 'normalized');
    
    % 保存综合图表
    saveas(gcf, 'results/combined_energy.png');
    saveas(gcf, 'results/combined_energy.fig');
    close;
    
    % ===== 能耗与分割比例关系分析 =====
    % 为每个ED数量创建一个图表，显示不同分割比例的能耗对比
    for ed_idx = 1:length(totalEDs_set)
        figure('Position', [100, 100, 900, 600]);
        
        % 创建子图
        subplot(2, 1, 1);
        hold on;
        
        % 提取该ED数量下的所有方法、所有分割比例的能耗数据
        tsm_values = zeros(1, length(divisible_task_ratios));
        prop_values = zeros(1, length(divisible_task_ratios));
        bat_values = zeros(1, length(divisible_task_ratios));
        
        for r = 1:length(divisible_task_ratios)
            tsm_values(r) = avg_energy_tsms(r, ed_idx);
            prop_values(r) = avg_energy_props(r, ed_idx);
            bat_values(r) = avg_energy_bats(r, ed_idx);
        end
        
        % 创建分组柱状图
        x_categories = categorical(arrayfun(@(x) sprintf('%.0f%%', x*100), divisible_task_ratios, 'UniformOutput', false));
        bar_data = [tsm_values; prop_values; bat_values]';
        bar_h = bar(x_categories, bar_data);
        
        % 设置柱状图颜色
        for i = 1:length(bar_h)
            bar_h(i).FaceColor = colors{i};
        end
        
        % 设置图形属性
        grid on;
        xlabel('可分割任務比例', 'FontSize', 12);
        ylabel('平均能耗 (焦耳)', 'FontSize', 12);
        title(sprintf('%d個終端設備下的能耗比較', totalEDs_set(ed_idx)), 'FontSize', 14);
        legend(method_names, 'Location', 'best', 'FontSize', 10, 'Box', 'off');
        
        % 添加数据标签
        for i = 1:length(divisible_task_ratios)
            for j = 1:3
                if j <= length(bar_h) && i <= size(bar_data, 1)
                    x_pos = bar_h(j).XEndPoints(i);
                    y_pos = bar_h(j).YEndPoints(i);
                    text(x_pos, y_pos+max(bar_data(:))*0.03, sprintf('%.1f', bar_data(i,j)), ...
                         'HorizontalAlignment', 'center', 'FontSize', 8);
                end
            end
        end
        
        % 添加网格
        ax = gca;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridLineStyle = ':';
        ax.GridAlpha = 0.3;
        
        % 创建子图2：节省率对比
        subplot(2, 1, 2);
        hold on;
        
        % 计算相对于TSM和BAT的节省率
        tsm_savings = zeros(1, length(divisible_task_ratios));
        bat_savings = zeros(1, length(divisible_task_ratios));
        
        for r = 1:length(divisible_task_ratios)
            if tsm_values(r) > 0
                tsm_savings(r) = (tsm_values(r) - prop_values(r)) / tsm_values(r) * 100;
            end
            if bat_values(r) > 0
                bat_savings(r) = (bat_values(r) - prop_values(r)) / bat_values(r) * 100;
            end
        end
        
        % 替换NaN和无穷大
        tsm_savings(isnan(tsm_savings) | isinf(tsm_savings)) = 0;
        bat_savings(isnan(bat_savings) | isinf(bat_savings)) = 0;
        
        % 创建分组柱状图
        savings_data = [tsm_savings; bat_savings]';
        bar_h2 = bar(x_categories, savings_data);
        
        % 设置柱状图颜色
        if length(bar_h2) >= 1
            bar_h2(1).FaceColor = colors{1};
        end
        if length(bar_h2) >= 2
            bar_h2(2).FaceColor = colors{3};
        end
        
        % 设置图形属性
        grid on;
        xlabel('可分割任務比例', 'FontSize', 12);
        ylabel('Proposal能耗節省率 (%)', 'FontSize', 12);
        title(sprintf('%d個終端設備下的能耗節省率', totalEDs_set(ed_idx)), 'FontSize', 14);
        legend({'vs. TSM', 'vs. BAT'}, 'Location', 'best', 'FontSize', 10, 'Box', 'off');
        
        % 添加数据标签
        for i = 1:length(divisible_task_ratios)
            for j = 1:2
                if j <= length(bar_h2) && i <= size(savings_data, 1)
                    x_pos = bar_h2(j).XEndPoints(i);
                    y_pos = bar_h2(j).YEndPoints(i);
                    text(x_pos, y_pos+(max(savings_data(:))+5)*0.05, sprintf('%.1f%%', savings_data(i,j)), ...
                         'HorizontalAlignment', 'center', 'FontSize', 8);
                end
            end
        end
        
        % 添加网格
        ax = gca;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridLineStyle = ':';
        ax.GridAlpha = 0.3;
        
        % 保存图形（禁用個別ED分析圖輸出）
        % saveas(gcf, sprintf('results/energy_analysis_ED%d.png', totalEDs_set(ed_idx)));
        % saveas(gcf, sprintf('results/energy_analysis_ED%d.fig', totalEDs_set(ed_idx)));
        
        hold off;
        close;
    end
end
