package main

import "core:sys/linux"
import "core:sys/posix"
import "core:os"

ESC_CLEAR_SCREEN :: "\x1b[2J"
ESC_CURSOR_HOME :: "\x1b[H"

ctrl_key :: proc(k: u8) -> u8 {
	return k & 0x1f
}

enable_raw_mode :: proc() -> (posix.termios, bool) {
	orig: posix.termios
	if posix.tcgetattr(posix.STDIN_FILENO, &orig) != .OK {
		return orig, false
	}

	raw := orig
	raw.c_iflag &~= {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON}
	raw.c_oflag &~= {.OPOST}
	raw.c_cflag |= {.CS8}
	raw.c_lflag &~= {.ECHO, .ICANON, .IEXTEN, .ISIG}
	raw.c_cc[.VMIN] = 0
	raw.c_cc[.VTIME] = 1
	if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) != .OK {
		return orig, false
	}
	return orig, true
}

disable_raw_mode :: proc(orig: ^posix.termios) {
	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, orig)
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
	for _ in 0..<24 {
		os.write_string(os.stdout, "~\r\n")
	}
}

main :: proc() {
	orig, ok := enable_raw_mode()
	if !ok {
		os.exit(1)
	}
	defer disable_raw_mode(&orig)
	defer clear_screen()

	for {
		refresh_screen()
		if !process_key() {
			break
		}
	}
}
