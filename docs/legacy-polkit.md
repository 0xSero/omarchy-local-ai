# Polkit files left by Local AI 6.0-6.4

Local AI 6.0 to 6.4 set up passwordless start and stop through polkit. Setup on those versions wrote two files for
each account that ran it, where `<uid>` is that account's user id (`id -u`):

| File | What it is |
|---|---|
| `/etc/polkit-1/actions/sero.local-ai.u<uid>.policy` | polkit actions whose `org.freedesktop.policykit.exec.path` is `bin/omarchy-local-ai` in that account's plugin folder, `~/.config/omarchy/plugins/sero.local-ai` |
| `/etc/polkit-1/rules.d/49-sero.local-ai.u<uid>.rules` | a rule that allows the start and stop actions for that account without a password |

## Why they are dangerous

Together they let `pkexec` run the backend as root without asking for a password. The backend is a file in the
account's home folder, which every program running as that account can change. Such a program could replace that file
and then have polkit run it as root, so the two files give any program of that account root without a password. A
pair left by another account on the machine is root on this machine all the same.

Local AI stopped using polkit in 6.5. Versions 6.5 to 6.7 deleted these files during setup. 6.8 to 6.18 only printed
their paths at the end of setup, so on a machine that once ran 6.0-6.4 they may still be there.

## What Local AI does about them

While any such file is there, for any account, Local AI stops. Home shows a red banner that links to this page.
Starting a model, sharing one and setup refuse with the same reason. Only root can delete the files, so Local AI does
not delete them for you.

Local AI can always see the actions, because `/etc/polkit-1/actions` is readable by every account. Most systems do
not let a normal account read `/etc/polkit-1/rules.d`, so a rule whose action is already gone may not be seen. That
rule allows nothing on its own, but the commands below remove it too.

## Remove them

Run this in a terminal. It asks for your password. It removes the files of every account, and the pattern is expanded
by the root shell, which can read `rules.d`:

```bash
sudo sh -c 'rm -f /etc/polkit-1/actions/sero.local-ai.u*.policy /etc/polkit-1/rules.d/49-sero.local-ai.u*.rules' && sudo systemctl reload polkit
```

The first command deletes the files. The second makes polkit read its actions and rules again, so the rules stop
applying straight away.

## Check that they are gone

```bash
sudo sh -c 'ls -l /etc/polkit-1/actions/sero.local-ai.u*.policy /etc/polkit-1/rules.d/49-sero.local-ai.u*.rules'
```

Both patterns should say `No such file or directory`. The banner in Local AI clears on its next refresh, within a few
seconds while the panel is open.
