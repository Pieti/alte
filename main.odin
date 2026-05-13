package main

import "core:fmt"
import "core:os"
import "core:sys/linux"
import "core:sys/posix"

enableRawMode :: proc() -> posix.termios {
	orig: posix.termios
	if posix.tcgetattr(posix.STDIN_FILENO, &orig) != .OK {
		panic("tcgetattr failed")
	}

	raw := orig
	raw.c_iflag &~= {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON}
	raw.c_oflag &~= {.OPOST}
	raw.c_cflag |= {.CS8}
	raw.c_lflag &~= {.ECHO, .ICANON, .IEXTEN, .ISIG}
	raw.c_cc[.VMIN] = 0
	raw.c_cc[.VTIME] = 1
	if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) != .OK {
		panic("tcsetattr failed")
	}
	return orig
}

disableRawMode :: proc(orig: ^posix.termios) {
	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, orig)
}

main :: proc() {
	orig := enableRawMode()
	defer disableRawMode(&orig)

	buf: [1]u8
	for {
		n, err := linux.read(linux.STDIN_FILENO, buf[:])
		if n == 0 {
			continue
		}
		if err != .NONE {
			panic("read failed")
		}
		if buf[0] == 'q' {
			break
		}
		if buf[0] < 32 || buf[0] == 127 {
			fmt.printf("%d\r\n", buf[0])
		} else {
			fmt.printf("%d ('%c')\r\n", buf[0], buf[0])
		}
	}
}
