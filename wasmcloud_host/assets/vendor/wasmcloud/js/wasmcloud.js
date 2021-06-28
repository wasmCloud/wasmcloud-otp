// // Custom JS for wasmCloud logic goes here
// var cardChart1 = new Chart(document.getElementById('card-chart1'), {
//     type: 'line',
//     data: {
//         labels: ['January', 'February', 'March', 'April', 'May', 'June', 'July'],
//         datasets: [{
//             label: 'My First dataset',
//             backgroundColor: 'transparent',
//             borderColor: 'rgba(255,255,255,.55)',
//             pointBackgroundColor: '#321fdb',
//             data: [65, 59, 84, 84, 51, 55, 40]
//         }]
//     },
//     options: {
//         maintainAspectRatio: false,
//         legend: {
//             display: false
//         },
//         scales: {
//             xAxes: [{
//                 gridLines: {
//                     color: 'transparent',
//                     zeroLineColor: 'transparent'
//                 },
//                 ticks: {
//                     fontSize: 2,
//                     fontColor: 'transparent'
//                 }
//             }],
//             yAxes: [{
//                 display: false,
//                 ticks: {
//                     display: false,
//                     min: 35,
//                     max: 89
//                 }
//             }]
//         },
//         elements: {
//             line: {
//                 borderWidth: 1
//             },
//             point: {
//                 radius: 4,
//                 hitRadius: 10,
//                 hoverRadius: 4
//             }
//         }
//     }
// }); // eslint-disable-next-line no-unused-vars

// var cardChart2 = new Chart(document.getElementById('card-chart2'), {
//     type: 'line',
//     data: {
//         labels: ['January', 'February', 'March', 'April', 'May', 'June', 'July'],
//         datasets: [{
//             label: 'My First dataset',
//             backgroundColor: 'transparent',
//             borderColor: 'rgba(255,255,255,.55)',
//             pointBackgroundColor: '#39f',
//             data: [1, 18, 9, 17, 34, 22, 11]
//         }]
//     },
//     options: {
//         maintainAspectRatio: false,
//         legend: {
//             display: false
//         },
//         scales: {
//             xAxes: [{
//                 gridLines: {
//                     color: 'transparent',
//                     zeroLineColor: 'transparent'
//                 },
//                 ticks: {
//                     fontSize: 2,
//                     fontColor: 'transparent'
//                 }
//             }],
//             yAxes: [{
//                 display: false,
//                 ticks: {
//                     display: false,
//                     min: -4,
//                     max: 39
//                 }
//             }]
//         },
//         elements: {
//             line: {
//                 tension: 0.00001,
//                 borderWidth: 1
//             },
//             point: {
//                 radius: 4,
//                 hitRadius: 10,
//                 hoverRadius: 4
//             }
//         }
//     }
// }); // eslint-disable-next-line no-unused-vars

// var cardChart3 = new Chart(document.getElementById('card-chart3'), {
//     type: 'line',
//     data: {
//         labels: ['January', 'February', 'March', 'April', 'May', 'June', 'July'],
//         datasets: [{
//             label: 'My First dataset',
//             backgroundColor: 'rgba(255,255,255,.2)',
//             borderColor: 'rgba(255,255,255,.55)',
//             data: [78, 81, 80, 45, 34, 12, 40]
//         }]
//     },
//     options: {
//         maintainAspectRatio: false,
//         legend: {
//             display: false
//         },
//         scales: {
//             xAxes: [{
//                 display: false
//             }],
//             yAxes: [{
//                 display: false
//             }]
//         },
//         elements: {
//             line: {
//                 borderWidth: 2
//             },
//             point: {
//                 radius: 0,
//                 hitRadius: 10,
//                 hoverRadius: 4
//             }
//         }
//     }
// }); // eslint-disable-next-line no-unused-vars

// var cardChart4 = new Chart(document.getElementById('card-chart4'), {
//     type: 'bar',
//     data: {
//         labels: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December', 'January', 'February', 'March', 'April'],
//         datasets: [{
//             label: 'My First dataset',
//             backgroundColor: 'rgba(255,255,255,.2)',
//             borderColor: 'rgba(255,255,255,.55)',
//             data: [78, 81, 80, 45, 34, 12, 40, 85, 65, 23, 12, 98, 34, 84, 67, 82],
//             barPercentage: 0.6
//         }]
//     },
//     options: {
//         maintainAspectRatio: false,
//         legend: {
//             display: false
//         },
//         scales: {
//             xAxes: [{
//                 display: false
//             }],
//             yAxes: [{
//                 display: false
//             }]
//         }
//     }
// }); // Random Numbers

// /**
//  * For some reason, stopping the execution of this file here makes the charts load correctly.
//  * Until we figure that out, leave this in.
//  * Thanks, JavaScript.
//  */
// null.ignoreThisError
