async function showReleases() {
  const response = await fetch("site-release.json", { cache: "no-cache" });
  if (!response.ok) return;
  const releases = await response.json();

  for (const row of document.querySelectorAll("[data-channel]")) {
    const channel = row.dataset.channel;
    const entry = releases[channel];
    const status = row.querySelector("[data-status]");
    if (entry?.url === null) {
      if (typeof entry.status === "string" && entry.status.trim()) status.textContent = entry.status;
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
    const link = row.querySelector("[data-download]");
    link.href = url.href;
    link.textContent = iphone ? "View on App Store ↗" : "Download DMG ↓";
    link.setAttribute("aria-label", iphone ? "View Relaypad on the App Store" : "Download Relaypad for Mac, " + architecture);
    link.hidden = false;
    status.textContent = "Version " + entry.version;
  }
}
showReleases().catch(() => { /* Release notes and build instructions are available in the HTML fallback. */ });
