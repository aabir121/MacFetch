const HOST = "com.macfetch.native";
const pendingDownloads = new Map();

function isHttpDownload(download) {
  return Boolean(download?.url && /^https?:/i.test(download.url));
}

function sendToMacFetch(download, filename) {
  if (!isHttpDownload(download)) return;
  chrome.runtime.sendNativeMessage(HOST, {
    type: "download",
    url: download.url,
    filename: filename || download.filename || ""
  }, () => {
    if (chrome.runtime.lastError) console.warn("MacFetch bridge:", chrome.runtime.lastError.message);
  });
}

function interceptDownload(download, filename) {
  // Chrome has already created its own download item at this point. Cancel it
  // before handing the URL to MacFetch so the browser does not save a second
  // copy alongside the MacFetch transfer.
  chrome.downloads.cancel(download.id, () => {
    if (chrome.runtime.lastError) {
      console.warn("MacFetch could not cancel Chrome download:", chrome.runtime.lastError.message);
    }
    chrome.downloads.erase({ id: download.id }, () => {
      if (chrome.runtime.lastError) {
        console.warn("MacFetch could not remove Chrome download:", chrome.runtime.lastError.message);
      }
    });
    sendToMacFetch(download, filename);
  });
}

chrome.downloads.onCreated.addListener(download => {
  if (isHttpDownload(download)) pendingDownloads.set(download.id, download);
});

chrome.downloads.onDeterminingFilename.addListener((download, suggest) => {
  const pending = pendingDownloads.get(download.id);
  if (!pending) {
    suggest();
    return;
  }
  pendingDownloads.delete(download.id);
  interceptDownload(download, download.filename || pending.filename);
  suggest();
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "test") return;
  chrome.runtime.sendNativeMessage(HOST, { type: "download", url: message.url }, response => {
    sendResponse({ ok: !chrome.runtime.lastError && response?.ok !== false, error: chrome.runtime.lastError?.message || response?.error });
  });
  return true;
});
