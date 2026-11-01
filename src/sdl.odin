package main

import "base:runtime"
import "core:encoding/json"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"

import sdl "vendor:sdl3"

SDL :: struct {
	window:                   ^sdl.Window,
	gpu:                      ^sdl.GPUDevice,
	depth_texture:            ^sdl.GPUTexture,
	depth_texture_format:     sdl.GPUTextureFormat,
	swapchain_texture_format: sdl.GPUTextureFormat,
	window_size:              [2]i32,
	textures:                 map[int]^sdl.GPUTexture,
}

s: SDL

sdl_init :: proc(window_title: string, window_width: i32, window_height: i32) {
	window_title := strings.clone_to_cstring(window_title, context.temp_allocator)

	@(static) sdl_log_context: runtime.Context
	sdl_log_context = context
	sdl_log_context.logger.options = {.Short_File_Path, .Line, .Procedure}
	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(sdl_log, &sdl_log_context)

	ok := sdl.Init({.VIDEO})
	if !ok do log.panicf("Could not init SDL: {}", sdl.GetError())

	s.window = sdl.CreateWindow(window_title, window_width, window_height, {})
	if s.window == nil do log.panicf("Could not create SDL window: {}", sdl.GetError())

	s.gpu = sdl.CreateGPUDevice({.SPIRV, .DXIL, .MSL}, true, nil)
	if s.gpu == nil do log.panicf("Could not create GPU device: {}", sdl.GetError())

	ok = sdl.ClaimWindowForGPUDevice(s.gpu, s.window)
	if !ok do log.panicf("Could not claim window for GPU: {}", sdl.GetError())

	// NOTE: was .LINEAR_SDR
	ok = sdl.SetGPUSwapchainParameters(s.gpu, s.window, .SDR_LINEAR, .VSYNC)
	if !ok do log.panicf("Could not SetGPUSwapchainParameters for GPU: {}", sdl.GetError())

	s.swapchain_texture_format = sdl.GetGPUSwapchainTextureFormat(s.gpu, s.window)

	// Do on resize
	ok = sdl.GetWindowSize(s.window, &s.window_size.x, &s.window_size.y); sdl_assert(ok)

	s.depth_texture_format = .D16_UNORM
	try_depth_format :: proc(format: sdl.GPUTextureFormat) {
		if sdl.GPUTextureSupportsFormat(s.gpu, format, .D2, {.DEPTH_STENCIL_TARGET}) {
			s.depth_texture_format = format
		}
	}

	try_depth_format(.D32_FLOAT)
	try_depth_format(.D24_UNORM)

	log.debug("Creating depth_texture")

	s.depth_texture = sdl.CreateGPUTexture(
	s.gpu,
	{
		format               = s.depth_texture_format,
		usage                = {.DEPTH_STENCIL_TARGET},
		width                = u32(s.window_size.x),
		height               = u32(s.window_size.y),
		layer_count_or_depth = 1,
		num_levels           = 1,
		// props = properties
	},
	)

	log.debug("Created depth_texture")

	s.textures = make(map[int]^sdl.GPUTexture)

	_ = sdl.SetWindowRelativeMouseMode(s.window, true)
}

sdl_create_entity_pipeline :: proc(
	state: ^Game_State,
	vertex_shader: string,
	fragment_shader: string,
) {
	vert_shader := sdl_load_shader(s.gpu, vertex_shader)
	frag_shader := sdl_load_shader(s.gpu, fragment_shader)

	vertex_attrs := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
		{location = 1, format = .FLOAT2, offset = u32(offset_of(Vertex_Data, uv))},
		{location = 2, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, normal))},
		{location = 3, format = .FLOAT4, offset = u32(offset_of(Vertex_Data, color))},
	}

	state.entity_pipeline = sdl.CreateGPUGraphicsPipeline(
	s.gpu,
	{
		vertex_shader = vert_shader,
		fragment_shader = frag_shader,
		primitive_type = .TRIANGLELIST,
		vertex_input_state = {
			num_vertex_buffers = 1,
			vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
					slot = 0,
					pitch = size_of(Vertex_Data),
				}),
			num_vertex_attributes = u32(len(vertex_attrs)),
			vertex_attributes = raw_data(vertex_attrs),
		},
		depth_stencil_state = {
			enable_depth_test = true,
			enable_depth_write = true,
			compare_op = .LESS,
		},
		rasterizer_state = {
			cull_mode = .BACK,
			// fill_mode = .LINE,
		},
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = &(sdl.GPUColorTargetDescription {
					format = s.swapchain_texture_format,
				}),
			has_depth_stencil_target = true,
			depth_stencil_format = s.depth_texture_format,
		},
	},
	)

	sdl.ReleaseGPUShader(s.gpu, vert_shader)
	sdl.ReleaseGPUShader(s.gpu, frag_shader)

}

sdl_load_shader :: proc(device: ^sdl.GPUDevice, shaderfile: string) -> ^sdl.GPUShader {
	stage: sdl.GPUShaderStage

	switch filepath.ext(shaderfile) {
	case ".vert":
		stage = .VERTEX
	case ".frag":
		stage = .FRAGMENT
	}

	format: sdl.GPUShaderFormatFlag
	format_ext: string
	entrypoint: cstring = "main"

	supported_formats := sdl.GetGPUShaderFormats(s.gpu)
	log.debug(`Supported Formats: {}`, supported_formats)
	if .SPIRV in supported_formats {
		format = .SPIRV
		format_ext = ".spv"
	} else if .MSL in supported_formats {
		format = .MSL
		format_ext = ".msl"
		entrypoint = "main0"
	} else if .DXIL in supported_formats {
		format = .DXIL
		format_ext = ".dxil"
	} else {
		log.panicf("No supported shader format: {}", supported_formats)
	}

	shaderfile, _ := filepath.join(
		{CONTENT_DIR, "shaders", "out", shaderfile},
		context.temp_allocator,
	)

	filename := strings.concatenate({shaderfile, format_ext}, context.temp_allocator)
	code, err := os.read_entire_file_from_path(filename, context.temp_allocator)
	if err != nil {
		log.panicf("File {}: {}", filename, err)
	}

	log.debugf("Read {} bytes from {}", len(code), filename)

	info := sdl_load_shader_info(shaderfile)

	log.debugf("Shader Info: {}", info)

	return sdl.CreateGPUShader(
		device,
		{
			code_size = len(code),
			code = raw_data(code),
			entrypoint = entrypoint,
			format = {format},
			stage = stage,
			num_uniform_buffers = info.uniform_buffers,
			num_samplers = info.samplers,
			num_storage_buffers = info.storage_buffers,
			num_storage_textures = info.storage_textures,
		},
	)
}

@(private)
Shader_Info :: struct {
	samplers:         u32,
	storage_textures: u32,
	storage_buffers:  u32,
	uniform_buffers:  u32,
}

@(private)
sdl_load_shader_info :: proc(shaderfile: string) -> Shader_Info {
	json_filename := strings.concatenate({shaderfile, ".json"}, context.temp_allocator)
	json_data, err := os.read_entire_file_from_path(json_filename, context.temp_allocator)
	if err != nil do log.errorf(`Couldn't read {}: {}`, json_filename, err)
	result: Shader_Info
	uerr := json.unmarshal(json_data, &result, allocator = context.temp_allocator)
	if uerr != nil do log.errorf(`Couldn't unmarshall {}: {}`, json_filename, uerr)
	return result
}

sdl_cleanup :: proc() {

	// for model in g.models {
	//     sdl.ReleaseGPUBuffer(g.gpu, model.mesh.index_buf)
	//     sdl.ReleaseGPUBuffer(g.gpu, model.mesh.vertex_buf)
	// }
	log.debugf("Releasing {} textures", len(s.textures))

	for key, texture in s.textures {
		sdl.ReleaseGPUTexture(s.gpu, texture)
	}

	// None of this affects the warns at the end about live objects!
	sdl.ReleaseGPUTexture(s.gpu, s.depth_texture)

	// sdl.ReleaseGPUSampler(s.gpu, s.default_sampler)
	sdl.ReleaseWindowFromGPUDevice(s.gpu, s.window)
	sdl.DestroyWindow(s.window)

	delete(s.textures)
}

sdl_ticks :: proc() -> f32 {
	return f32(sdl.GetTicks())
}

sdl_assert :: proc(ok: bool) {
	if !ok do log.panicf("SDL Error: {}", sdl.GetError())
}

sdl_log :: proc "c" (
	userdata: rawptr,
	category: sdl.LogCategory,
	priority: sdl.LogPriority,
	message: cstring,
) {
	context = (transmute(^runtime.Context)userdata)^
	level: log.Level
	switch priority {
	case .INVALID, .TRACE, .VERBOSE, .DEBUG:
		level = .Debug
	case .INFO:
		level = .Info
	case .WARN:
		level = .Warning
		return // Ignore for now
	case .ERROR:
		level = .Error
	case .CRITICAL:
		level = .Fatal
	}
	log.logf(level, "SDL {}: {}", category, message)
}
