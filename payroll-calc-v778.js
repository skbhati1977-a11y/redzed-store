(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;
  else root.RRPayrollCalcV778=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  const round2=n=>Math.round((Number(n||0)+Number.EPSILON)*100)/100;
  function calculate(input={}){
    const monthly=Math.max(0,Number(input.monthlySalary||0));
    const divisor=Math.max(1,Number(input.salaryDivisorDays||30));
    const normalMinutes=Math.max(1,Number(input.normalMinutes||600));
    const daily=monthly/divisor;
    const minute=daily/normalMinutes;
    const base=input.fullMonth===false
      ?Math.min(monthly,daily*Math.max(0,Number(input.employmentDays||0)))
      :monthly;
    const absenceDays=Math.max(0,Number(input.absentDays||0))+
      Math.max(0,Number(input.unpaidLeaveDays||0))+
      Math.max(0,Number(input.halfDays||0))*0.5;
    const absence=round2(daily*absenceDays);
    const late=round2(minute*Math.max(0,Number(input.deductibleLateMinutes||0)));
    const overtime=round2(minute*Math.max(0,Number(input.payableOvertimeMinutes||0)));
    const holiday=round2(daily*Math.max(0,Number(input.holidayExtraFactorTotal||0)));
    const earnings=round2(Math.max(0,Number(input.adjustmentEarning||0)));
    const deductions=round2(Math.max(0,Number(input.adjustmentDeduction||0)));
    const advance=round2(Math.max(0,Number(input.advanceDeduction||0)));
    const gross=round2(base+overtime+holiday+earnings);
    const totalDeduction=round2(absence+late+deductions+advance);
    return {
      dailyRate:round2(daily),minuteRate:Number(minute.toFixed(6)),baseSalary:round2(base),
      absenceDeduction:absence,lateDeduction:late,overtimeEarning:overtime,
      holidayExtraEarning:holiday,grossPay:gross,totalDeduction,
      netPay:Math.max(0,round2(gross-totalDeduction))
    };
  }
  return {calculate,round2};
});
