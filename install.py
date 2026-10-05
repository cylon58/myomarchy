#!/usr/bin/env python3
"""Install only owned launcher, skill link and desktop entry. No privileged work."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--remove', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    base = Path(__file__).resolve().parent
    home = Path.home()
    state = Path(os.environ.get('XDG_STATE_HOME',home/'.local/state'))/'myomarchy'
    receipt = state/'install.json'
    desktop = Path(os.environ.get('XDG_DATA_HOME',home/'.local/share'))/'applications/myomarchy.desktop'
    desktop_text = '[Desktop Entry]\nType=Application\nName=My Omarchy\nComment=Your machine change history\nExec=omarchy-shell shell summon io.github.cylon58.myomarchy\nIcon=preferences-system\nTerminal=false\nCategories=System;\n'
    launcher = home/'.local/bin/myomarchy'
    if args.remove:
        data = json.loads(receipt.read_text())
        allowed = {str(launcher),str(home/'.agents/skills/myomarchy-change'),str(home/'.claude/skills/myomarchy-change')}
        for link,target in data['links'].items():
            path = Path(link)
            if link not in allowed:
                raise ValueError('Unexpected owned path')
            if path.is_symlink() and str(path.readlink()) == target:
                path.unlink()
        if desktop.is_file() and not desktop.is_symlink() and desktop.read_text() == desktop_text:
            desktop.unlink()
        receipt.unlink()
        print('Removed owned integration. History and snapshots retained.')
        return
    agent = subprocess.check_output(['omarchy-default-agent'],text=True).strip()
    roots = {'codex':home/'.agents/skills','opencode':home/'.agents/skills',
             'gemini':home/'.agents/skills','claude':home/'.claude/skills'}
    if agent not in roots:
        raise ValueError('Automatic skill setup supports Codex, Claude, OpenCode and Gemini. Select one first.')
    links = {launcher:base/'bin/myomarchy',roots[agent]/'myomarchy-change':base/'skills/myomarchy-change'}
    for link,target in links.items():
        if (link.exists() or link.is_symlink()) and not (link.is_symlink() and link.resolve() == target):
            raise ValueError('Refusing to overwrite '+str(link))
    if desktop.exists() and (desktop.is_symlink() or desktop.read_text() != desktop_text):
        raise ValueError('Refusing to overwrite desktop entry')
    for link,target in links.items():
        link.parent.mkdir(parents=True,exist_ok=True)
        if not link.is_symlink(): link.symlink_to(target)
    desktop.parent.mkdir(parents=True,exist_ok=True)
    desktop.write_text(desktop_text)
    state.mkdir(parents=True,exist_ok=True,mode=0o700)
    previous = json.loads(receipt.read_text())['links'] if receipt.exists() else {}
    previous.update({str(k):str(v) for k,v in links.items()})
    receipt.write_text(json.dumps({'links':previous},indent=2)+'\n')
    print('Installed launcher and '+agent+' skill. Start a new agent conversation.')


if __name__ == '__main__': main()
