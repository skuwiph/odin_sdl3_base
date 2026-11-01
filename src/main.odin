package main

import "core:fmt"
import "core:log"
import sdl "vendor:sdl3"

FrameData :: struct {
	quit_requested: bool,
	last_ticks:     f32,
	new_ticks:      f32,
	delta_time:     f32,
}

main :: proc() {
	context.logger = log.create_console_logger()

	sdl_init("Hello SDL", 1280, 780)

	loop()

	sdl_cleanup()
}

loop :: proc() {
	// Initialise FrameData
	fd := FrameData {
		last_ticks = sdl_ticks(),
	}

	for !fd.quit_requested {
		free_all(context.temp_allocator)

		fd.new_ticks = sdl_ticks()
		fd.delta_time = f32(fd.new_ticks - fd.last_ticks) / 1000
		fd.last_ticks = sdl_ticks()

		// Process events
		ev: sdl.Event
		for sdl.PollEvent(&ev) {
			// if g.ui_input_mode do im_sdl.ProcessEvent(&ev)

			#partial switch ev.type {
			case .QUIT:
				fd.quit_requested = true
			case .KEY_DOWN:
				if ev.key.scancode == .ESCAPE {
					fd.quit_requested = true
				}

			// if !g.ui_input_mode {
			//     g.key_down[ev.key.scancode] = true;
			// }
			// case .KEY_UP:
			//     if !g.ui_input_mode {
			//         g.key_down[ev.key.scancode] = false;
			//     }
			// case .MOUSE_MOTION:
			//     if !g.ui_input_mode {
			//         g.mouse_move += {ev.motion.xrel, ev.motion.yrel}
			//     }
			// case .MOUSE_BUTTON_DOWN:
			//     if ev.button.button == 2 {
			//         g.ui_input_mode = !g.ui_input_mode
			//         _ = sdl.SetWindowRelativeMouseMode(g.window, !g.ui_input_mode)
			//     }
			}
		}
	}
}
