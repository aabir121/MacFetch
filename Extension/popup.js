document.getElementById("test").addEventListener("click", () => {
  chrome.runtime.sendMessage({ type: "test", url: "https://example.com/macfetch-extension-test.txt" }, response => {
    document.getElementById("status").textContent = response?.ok ? "MacFetch received the test." : `Bridge error: ${response?.error || "unknown"}`;
  });
});
