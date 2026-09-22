
// The native view uses the installed controller; it never imports third-party QML.
// The view is generated from the controller's own ui/, so it requires the release that
// defines the row contract it renders: 5.4.0 and later.
function backendCommand(manifest) {
  if (!manifest || !manifest.__sourceDir) return ""
  var v = String(manifest.version || "").match(/^(\d+)\.(\d+)\.(\d+)$/)
  if (!v || Number(v[1]) !== 5 || Number(v[2]) < 4) return ""
  return manifest.__sourceDir.replace(/\/$/, "") + "/bin/omarchy-local-ai"
}
