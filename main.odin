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


Row :: struct {
	chars: [dynamic]u8,
}

Editor_Config :: struct {
	cx, cy: int,
	rowd, cold: int,
	height: int,
	width: int,
	rows: [dynamic]Row,
	orig: posix.termios,
}

editor : Editor_Config

Key :: enum {
	Up,
	Down,
	Left,
	Right,
	Home,
	End,
	PageUp,
	PageDown,
	Del,
}

Char :: union {
	u8,
	Key,
}

init_editor :: proc() -> bool {
	height, width, ok := get_window_size()
	if !ok {
		return false
	}
	editor.height = height
	editor.width = width
	return true
}

append_row :: proc(s: string) {
	row: Row
	row.chars = make([dynamic]u8, len(s))
	copy(row.chars[:], transmute([]u8)s)
	append(&editor.rows, row)
}

editor_open :: proc(filename: string) -> bool {
	data, err := os.read_entire_file(filename, context.allocator)
	if err != .NONE {
		return false
	}
	defer delete(data)

	content := string(data)
	for line in strings.split_lines_iterator(&content) {
		append_row(line)
	}
	return true
}

ctrl_key :: proc(k: u8) -> u8 {
	return k & 0x1f
}

esc_cursor_pos :: proc(sb: ^strings.Builder, row, col: int) {
	fmt.sbprintf(sb, "\x1b[%d;%dH", row+1, col+1)
}

move_cursor :: proc(key: Key) {
	row : Row
	if len(editor.rows) > 0 {
		row = editor.rows[editor.cy]
	} else {
		row.chars = make([dynamic]u8, 0)
	}

	#partial switch key {
	case Key.Left:
		if editor.cx > 0 {
			editor.cx -= 1
		} else if editor.cy > 0 {
			editor.cy -= 1
			editor.cx = len(editor.rows[editor.cy].chars)
		}
	case Key.Right:
		if editor.cx < len(row.chars) {
			editor.cx += 1
		} else if editor.cy < len(editor.rows) - 1 {
			editor.cy += 1
			editor.cx = 0
		}
	case Key.Up:
		if editor.cy > 0 {
			editor.cy -= 1
		}
	case Key.Down:
		if editor.cy < len(editor.rows) {
			editor.cy += 1
		}
	case Key.Home:
		editor.cx = 0
	case Key.End:
		editor.cx = len(row.chars)
	case Key.PageUp:
		editor.cy = 0
	case Key.PageDown:
		editor.cy = editor.rowd + editor.height - 1
	}

	if editor.cy >= len(editor.rows) {
		editor.cy = len(editor.rows) - 1
	}
	if editor.cx > len(editor.rows[editor.cy].chars) {
		editor.cx = len(editor.rows[editor.cy].chars)
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

read_key :: proc() -> (Char, bool) {
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
			seq: [3]u8
			if n1, _ := linux.read(linux.STDIN_FILENO, seq[:1]); n1 == 0 {
				return u8('\x1b'), true
			}
			if n2, _ := linux.read(linux.STDIN_FILENO, seq[1:2]); n2 == 0 {
				return u8('\x1b'), true
			}
			if seq[0] == '[' {
				if seq[1] >= '0' && seq[1] <= '9' {
					if n3, _ := linux.read(linux.STDIN_FILENO, seq[2:3]); n3 == 0 {
						return u8('\x1b'), true
					}
					if seq[2] == '~' {
						switch seq[1] {
						case '1': return Key.Home, true
						case '3': return Key.Del, true
						case '4': return Key.End, true
						case '5': return Key.PageUp, true
						case '6': return Key.PageDown, true
						case '7': return Key.Home, true	
						case '8': return Key.End, true
						}
					}
				} else {
					switch seq[1] {
					case 'A': return Key.Up, true
					case 'B': return Key.Down, true
					case 'C': return Key.Right, true
					case 'D': return Key.Left, true
					}
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
	switch k in key {
	case u8:
		switch k {
		case ctrl_key('q'):
			return false
		case 'h':
			move_cursor(Key.Left)
		case 'l':
			move_cursor(Key.Right)
		case 'k':
			move_cursor(Key.Up)
		case 'j':
			move_cursor(Key.Down)
		}
	case Key:
		move_cursor(k)
	}
	return true
}

clear_screen :: proc() {
	os.write_string(os.stdout, ESC_CLEAR_SCREEN)
	os.write_string(os.stdout, ESC_CURSOR_HOME)
}

refresh_screen :: proc(sb: ^strings.Builder) {
	scroll()
	strings.builder_reset(sb)
	strings.write_string(sb, ESC_HIDE_CURSOR)
	strings.write_string(sb, ESC_CURSOR_HOME)
	draw_rows(sb)
	esc_cursor_pos(sb, (editor.cy - editor.rowd), (editor.cx - editor.cold))
	strings.write_string(sb, ESC_SHOW_CURSOR)
	os.write_string(os.stdout, strings.to_string(sb^))
}

scroll :: proc() {
	if editor.cy < editor.rowd {
		editor.rowd = editor.cy
	}
	if editor.cy >= editor.rowd + editor.height {
		editor.rowd = editor.cy - editor.height + 1
	}
	if editor.cx < editor.cold {
		editor.cold = editor.cx
	}
	if editor.cx >= editor.cold + editor.width {
		editor.cold = editor.cx - editor.width + 1
	}
}

draw_rows :: proc(sb: ^strings.Builder) {
	for y in 0..<editor.height {
		yd := y + editor.rowd
		if yd >= len(editor.rows) {
			if len(editor.rows) == 0 && yd == editor.height /3 {
				welcome := WELCOME
				welcome = welcome[:min(editor.width, len(welcome))]
				padding := (editor.width - len(welcome)) / 2
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
		} else {
			line := editor.rows[yd].chars
			start := min(editor.cold, len(line))
			end := min(editor.cold + editor.width, len(line))
			dynline := line[start:end]
			strings.write_string(sb, string(dynline))
		}
		strings.write_string(sb, ESC_ERASE_IN_LINE)
		if y < editor.height-1 {
			strings.write_string(sb, "\r\n")
		}
	}
}

main :: proc() {
	if len(os.args) != 2 {
		fmt.println("Usage: alte <filename>")
		os.exit(1)
	}

	if !enable_raw_mode() {
		os.exit(1)
	}
	defer disable_raw_mode()

	if !init_editor() {
		os.exit(1)
	}
	defer clear_screen()

	if !editor_open(os.args[1]) {
		os.exit(1)
	}

	sb: strings.Builder
	strings.builder_init_len_cap(&sb, 0, editor.height * editor.width)
	defer(strings.builder_destroy(&sb))

	for {
		refresh_screen(&sb)
		if !process_key() {
			break
		}
	}
}
