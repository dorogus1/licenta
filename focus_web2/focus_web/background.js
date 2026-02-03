const sitesToBlock = ["facebook.com", "instagram.com", "youtube.com", "tiktok.com"];

// Creăm regulile de blocare
const rules = sitesToBlock.map((site, index) => ({
  id: index + 1,
  priority: 1,
  action: { type: "block" },
  condition: { urlFilter: site, resourceTypes: ["main_frame"] }
}));

chrome.storage.onChanged.addListener((changes) => {
    chrome.storage.local.get(['focusActive', 'blockedSites', 'blockedApps'], (data) => {
        if (data.focusActive && (data.blockedSites || data.blockedApps)) {
            // Combine both lists, remove duplicates
            const allBlocked = [
                ...(data.blockedSites || []),
                ...(data.blockedApps || [])
            ].filter((v, i, arr) => arr.indexOf(v) === i);
            const rules = allBlocked.map((site, index) => ({
                id: index + 1,
                priority: 1,
                action: { 
                    type: "redirect", 
                    redirect: { extensionPath: "/blocked.html" } 
                },
                condition: { urlFilter: site, resourceTypes: ["main_frame"] }
            }));

            chrome.declarativeNetRequest.getDynamicRules(oldRules => {
                const oldIds = oldRules.map(r => r.id);
                chrome.declarativeNetRequest.updateDynamicRules({
                    removeRuleIds: oldIds,
                    addRules: rules
                });
            });
        } else {
            chrome.declarativeNetRequest.getDynamicRules(oldRules => {
                const oldIds = oldRules.map(r => r.id);
                chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds: oldIds });
            });
        }
    });
});