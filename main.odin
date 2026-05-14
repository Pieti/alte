package main

import "core:fmt"
import "core:strings"
import "core:sys/linux"
import "core:sys/posix"
import "core:os"

ALTE_VERSION :: "0.0.1"
APP_NAME :: "Alte"
WELCOME :: APP_NAME + " -- version " + ALTE_VERSION

ESC_CLEAR_SCREEN :: "\x1b[2J"
ESC_CURSOR_HOME :: "\x1b[H"
ESC_HIDE_CURSOR :: "\x1b[?25l"
ESC_SHOW_CURSOR :: "\x1b[?25h"
ESC_ERASE_IN_LINE :: "\x1b[K"

editor_config :: struct {
	cx, cy: int,
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

esc_cursor_pos :: proc(sb: ^strings.Builder, row, col: int) {
	fmt.sbprintf(sb, "\x1b[%d;%dH", row+1, col+1)
}

move_cursor :: proc(key: u8) {
	switch key {
	case 'h':
		if editor.cx != 0 {
			editor.cx -= 1
		}
	case 'l':
		if editor.cx != editor.cols-1 {
			editor.cx += 1
		}
	case 'k':
		if editor.cy != 0 {
			editor.cy -= 1
		}
	case 'j':
		if editor.cy != editor.rows-1 {
			editor.cy += 1
		}
	}

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
		if buf[0] == '\x1b' {
			seq: [2]u8
			if n1, _ := linux.read(linux.STDIN_FILENO, seq[:1]); n1 == 0 {
				return u8('\x1b'), true
			}
			if n2, _ := linux.read(linux.STDIN_FILENO, seq[1:]); n2 == 0 {
				return u8('\x1b'), true
			}
			if seq[0] == '[' {
				switch seq[1] {
				case 'A':
					return 'k', true
				case 'B':
					return 'j', true
				case 'C':
					return 'l', true
				case 'D':
					return 'h', true
				}
			}
			return u8('\x1b'), true
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
	case 'h', 'j', 'k', 'l':
		move_cursor(key)
	}
	return true
}

clear_screen :: proc() {
	os.write_string(os.stdout, ESC_CLEAR_SCREEN)
	os.write_string(os.stdout, ESC_CURSOR_HOME)
}

refresh_screen :: proc(sb: ^strings.Builder) {
	strings.builder_reset(sb)
	strings.write_string(sb, ESC_HIDE_CURSOR)
	strings.write_string(sb, ESC_CURSOR_HOME)
	draw_rows(sb)
	esc_cursor_pos(sb, editor.cy, editor.cx)
	strings.write_string(sb, ESC_SHOW_CURSOR)
	os.write_string(os.stdout, strings.to_string(sb^))
}

draw_rows :: proc(sb: ^strings.Builder) {
	for y in 0..<editor.rows {
		if y == editor.rows /3 {
			welcome := WELCOME
			welcome = welcome[:min(editor.cols, len(welcome))]
			padding := (editor.cols - len(welcome)) / 2
			if padding > 0 {
				strings.write_string(sb, "~")
			}
			for _ in 1..<padding {
				strings.write_string(sb, " ")
			}
			strings.write_string(sb, welcome)
		} else {
			strings.write_string(sb, "~")
		}
		strings.write_string(sb, ESC_ERASE_IN_LINE)
		if y < editor.rows-1 {
			strings.write_string(sb, "\r\n")
		}
	}
}

main :: proc() {
	if !enable_raw_mode() {
		os.exit(1)
	}
	defer disable_raw_mode()

	if !init_editor() {
		os.exit(1)
	}
	defer clear_screen()

	sb: strings.Builder
	strings.builder_init_len_cap(&sb, 0, editor.rows * editor.cols)
	defer(strings.builder_destroy(&sb))

	for {
		refresh_screen(&sb)
		if !process_key() {
			break
		}
	}
}
