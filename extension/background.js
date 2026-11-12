chrome.commands.onCommand.addListener(command => {
  if (command === 'open-dashboard') chrome.tabs.create({url: chrome.runtime.getURL('dashboard.html')});
});
