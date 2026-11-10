# ~/.bash_profile
[[ -f ~/.bashrc ]] && . ~/.bashrc
# AshenOS: на первом терминале сразу запускаем sway
if [[ -z ${WAYLAND_DISPLAY:-} && "$(tty 2>/dev/null)" == /dev/tty1 ]]; then
    exec /usr/bin/sway
fi
