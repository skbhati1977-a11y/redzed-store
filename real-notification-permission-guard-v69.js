(()=>{
  'use strict';
  if(window.__RR_NOTIFICATION_PERMISSION_GUARD_V69__)return;
  window.__RR_NOTIFICATION_PERMISSION_GUARD_V69__=true;
  if(!('Notification' in window)||typeof Notification.requestPermission!=='function')return;
  const nativeRequest=Notification.requestPermission.bind(Notification);
  document.addEventListener('click',event=>{
    if(event.target?.closest?.('#rzPush61Btn,#rzPermNotification')){
      window.__RR_NOTIFICATION_EXPLICIT_TAP_V69__=true;
      setTimeout(()=>{window.__RR_NOTIFICATION_EXPLICIT_TAP_V69__=false},0);
    }
  },true);
  Notification.requestPermission=()=>{
    if(window.__RR_NOTIFICATION_EXPLICIT_TAP_V69__===true){
      window.__RR_NOTIFICATION_EXPLICIT_TAP_V69__=false;
      return nativeRequest();
    }
    return Promise.resolve(Notification.permission);
  };
  window.RRRequestNotificationPermissionV69=()=>{
    window.__RR_NOTIFICATION_EXPLICIT_TAP_V69__=true;
    return Notification.requestPermission();
  };
})();
