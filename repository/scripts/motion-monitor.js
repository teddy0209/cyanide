(() => {
  let lastState = null;
  const report = () => {
    const accessibility = r_class("UIAccessibility");
    const current = !!r_msg2(accessibility, "isReduceMotionEnabled");
    if (current !== lastState) {
      lastState = current;
      log("[Motion Monitor] Reduce Motion is " + (current ? "enabled" : "disabled"));
    }
  };
  report();
  setInterval(report, 3000);
})();
