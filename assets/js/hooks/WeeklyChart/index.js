// WeeklyChart hook — renders a Chart.js line/bar chart with weekly calorie data.
// The chart data is provided via the `data-chart-data` attribute as JSON.
// Uses `phx-update="ignore"` so LiveView does not override Chart.js DOM changes.

const WeeklyChart = {
  mounted() {
    this.initChart();
  },

  updated() {
    const data = JSON.parse(this.el.dataset.chartData);
    if (this.chart) {
      this.chart.data = data;
      this.chart.update();
    }
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy();
    }
  },

  initChart() {
    const data = JSON.parse(this.el.dataset.chartData);

    // Chart.js must be available globally or imported as a module.
    // In production, add Chart.js to assets/vendor/ or npm install.
    if (typeof Chart === "undefined") {
      return;
    }

    this.chart = new Chart(this.el, {
      type: "bar",
      data: data,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => `${ctx.parsed.y} kcal`,
            },
          },
        },
        scales: {
          y: {
            beginAtZero: true,
            ticks: { callback: (v) => `${v} kcal` },
          },
        },
      },
    });
  },
};

export default WeeklyChart;
