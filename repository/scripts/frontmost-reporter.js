(() => {
  const report = () => {
    const app = r_msg2(r_class("UIApplication"), "sharedApplication");
    const window = r_msg2(app, "keyWindow");
    log("[Frontmost Reporter] keyWindow=" + window);
  };
  report();
  setInterval(report, 5000);
})();
