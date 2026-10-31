const HOST = "com.macfetch.native";

function sendToMacFetch(download) {
  if (!download?.url || !/^https?:/i.test(download.url)) return;
  chrome.runtime.sendNativeMessage(HOST, {
    type: "download",
    url: download.url,
    filename: download.filename || ""
  }, () => {
    if (chrome.runtime.lastError) console.warn("MacFetch bridge:", chrome.runtime.lastError.message);
  });
}

chrome.downloads.onCreated.addListener(sendToMacFetch);

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "test") return;
  chrome.runtime.sendNativeMessage(HOST, { type: "download", url: message.url }, response => {
    sendResponse({ ok: !chrome.runtime.lastError && response?.ok !== false, error: chrome.runtime.lastError?.message || response?.error });
  });
  return true;
});
