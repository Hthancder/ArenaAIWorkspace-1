const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const js = fs.readFileSync(process.argv[2], 'utf8');
const start = js.indexOf('function renderAirChannelBars(');
const end = js.indexOf('\nasync function refreshSecLab()', start);
assert(start >= 0 && end > start);
const context = {}; vm.createContext(context); vm.runInContext(js.slice(start, end), context);
let html = context.renderAirChannelBars({bestCh:1, channels:[
  {ch:1,load:10,retry:2,rssi:-50,sampled:true},
  {ch:6,load:0,retry:0,rssi:0,sampled:false},
  {ch:11,load:null,retry:0,rssi:0,sampled:true},
  {ch:'<img src=x>',load:0,retry:0,rssi:0}
]});
assert(html.includes('CH1: estimated 10% load'));
assert(html.includes('sl-bar-col best'));
assert(html.includes('CH6: not sampled') && html.includes('CH11: not sampled'));
assert(!html.includes('<img'));
assert(context.renderAirChannelBars({channels:[]}).includes('Run WiFi'));
console.log('Radio observation UI regression tests passed');
