import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:school_manager/constants/colors.dart';
import 'package:school_manager/constants/sizes.dart';

class ChartCard extends StatelessWidget {
  final String title;
  final String total;
  final String percentage;
  final double maxY;
  final List<String> bottomTitles;
  final List<double> barValues;
  final double aspectRatio;

  const ChartCard({
    required this.title,
    required this.total,
    required this.percentage,
    required this.maxY,
    required this.bottomTitles,
    required this.barValues,
    required this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSizes.spacing),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.2),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: AppSizes.chartTitleFontSize,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
          SizedBox(height: AppSizes.smallSpacing / 1.5),
          Text(
            total,
            style: TextStyle(
              fontSize: AppSizes.chartValueFontSize,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
          SizedBox(height: AppSizes.smallSpacing / 3),
          Row(
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: AppSizes.textFontSize,
                  color: Theme.of(context).textTheme.bodyMedium!.color,
                ),
              ),
              SizedBox(width: AppSizes.smallSpacing / 1.5),
              Text(
                percentage,
                style: TextStyle(
                  fontSize: AppSizes.textFontSize,
                  fontWeight: FontWeight.w600,
                  color: AppColors.successGreen,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSizes.spacing),
          AspectRatio(
            aspectRatio: aspectRatio,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        rod.toY.toString(),
                        TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          bottomTitles[value.toInt()],
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyMedium!.color,
                            fontSize: AppSizes.smallTextFontSize,
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyMedium!.color,
                            fontSize: AppSizes.smallTextFontSize,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: barValues
                    .asMap()
                    .entries
                    .map(
                      (entry) => BarChartGroupData(
                        x: entry.key,
                        barRods: [
                          BarChartRodData(toY: entry.value, color: AppColors.primaryBlue),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}