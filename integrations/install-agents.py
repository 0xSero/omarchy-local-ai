#!/usr/bin/env python3
"""Extend the installed native Agents panel without changing system-owned files."""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--omarchy', type=Path, default=Path('/usr/share/omarchy'))
parser.add_argument('--moonlight', action='store_true', help='also install Ctrl-based desktop shortcuts')
args = parser.parse_args()
home = Path.home()
config = home / '.config/omarchy'
source = args.omarchy / 'shell/plugins/agents'
local_ai = config / 'plugins/sero.local-ai'
here = Path(__file__).resolve().parent
if 'property bool embedded:' not in (local_ai / 'ui/Panel.qml').read_text():
    raise SystemExit('Update Local AI before installing the native Agents integration.')

# Fail before changing the desktop if this Omarchy version no longer matches.
with tempfile.TemporaryDirectory() as tmp:
    staged = Path(tmp) / 'Panel.qml'
    shutil.copy2(source / 'Panel.qml', staged)
    subprocess.run(['patch', '--batch', '--fuzz=0', str(staged), str(here / 'agents-panel.patch')], check=True)
    panel = staged.read_text()

stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
backup = home / '.local/state/omarchy/backups' / ('native-agents-' + stamp)
backup.mkdir(parents=True)
shell_path = config / 'shell.json'
shutil.copy2(shell_path, backup / 'shell.json')
destination = config / 'plugins/sero.agents'
if destination.exists():
    shutil.copytree(destination, backup / 'sero.agents', symlinks=True)
destination.mkdir(parents=True, exist_ok=True)
(destination / 'Panel.qml').write_text(panel)
for name in ('Main.qml', 'Agent.qml', 'assets'):
    target = destination / name
    if target.is_symlink():
        target.unlink()
    elif target.exists():
        raise SystemExit(f'Refusing to replace non-symlink {target}')
    target.symlink_to(source / name)
manifest = json.loads((source / 'manifest.json').read_text())
manifest.update(id='sero.agents', name='Agents', author='Local customization',
                description='Native Agents panel with Local AI controls, project folder selection and shortcut help.')
(destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
shell = json.loads(shell_path.read_text())
found = False
for section, items in shell['bar']['layout'].items():
    updated = []
    for item in items:
        if item['id'] == 'sero.local-ai':
            continue
        if item['id'] in ('omarchy.agents', 'sero.agents'):
            item = dict(item, id='sero.agents')
            found = True
        updated.append(item)
    shell['bar']['layout'][section] = updated
if not found:
    shell['bar']['layout'].setdefault('right', []).append({'id': 'sero.agents'})
shortcuts = config / 'plugins/sero.shortcuts'
if shortcuts.exists():
    shutil.copytree(shortcuts, backup / 'sero.shortcuts', symlinks=True)
shortcuts.mkdir(parents=True, exist_ok=True)
guide = home / '.local/share/omarchy/guides/macos-controls.html'
guide.parent.mkdir(parents=True, exist_ok=True)
if guide.exists():
    shutil.copy2(guide, backup / guide.name)
shutil.copy2(here / guide.name, guide)
shutil.copy2(here / 'Shortcuts.qml', shortcuts / 'Panel.qml')
(shortcuts / 'manifest.json').write_text(json.dumps({
    'schemaVersion': 1, 'id': 'sero.shortcuts', 'name': 'Keyboard shortcuts',
    'version': '1.0.0', 'author': 'Local customization', 'license': 'MIT',
    'description': 'Mac and remote desktop keyboard cheat sheet.',
    'kinds': ['bar-widget'], 'activation': 'on-demand',
    'entryPoints': {'barWidget': 'Panel.qml'},
    'barWidget': {'displayName': 'Keyboard shortcuts', 'category': 'System', 'allowMultiple': False}
}, indent=2) + '\n')
if not any(item['id'] == 'sero.shortcuts' for items in shell['bar']['layout'].values() for item in items):
    shell['bar']['layout'].setdefault('right', []).insert(0, {'id': 'sero.shortcuts'})
if args.moonlight:
    hypr = home / '.config/hypr'
    bindings = hypr / 'bindings.lua'
    shutil.copy2(bindings, backup / 'bindings.lua')
    if (hypr / 'moonlight.lua').exists():
        shutil.copy2(hypr / 'moonlight.lua', backup / 'moonlight.lua')
    lua = (here / 'moonlight.lua').read_text().replace('/usr/share/omarchy', str(args.omarchy))
    (hypr / 'moonlight.lua').write_text(lua)
    include = 'require("hypr.moonlight")'
    if include not in bindings.read_text():
        with bindings.open('a') as output:
            output.write('\n' + include + '\n')
shell_path.write_text(json.dumps(shell, indent=2) + '\n')
print(f'Installed native Agents integration. Backup: {backup}')
print('Reload Hyprland for shortcuts. Restart the running shell to discard cached QML types.')
