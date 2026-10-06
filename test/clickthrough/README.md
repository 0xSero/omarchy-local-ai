# Click-through

Drives the real panel and the real backend on a machine with Local AI installed, inside a private headless sway (the
desktop is never touched), and records it.

```
bash test/clickthrough/setup.sh   # ~/la-rec: the installed plugin's Panel.qml, Model.js and marks, its real bin, shell stubs
bash test/clickthrough/drive.sh   # ~/la-rec-out: clickthrough.mp4, clickthrough.gif, steps/NN-*.png, steps.log
```

Each step finds a label on screen, moves the drawn cursor there and delivers the click to the topmost enabled MouseArea
under that point (headless sway has no pointer device to click with), then waits for the screen it expects. Every verb
runs for real: the agent and folder it changes are set back, the share is turned off again, the CPU model it runs is
stopped. `uwsm-app` is shimmed for the run so an agent opened from the panel appears inside the recording.

The last recording (Local AI 7.1.0 on the omarchy box, 27 steps) is in `design/clickthrough/`.
