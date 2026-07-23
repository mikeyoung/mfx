"use strict";

// A full tab is used instead of a popup so playback does not stop when the
// toolbar panel closes. Creating tabs does not require the broad "tabs"
// permission in Chrome or Firefox.
chrome.action.onClicked.addListener(() => {
  chrome.tabs.create({ url: chrome.runtime.getURL("index.html") });
});
