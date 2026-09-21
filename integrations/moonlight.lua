-- Ctrl+Space enters one-shot desktop shortcuts without taking Ctrl+C/V from apps.
-- Match Mac focus: moving the pointer alone must not redirect typing.
hl.config({ input = { follow_mouse = 0 } })
local function remote_key(key, description, action)
  hl.bind(key, function()
    hl.dispatch(hl.dsp.submap("reset"))
    if type(action) == "string" then hl.exec_cmd(action) else hl.dispatch(action) end
  end, { description = "Remote: " .. description })
end

o.bind("CTRL + SPACE", "Remote shortcuts (release, then K for help)", hl.dsp.submap("moonlight"))
o.bind("CTRL + F1", "Keyboard cheat sheet", "env OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell toggle sero.shortcuts")
hl.define_submap("moonlight", function()
  remote_key("ESCAPE", "Cancel", hl.dsp.submap("reset"))
  remote_key("K", "Cheat sheet", "env OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell toggle sero.shortcuts")
  remote_key("A", "Agents", "env OMARCHY_PATH=/usr/share/omarchy omarchy-shell shell toggle sero.agents")
  remote_key("I", "Local AI", "env OMARCHY_PATH=/usr/share/omarchy omarchy-shell omarchy.agents local")
  remote_key("RETURN", "Terminal", "omarchy-launch-terminal")
  remote_key("SPACE", "Omarchy menu", "omarchy-menu toggle")
  remote_key("B", "Browser", "omarchy-launch-browser")
  remote_key("F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
  remote_key("T", "Float / tile", hl.dsp.window.float({ action = "toggle" }))
  remote_key("TAB", "Next window", hl.dsp.window.cycle_next())
  remote_key("P", "Previous window", hl.dsp.window.cycle_next({ next = false }))
  remote_key("W", "Close window", hl.dsp.window.close())
  for key, direction in pairs({ LEFT = "l", RIGHT = "r", UP = "u", DOWN = "d" }) do
    remote_key(key, "Focus " .. direction, hl.dsp.focus({ direction = direction }))
    remote_key("SHIFT + " .. key, "Swap " .. direction, hl.dsp.window.swap({ direction = direction }))
  end
  for workspace = 1, 10 do
    local key = "code:" .. tostring(workspace + 9)
    remote_key(key, "Workspace " .. workspace, hl.dsp.focus({ workspace = tostring(workspace) }))
    remote_key("SHIFT + " .. key, "Move to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
  end
end)

-- Familiar desktop chords; workspace selection stays on Ctrl+Space then 1–0.
for _, chord in ipairs({ "SUPER + TAB", "SUPER + SHIFT + TAB", "SUPER + SHIFT + ISO_Left_Tab", "SUPER + SPACE", "SUPER + CTRL + F" }) do hl.unbind(chord) end
o.bind("SUPER + SPACE", "Mac: app launcher", "omarchy-menu toggle apps")
o.bind("SUPER + CTRL + F", "Mac: full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
o.bind("SUPER + TAB", "Mac: switch window", function()
  hl.dispatch(hl.dsp.window.cycle_next())
  hl.dispatch(hl.dsp.window.bring_to_top())
end)

-- Moonlight forwards Mac Command as SUPER. Keep desktop actions on Ctrl+Space
-- and send app shortcuts with explicit modifiers, as Omarchy's clipboard does.
local function app_shortcut(key, mods, terminal_action)
  local chord = "SUPER + " .. key
  hl.unbind(chord)
  o.bind(chord, "Mac: " .. key, function()
    local window = hl.get_active_window()
    local terminal = false
    for _, tag in ipairs(window and window.tags or {}) do
      if tag:gsub("%*$", "") == "terminal" then terminal = true end
    end
    if terminal and terminal_action then
      if type(terminal_action) == "string" then hl.exec_cmd(terminal_action)
      else hl.dispatch(terminal_action) end
      return
    end
    local target_key = key:match("%S+$")
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = target_key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = target_key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end)
end
app_shortcut("W", "CTRL", hl.dsp.window.close())
app_shortcut("D", "CTRL", "omarchy-launch-terminal")
app_shortcut("T", "CTRL", "omarchy-launch-terminal")
app_shortcut("N", "CTRL", "omarchy-launch-terminal")
for _, key in ipairs({ "A", "F", "S", "L", "R", "Z", "O", "P" }) do app_shortcut(key, "CTRL") end
app_shortcut("SHIFT + Z", "CTRL SHIFT")
app_shortcut("SHIFT + T", "CTRL SHIFT")
