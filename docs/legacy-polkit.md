# Polkit files left by Local AI 6.0-6.4

Local AI 6.0 to 6.4 set up passwordless start and stop through polkit. Setup on those versions wrote two files for
your account, where `<uid>` is your user id (`id -u`):

| File | What it is |
|---|---|
| `/etc/polkit-1/actions/sero.local-ai.u<uid>.policy` | polkit actions whose `org.freedesktop.policykit.exec.path` is `bin/omarchy-local-ai` in your plugin folder, `~/.config/omarchy/plugins/sero.local-ai` |
| `/etc/polkit-1/rules.d/49-sero.local-ai.u<uid>.rules` | a rule that allows the start and stop actions for your account without a password |

## Why they are dangerous

Together they let `pkexec` run the backend as root without asking for a password. The backend is a file in your home
folder, which every program running as you can change. A program running as you could replace that file and then have
polkit run it as root, so the two files give any program on your account root without a password.

Local AI stopped using polkit in 6.5. Versions 6.5 to 6.7 deleted these files during setup. 6.8 to 6.18 only printed
their paths at the end of setup, so on a machine that once ran 6.0-6.4 they may still be there.

## What Local AI does about them

While either file is there, Local AI stops. Home shows a red banner that links to this page. Starting a model, sharing
one and setup refuse with the same reason. Only root can delete the files, so Local AI does not delete them for you.

## Remove them

Run this in a terminal. It asks for your password:

```bash
sudo rm -f /etc/polkit-1/actions/sero.local-ai.u$(id -u).policy /etc/polkit-1/rules.d/49-sero.local-ai.u$(id -u).rules && sudo systemctl reload polkit
```

The first command deletes the two files. The second makes polkit read its actions and rules again, so the rule stops
applying straight away.

## Check that they are gone

```bash
sudo ls -l /etc/polkit-1/actions/sero.local-ai.u$(id -u).policy /etc/polkit-1/rules.d/49-sero.local-ai.u$(id -u).rules
```

Both lines should say `No such file or directory`. `sudo` is needed here because most systems do not let your account
read `/etc/polkit-1/rules.d`. The banner in Local AI clears on its next refresh, within a few seconds while the panel
is open.
