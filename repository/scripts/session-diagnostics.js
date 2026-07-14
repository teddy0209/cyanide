(() => {
  log("[Session Diagnostics] Starting capability check");
  const appClass = r_class("UIApplication");
  const colorClass = r_class("UIColor");
  const windowClass = r_class("UIWindow");
  log("[Session Diagnostics] UIApplication=" + appClass);
  log("[Session Diagnostics] UIColor=" + colorClass);
  log("[Session Diagnostics] UIWindow=" + windowClass);
  log("[Session Diagnostics] RemoteCall bridge is ready");
})();
