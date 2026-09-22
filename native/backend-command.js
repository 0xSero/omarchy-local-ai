
// The native view uses the installed controller; it never imports third-party QML.
function backendCommand(manifest) {
  if (!manifest || !manifest.__sourceDir) return ""
  var v = String(manifest.version || "").match(/^(\d+)\.(\d+)\.(\d+)$/)
  if (!v || Number(v[1]) !== 5 || Number(v[2]) < 3 || (Number(v[2]) === 3 && Number(v[3]) < 7)) return ""
  return manifest.__sourceDir.replace(/\/$/, "") + "/bin/omarchy-local-ai"
}
