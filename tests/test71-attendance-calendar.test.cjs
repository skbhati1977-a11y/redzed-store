const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync(require('node:path').join(__dirname,'../real-attendance-salary-v778.js'),'utf8');
function calendar({month='2026-10',today='2026-10-10',from='2026-09-01',to=null,records=[]}={}){
  const context={state:{attendanceWorkerId:'worker',workers:[{worker_id:'worker',effective_from:from,effective_to:to}],attendance:records,holidays:[]},$:()=>({value:month}),todayDate:()=>today,dayName:d=>new Date(d+'T00:00:00Z').toLocaleDateString('en-IN',{weekday:'short',timeZone:'UTC'}),monthRange:m=>[m+'-01',new Date(Date.UTC(+m.slice(0,4),+m.slice(5,7),0)).toISOString().slice(0,10)]};
  vm.createContext(context);
  const functions=source.slice(source.indexOf('function calendarDates('),source.indexOf('function renderHolidays('));
  vm.runInContext(functions+'; result=attendanceCalendarRows();',context);
  return JSON.parse(JSON.stringify(context.result));
}
test('current month excludes future dates and today is pending',()=>{
  const rows=calendar();assert.equal(rows.length,10);assert.equal(rows.at(-1).attendance_date,'2026-10-10');assert.equal(rows.at(-1).status,'PENDING');assert.ok(rows.every(r=>r.attendance_date<='2026-10-10'));
});
test('future month has no absent rows',()=>assert.deepEqual(calendar({month:'2026-11'}),[]));
test('profile start and end bound attendance',()=>{
  const rows=calendar({from:'2026-10-05',to:'2026-10-07'});assert.deepEqual(rows.map(r=>r.attendance_date),['2026-10-05','2026-10-06','2026-10-07']);
});
test('saved today status takes precedence over virtual pending',()=>{
  const rows=calendar({records:[{id:'saved',attendance_date:'2026-10-10',status:'PRESENT'}]});assert.equal(rows.at(-1).id,'saved');assert.equal(rows.at(-1).status,'PRESENT');
});
