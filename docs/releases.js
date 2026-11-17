async function showReleases() {
  const response = await fetch("site-release.json", { cache: "no-cache" });
  if (!response.ok) return;
  const releases = await response.json();

  for (const row of document.querySelectorAll("[data-channel]")) {
    const channel = row.dataset.channel;
    const entry = releases[channel];
    if (entry?.url === null) {
      row.querySelector("[data-status]").textContent = "Available from source only";
      continue;
    }
    if (typeof entry?.url !== "string" || typeof entry.version !== "string" || !entry.version) continue;
    let url;
    try {
      url = new URL(entry.url);
    } catch {
      continue;
    }
    const iphone = channel === "iphone";
    const architecture = channel === "mac-arm64" ? "arm64" : "x86_64";
    const official = iphone
      ? url.origin === "https://apps.apple.com" && /\/id\d+\/?$/.test(url.pathname)
      : url.origin === "https://github.com" && url.pathname.startsWith("/chheplo/relaypad/releases/download/")
        && url.pathname.endsWith("-macOS-" + architecture + ".dmg");
    if (!official) continue;
    const link = row.querySelector("a");
    link.href = url.href;
    link.textContent = iphone ? "View on App Store ↗" : "Download .dmg ↓";
    link.setAttribute("aria-label", iphone ? "View Relaypad on the App Store" : "Download Relaypad for Mac, " + architecture);
    row.querySelector("[data-status]").textContent = "Version " + entry.version;
  }
}
showReleases().catch(() => { /* Build instructions remain available when the manifest is offline. */ });
