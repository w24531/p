function create_energy_efficiency_plots(totalEDs_set, divisible_task_ratios, avg_eff_tsms, avg_eff_props, avg_eff_bats, suffix)
    % 创建能效比比较图
    % 输入:
    %   totalEDs_set: 终端设备数量集合
    %   divisible_task_ratios: 可分割任务比例集合
    %   avg_eff_tsms: TSM方法能效比数据 (按分割比例和ED数量组织)
    %   avg_eff_props: Proposal方法能效比数据
    %   avg_eff_bats: BAT方法能效比数据
    % 输出:
    %   生成并保存能效比比较图表

    if nargin < 6
        suffix = '';
    else
        suffix = ['_' suffix];
    end

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

    % ===== 能效比比较图 =====
    for r = 1:length(divisible_task_ratios)
        % 设置图形
        figure('Position', [100, 100, 800, 600]);
        hold on;

        % 绘制三种方法的曲线
        plot(totalEDs_set, avg_eff_tsms(r,:), 'Color', colors{1}, 'LineStyle', line_styles{1}, 'LineWidth', 2, 'Marker', markers{1}, 'MarkerSize', 8, 'MarkerFaceColor', colors{1});
        plot(totalEDs_set, avg_eff_props(r,:), 'Color', colors{2}, 'LineStyle', line_styles{2}, 'LineWidth', 2, 'Marker', markers{2}, 'MarkerSize', 8, 'MarkerFaceColor', colors{2});
        plot(totalEDs_set, avg_eff_bats(r,:), 'Color', colors{3}, 'LineStyle', line_styles{3}, 'LineWidth', 2, 'Marker', markers{3}, 'MarkerSize', 8, 'MarkerFaceColor', colors{3});

        % 设置图形属性
        grid on;
        xlabel('UE數量', 'FontSize', 14);
        ylabel('能效比 (bit/J)', 'FontSize', 14);
        title(sprintf('能效比 - %.0f%%可分割', divisible_task_ratios(r)*100), 'FontSize', 16);
        legend(method_names, 'Location', 'best', 'FontSize', 12, 'Box', 'off');

        % 添加网格
        ax = gca;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridLineStyle = ':';
        ax.GridAlpha = 0.3;

        % 自动设置Y轴范围以美化图表
        y_data = [avg_eff_tsms(r,:), avg_eff_props(r,:), avg_eff_bats(r,:)];
        y_min = max(0, min(y_data)*0.9);
        y_max = max(y_data)*1.1;
        ylim([y_min, y_max]);

        % 设置X轴刻度
        xticks(totalEDs_set);

        % 保存图形
        saveas(gcf, sprintf('results/energy_efficiency_ratio%.0f%s.png', divisible_task_ratios(r)*100, suffix));
        saveas(gcf, sprintf('results/energy_efficiency_ratio%.0f%s.fig', divisible_task_ratios(r)*100, suffix));

        hold off;
        close;
    end

    % ===== 综合能效比图 =====
    figure('Position', [100, 100, 1000, 600]);

    for r = 1:length(divisible_task_ratios)
        subplot(1, length(divisible_task_ratios), r);
        hold on;

        % 绘制三种方法的曲线
        plot(totalEDs_set, avg_eff_tsms(r,:), 'Color', colors{1}, 'LineStyle', line_styles{1}, 'LineWidth', 2, 'Marker', markers{1}, 'MarkerSize', 6, 'MarkerFaceColor', colors{1});
        plot(totalEDs_set, avg_eff_props(r,:), 'Color', colors{2}, 'LineStyle', line_styles{2}, 'LineWidth', 2, 'Marker', markers{2}, 'MarkerSize', 6, 'MarkerFaceColor', colors{2});
        plot(totalEDs_set, avg_eff_bats(r,:), 'Color', colors{3}, 'LineStyle', line_styles{3}, 'LineWidth', 2, 'Marker', markers{3}, 'MarkerSize', 6, 'MarkerFaceColor', colors{3});

        % 设置图形属性
        grid on;
        xlabel('UE數量', 'FontSize', 11);
        ylabel('能效比 (bit/J)', 'FontSize', 11);
        title(sprintf('可分割任務比例 %.0f%%', divisible_task_ratios(r)*100), 'FontSize', 12);

        % 添加网格
        ax = gca;
        ax.XGrid = 'on';
        ax.YGrid = 'on';
        ax.GridLineStyle = ':';
        ax.GridAlpha = 0.3;

        % 自动设置Y轴范围
        y_data = [avg_eff_tsms(r,:), avg_eff_props(r,:), avg_eff_bats(r,:)];
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
    saveas(gcf, ['results/combined_energy_efficiency' suffix '.png']);
    saveas(gcf, ['results/combined_energy_efficiency' suffix '.fig']);
    close;

    % ===== 能效比與分割比例關係分析 =====
    for ed_idx = 1:length(totalEDs_set)
        figure('Position', [100, 100, 900, 600]);

        % 创建子图1：能效比對比
        subplot(2, 1, 1);
        hold on;

        % 提取該ED數量下的所有方法、所有分割比例的能效比數據
        tsm_values = zeros(1, length(divisible_task_ratios));
        prop_values = zeros(1, length(divisible_task_ratios));
        bat_values = zeros(1, length(divisible_task_ratios));

        for r = 1:length(divisible_task_ratios)
            tsm_values(r) = avg_eff_tsms(r, ed_idx);
            prop_values(r) = avg_eff_props(r, ed_idx);
            bat_values(r) = avg_eff_bats(r, ed_idx);
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
        ylabel('能效比 (bit/J)', 'FontSize', 12);
        title(sprintf('%d個UE下的能效比比較', totalEDs_set(ed_idx)), 'FontSize', 14);
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

        % 创建子图2：提升率對比
        subplot(2, 1, 2);
        hold on;

        % 计算相对于TSM和BAT的提升率
        tsm_improve = zeros(1, length(divisible_task_ratios));
        bat_improve = zeros(1, length(divisible_task_ratios));

        for r = 1:length(divisible_task_ratios)
            if tsm_values(r) > 0
                tsm_improve(r) = (prop_values(r) - tsm_values(r)) / tsm_values(r) * 100;
            end
            if bat_values(r) > 0
                bat_improve(r) = (prop_values(r) - bat_values(r)) / bat_values(r) * 100;
            end
        end

        % 替換NaN和無窮大
        tsm_improve(isnan(tsm_improve) | isinf(tsm_improve)) = 0;
        bat_improve(isnan(bat_improve) | isinf(bat_improve)) = 0;

        % 创建分组柱状图
        improve_data = [tsm_improve; bat_improve]';
        bar_h2 = bar(x_categories, improve_data);

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
        ylabel('Proposal能效提升率 (%)', 'FontSize', 12);
        title(sprintf('%d個UE下的能效提升率', totalEDs_set(ed_idx)), 'FontSize', 14);
        legend({'vs. TSM', 'vs. BAT'}, 'Location', 'best', 'FontSize', 10, 'Box', 'off');

        % 添加数据标签
        for i = 1:length(divisible_task_ratios)
            for j = 1:2
                if j <= length(bar_h2) && i <= size(improve_data, 1)
                    x_pos = bar_h2(j).XEndPoints(i);
                    y_pos = bar_h2(j).YEndPoints(i);
                    text(x_pos, y_pos+(max(improve_data(:))+5)*0.05, sprintf('%.1f%%', improve_data(i,j)), ...
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

        % 保存图形（禁用個別ED能效圖輸出）
        % saveas(gcf, sprintf('results/energy_efficiency_analysis_ED%d.png', totalEDs_set(ed_idx)));
        % saveas(gcf, sprintf('results/energy_efficiency_analysis_ED%d.fig', totalEDs_set(ed_idx)));

        hold off;
        close;
    end
end