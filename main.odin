package main

import "core:sys/linux"
import "core:sys/posix"
import "core:os"

ESC_CLEAR_SCREEN :: "\x1b[2J"
ESC_CURSOR_HOME :: "\x1b[H"

editor_config :: struct {
	rows: int,
	cols: int,
	orig: posix.termios,
}

editor : editor_config


init_editor :: proc() -> bool {
	rows, cols, ok := get_window_size()
	if !ok {
		return false
	}
	editor.rows = rows
	editor.cols = cols
	return true
}

ctrl_key :: proc(k: u8) -> u8 {
	return k & 0x1f
}

enable_raw_mode :: proc() -> bool {
	if posix.tcgetattr(posix.STDIN_FILENO, &editor.orig) != .OK {
		return false
	}

	raw := editor.orig
	raw.c_iflag &~= {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON}
	raw.c_oflag &~= {.OPOST}
	raw.c_cflag |= {.CS8}
	raw.c_lflag &~= {.ECHO, .ICANON, .IEXTEN, .ISIG}
	raw.c_cc[.VMIN] = 0
	raw.c_cc[.VTIME] = 1
	if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) != .OK {
		return false
	}
	return true
}

disable_raw_mode :: proc() {
	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &editor.orig)
}

Winsize :: struct {
	ws_row:    u16,
	ws_col:    u16,
	ws_xpixel: u16,
	ws_ypixel: u16,
}

get_window_size :: proc() -> (rows: int, cols: int, ok: bool) {
	ws: Winsize
	ret := linux.ioctl(linux.Fd(linux.STDOUT_FILENO), linux.TIOCGWINSZ, uintptr(rawptr(&ws)))
	if i64(ret) < 0 || ws.ws_col == 0 {
		return 0, 0, false
	}
	return int(ws.ws_row), int(ws.ws_col), true
}

read_key :: proc() -> (u8, bool) {
	buf: [1]u8
	for {
		n, err := linux.read(linux.STDIN_FILENO, buf[:])
		if n == 0 {
			continue
		}
		if err != .NONE {
			return 0, false
		}
		return buf[0], true
	}
}

process_key :: proc() -> bool {
	key, ok := read_key()
	if !ok {
		return false
	}
	switch key {
	case ctrl_key('q'):
		return false
	}
	return true
}

clear_screen :: proc() {
	os.write_string(os.stdout, ESC_CLEAR_SCREEN)
	os.write_string(os.stdout, ESC_CURSOR_HOME)
}

refresh_screen :: proc() {
	clear_screen()
	draw_rows()
	os.write_string(os.stdout, ESC_CURSOR_HOME)
}

draw_rows :: proc() {
	for _ in 0..<editor.rows-1 {
		os.write_string(os.stdout, "~\r\n")
	}
	os.write_string(os.stdout, "~")
}

main :: proc() {
	if !enable_raw_mode() {
		os.exit(1)
	}
	if !init_editor() {
		os.exit(1)
	}
	defer disable_raw_mode()
	defer clear_screen()

	for {
		refresh_screen()
		if !process_key() {
			break
		}
	}
}
