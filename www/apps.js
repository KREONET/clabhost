// Rail contents.
//
// This file exists to be edited. Add, remove or reorder entries and reload the
// portal -- nothing else needs to change. Served as a plain script, so there is
// no build step and no bundler.
//
// key   value in /?app=<key>, so changing it breaks existing links
// name  rail label
// sub   shown next to the label in the stage bar
// path  where the app lives; used for the frame, the rail href and pop-out
// ping  polled every 30s for the status dot. Pick something cheap that answers
//       even when the app is not interactive -- a health endpoint beats the
//       document, which may be a multi-megabyte bundle.
// icon  inline SVG at 17x17, stroke="currentColor" so it follows the theme
window.CLABHOST_APPS = [
  {
    key: "clab",
    name: "Topology",
    sub: "containerlab WebUI",
    path: "/clab/",
    ping: "/clab/",
    icon:
      '<svg width="17" height="17" viewBox="0 0 18 18" fill="none">' +
      '<circle cx="4" cy="4.5" r="2.2" stroke="currentColor" stroke-width="1.4"/>' +
      '<circle cx="14" cy="13.5" r="2.2" stroke="currentColor" stroke-width="1.4"/>' +
      '<circle cx="4" cy="13.5" r="2.2" stroke="currentColor" stroke-width="1.4"/>' +
      '<path d="M4 6.7v4.6M6.2 5.2 11.8 12" stroke="currentColor" stroke-width="1.4"/></svg>'
  },
  {
    key: "code",
    name: "Editor",
    sub: "VS Code for the Web",
    path: "/code/",
    ping: "/code/",
    icon:
      '<svg width="17" height="17" viewBox="0 0 18 18" fill="none">' +
      '<path d="M6.5 5 3 9l3.5 4M11.5 5 15 9l-3.5 4" stroke="currentColor" ' +
      'stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>'
  },
  {
    key: "grafana",
    name: "Monitoring",
    sub: "Grafana",
    // Straight to the provisioned dashboard. Grafana's own landing page is a
    // list of dashboards, which is one click of nothing on a host with one.
    path: "/grafana/d/clabhost-overview/clabhost-overview",
    ping: "/grafana/api/health",
    icon:
      '<svg width="17" height="17" viewBox="0 0 18 18" fill="none">' +
      '<path d="M2 13.5 6 8l3.2 2.8L15.5 4" stroke="currentColor" stroke-width="1.5" ' +
      'stroke-linecap="round" stroke-linejoin="round"/>' +
      '<path d="M2 16h14" stroke="currentColor" stroke-width="1.2" opacity=".5"/></svg>'
  }
];
