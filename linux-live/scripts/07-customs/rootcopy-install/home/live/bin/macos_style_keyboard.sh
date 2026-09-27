#!/usr/bin/env bash
###
setxkbmap -layout us -model apple
## to enable alt(was ctral) ++ zoom in
## setxkbmap -option ctrl:ralt_rctrl
## macos style
setxkbmap -option ctrl:swap_lwin_lctl
##
##echo "firefox extension addon shortcuts"
## for cmd+1--9, cmd+t, create tab for terminal
cp accels.scm ~/.config/xfce4/terminal/accels.scm
## for switch windows
cp xfce4-keyboard-shortcuts.xml ~/.config/xfce4/xfconf/xfce-perchannel-xml/
xfsettingsd --replace --exit &
### for terminal ctrl+c -> ctrl+d
stty intr ^D
