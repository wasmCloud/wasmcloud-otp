/* global Chart, coreui, coreui.Utils.getStyle */

/**
 * --------------------------------------------------------------------------
 * CoreUI Boostrap Admin Template (3.4.0): main.js
 * License (https://coreui.io/pro/license)
 * --------------------------------------------------------------------------
 */

/* eslint-disable no-magic-numbers */
// Disable the on-canvas tooltip
Chart.defaults.global.pointHitDetectionRadius = 1;
Chart.defaults.global.tooltips.enabled = false;
Chart.defaults.global.tooltips.mode = 'index';
Chart.defaults.global.tooltips.position = 'nearest';
Chart.defaults.global.tooltips.custom = coreui.ChartJS.customTooltips;
Chart.defaults.global.defaultFontColor = coreui.Utils.getStyle('--color', document.getElementsByClassName('c-app')[0]);
document.body.addEventListener('classtoggle', function () {
  cardChart1.data.datasets[0].pointBackgroundColor = coreui.Utils.getStyle('--primary', document.getElementsByClassName('c-app')[0]);
  cardChart2.data.datasets[0].pointBackgroundColor = coreui.Utils.getStyle('--info', document.getElementsByClassName('c-app')[0]);
  sparklineChart1.data.datasets[0].pointBackgroundColor = coreui.Utils.getStyle('--primary', document.getElementsByClassName('c-app')[0]);
  sparklineChart2.data.datasets[0].pointBackgroundColor = coreui.Utils.getStyle('--warning', document.getElementsByClassName('c-app')[0]);
  sparklineChart3.data.datasets[0].pointBackgroundColor = coreui.Utils.getStyle('--success', document.getElementsByClassName('c-app')[0]);
  sparklineChart4.data.datasets[0].borderColor = coreui.Utils.getStyle('--info', document.getElementsByClassName('c-app')[0]);
  sparklineChart5.data.datasets[0].borderColor = coreui.Utils.getStyle('--success', document.getElementsByClassName('c-app')[0]);
  sparklineChart6.data.datasets[0].borderColor = coreui.Utils.getStyle('--danger', document.getElementsByClassName('c-app')[0]);
  Chart.defaults.global.defaultFontColor = coreui.Utils.getStyle('--color', document.getElementsByClassName('c-app')[0]);
  cardChart1.update();
  cardChart2.update();
  sparklineChart1.update();
  sparklineChart2.update();
  sparklineChart3.update();
  sparklineChart4.update();
  sparklineChart5.update();
  sparklineChart6.update();
}); // eslint-disable-next-line no-unused-vars

var cardChart1 = new Chart(document.getElementById('card-chart1'), {
  type: 'line',
  data: {
    labels: ['January', 'February', 'March', 'April', 'May', 'June', 'July'],
    datasets: [{
      label: 'My First dataset',
      backgroundColor: 'transparent',
      borderColor: 'rgba(255,255,255,.55)',
      pointBackgroundColor: coreui.Utils.getStyle('--primary', document.getElementsByClassName('c-app')[0]),
      data: [65, 59, 84, 84, 51, 55, 40]
    }]
  },
  options: {
    maintainAspectRatio: false,
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        gridLines: {
          color: 'transparent',
          zeroLineColor: 'transparent'
        },
        ticks: {
          fontSize: 2,
          fontColor: 'transparent'
        }
      }],
      yAxes: [{
        display: false,
        ticks: {
          display: false,
          min: 35,
          max: 89
        }
      }]
    },
    elements: {
      line: {
        borderWidth: 1
      },
      point: {
        radius: 4,
        hitRadius: 10,
        hoverRadius: 4
      }
    }
  }
}); // eslint-disable-next-line no-unused-vars

var cardChart2 = new Chart(document.getElementById('card-chart2'), {
  type: 'line',
  data: {
    labels: ['January', 'February', 'March', 'April', 'May', 'June', 'July'],
    datasets: [{
      label: 'My First dataset',
      backgroundColor: 'transparent',
      borderColor: 'rgba(255,255,255,.55)',
      pointBackgroundColor: coreui.Utils.getStyle('--info', document.getElementsByClassName('c-app')[0]),
      data: [1, 18, 9, 17, 34, 22, 11]
    }]
  },
  options: {
    maintainAspectRatio: false,
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        gridLines: {
          color: 'transparent',
          zeroLineColor: 'transparent'
        },
        ticks: {
          fontSize: 2,
          fontColor: 'transparent'
        }
      }],
      yAxes: [{
        display: false,
        ticks: {
          display: false,
          min: -4,
          max: 39
        }
      }]
    },
    elements: {
      line: {
        tension: 0.00001,
        borderWidth: 1
      },
      point: {
        radius: 4,
        hitRadius: 10,
        hoverRadius: 4
      }
    }
  }
}); // eslint-disable-next-line no-unused-vars

var cardChart3 = new Chart(document.getElementById('card-chart3'), {
  type: 'line',
  data: {
    labels: ['January', 'February', 'March', 'April', 'May', 'June', 'July'],
    datasets: [{
      label: 'My First dataset',
      backgroundColor: 'rgba(255,255,255,.2)',
      borderColor: 'rgba(255,255,255,.55)',
      data: [78, 81, 80, 45, 34, 12, 40]
    }]
  },
  options: {
    maintainAspectRatio: false,
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        display: false
      }],
      yAxes: [{
        display: false
      }]
    },
    elements: {
      line: {
        borderWidth: 2
      },
      point: {
        radius: 0,
        hitRadius: 10,
        hoverRadius: 4
      }
    }
  }
}); // eslint-disable-next-line no-unused-vars

var cardChart4 = new Chart(document.getElementById('card-chart4'), {
  type: 'bar',
  data: {
    labels: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December', 'January', 'February', 'March', 'April'],
    datasets: [{
      label: 'My First dataset',
      backgroundColor: 'rgba(255,255,255,.2)',
      borderColor: 'rgba(255,255,255,.55)',
      data: [78, 81, 80, 45, 34, 12, 40, 85, 65, 23, 12, 98, 34, 84, 67, 82],
      barPercentage: 0.6
    }]
  },
  options: {
    maintainAspectRatio: false,
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        display: false
      }],
      yAxes: [{
        display: false
      }]
    }
  }
}); // Random Numbers

var random = function random(min, max) {
  return Math.floor(Math.random() * (max - min + 1) + min);
}; // eslint-disable-next-line no-unused-vars


var sparklineChart1 = new Chart(document.getElementById('sparkline-chart-1'), {
  type: 'bar',
  data: {
    labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S', 'M', 'T', 'W', 'T', 'F', 'S', 'S', 'M'],
    datasets: [{
      backgroundColor: coreui.Utils.getStyle('--primary', document.getElementsByClassName('c-app')[0]),
      borderColor: 'transparent',
      borderWidth: 1,
      data: [random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100)]
    }]
  },
  options: {
    maintainAspectRatio: false,
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        display: false
      }],
      yAxes: [{
        display: false
      }]
    }
  }
}); // eslint-disable-next-line no-unused-vars

var sparklineChart2 = new Chart(document.getElementById('sparkline-chart-2'), {
  type: 'bar',
  data: {
    labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S', 'M', 'T', 'W', 'T', 'F', 'S', 'S', 'M'],
    datasets: [{
      backgroundColor: coreui.Utils.getStyle('--warning', document.getElementsByClassName('c-app')[0]),
      borderColor: 'transparent',
      borderWidth: 1,
      data: [random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100)]
    }]
  },
  options: {
    maintainAspectRatio: false,
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        display: false
      }],
      yAxes: [{
        display: false
      }]
    }
  }
}); // eslint-disable-next-line no-unused-vars

var sparklineChart3 = new Chart(document.getElementById('sparkline-chart-3'), {
  type: 'bar',
  data: {
    labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S', 'M', 'T', 'W', 'T', 'F', 'S', 'S', 'M'],
    datasets: [{
      backgroundColor: coreui.Utils.getStyle('--success', document.getElementsByClassName('c-app')[0]),
      borderColor: 'transparent',
      borderWidth: 1,
      data: [random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100)]
    }]
  },
  options: {
    maintainAspectRatio: false,
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        display: false
      }],
      yAxes: [{
        display: false
      }]
    }
  }
}); // eslint-disable-next-line no-unused-vars

var sparklineChart4 = new Chart(document.getElementById('sparkline-chart-4'), {
  type: 'line',
  data: {
    labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
    datasets: [{
      backgroundColor: 'transparent',
      borderColor: coreui.Utils.getStyle('--info', document.getElementsByClassName('c-app')[0]),
      borderWidth: 2,
      data: [random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100)]
    }]
  },
  options: {
    maintainAspectRatio: false,
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        display: false
      }],
      yAxes: [{
        display: false
      }]
    },
    elements: {
      point: {
        radius: 0
      }
    }
  }
}); // eslint-disable-next-line no-unused-vars

var sparklineChart5 = new Chart(document.getElementById('sparkline-chart-5'), {
  type: 'line',
  data: {
    labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
    datasets: [{
      backgroundColor: 'transparent',
      borderColor: coreui.Utils.getStyle('--success', document.getElementsByClassName('c-app')[0]),
      borderWidth: 2,
      data: [random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100)]
    }]
  },
  options: {
    maintainAspectRatio: false,
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        display: false
      }],
      yAxes: [{
        display: false
      }]
    },
    elements: {
      point: {
        radius: 0
      }
    }
  }
}); // eslint-disable-next-line no-unused-vars

var sparklineChart6 = new Chart(document.getElementById('sparkline-chart-6'), {
  type: 'line',
  data: {
    labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
    datasets: [{
      backgroundColor: 'transparent',
      borderColor: coreui.Utils.getStyle('--danger', document.getElementsByClassName('c-app')[0]),
      borderWidth: 2,
      data: [random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100), random(40, 100)]
    }]
  },
  options: {
    maintainAspectRatio: false,
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        display: false
      }],
      yAxes: [{
        display: false
      }]
    },
    elements: {
      point: {
        radius: 0
      }
    }
  }
});
var brandBoxChartLabels = ['January', 'February', 'March', 'April', 'May', 'June', 'July'];
var brandBoxChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  legend: {
    display: false
  },
  scales: {
    xAxes: [{
      display: false
    }],
    yAxes: [{
      display: false
    }]
  },
  elements: {
    point: {
      radius: 0,
      hitRadius: 10,
      hoverRadius: 4,
      hoverBorderWidth: 3
    }
  }
}; // eslint-disable-next-line no-unused-vars

var brandBoxChart1 = new Chart(document.getElementById('social-box-chart-1'), {
  type: 'line',
  data: {
    labels: brandBoxChartLabels,
    datasets: [{
      backgroundColor: 'rgba(255,255,255,.1)',
      borderColor: 'rgba(255,255,255,.55)',
      pointHoverBackgroundColor: '#fff',
      borderWidth: 2,
      data: [65, 59, 84, 84, 51, 55, 40]
    }]
  },
  options: brandBoxChartOptions
}); // eslint-disable-next-line no-unused-vars

var brandBoxChart2 = new Chart(document.getElementById('social-box-chart-2'), {
  type: 'line',
  data: {
    labels: brandBoxChartLabels,
    datasets: [{
      backgroundColor: 'rgba(255,255,255,.1)',
      borderColor: 'rgba(255,255,255,.55)',
      pointHoverBackgroundColor: '#fff',
      borderWidth: 2,
      data: [1, 13, 9, 17, 34, 41, 38]
    }]
  },
  options: brandBoxChartOptions
}); // eslint-disable-next-line no-unused-vars

var brandBoxChart3 = new Chart(document.getElementById('social-box-chart-3'), {
  type: 'line',
  data: {
    labels: brandBoxChartLabels,
    datasets: [{
      backgroundColor: 'rgba(255,255,255,.1)',
      borderColor: 'rgba(255,255,255,.55)',
      pointHoverBackgroundColor: '#fff',
      borderWidth: 2,
      data: [78, 81, 80, 45, 34, 12, 40]
    }]
  },
  options: brandBoxChartOptions
});
//# sourceMappingURL=widgets.js.map