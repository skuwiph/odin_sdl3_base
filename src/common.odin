package main

import sdl "vendor:sdl3"

CONTENT_DIR :: "content"

Vec3 :: [3]f32
Vec2 :: [2]f32
Mat4 :: matrix[4, 4]f32
Quat :: quaternion128

Vertex_Data :: struct {
	pos:    Vec3,
	color:  sdl.FColor,
	uv:     Vec2,
	normal: Vec3,
}

Model_Id :: distinct int
Entity :: struct {
	model_id: Model_Id,
	position: Vec3,
	rotation: Quat,
}

Mesh :: struct {
	vertex_buf:  ^sdl.GPUBuffer,
	index_buf:   ^sdl.GPUBuffer,
	num_indices: u32,
}

Model :: struct {
	mesh:     Mesh,
	material: Material,
}

Material :: struct {
	diffuse_texture:    ^sdl.GPUTexture,
	specular_color:     Vec3,
	specular_shininess: f32,
}

// NOTE: Data must be aligned
UBO_Vertex_Global :: struct #packed {
	view_projection_mat: Mat4,
}

UBO_Vertex_Local :: struct #packed {
	model_mat:  Mat4,
	normal_mat: Mat4,
}

UBO_Fragment_Global :: struct #packed {
	lightPosition:     Vec3,
	_:                 f32, // Need 4 bytes padding to align the previous 12-byte value to the 16byte "page"
	lightColor:        Vec3,
	lightIntensity:    f32,
	viewPosition:      Vec3,
	_:                 f32, // Need 4 bytes padding to align the previous 12-byte value to the 16byte "page"
	ambientLightColor: Vec3,
}

UBO_Fragment_Local :: struct #packed {
	material_specular_color:     Vec3,
	material_specular_shininess: f32,
}

Input_State :: struct {
	key_down:   #sparse[sdl.Scancode]bool,
	mouse_move: Vec2,
}

Game_State :: struct {
	// NOTE: usually these are apparently "per-material"
	entity_pipeline:      ^sdl.GPUGraphicsPipeline,
	light_shape_pipeline: ^sdl.GPUGraphicsPipeline,
	light_shape_mesh:     Mesh,
	default_sampler:      ^sdl.GPUSampler,
	camera:               struct {
		position: Vec3,
		target:   Vec3,
	},
	look:                 struct {
		yaw:   f32,
		pitch: f32,
	},
	models:               []Model,
	entities:             []Entity,

	// Are these "scene" or "level" specific?
	light_position:       Vec3,
	light_color:          Vec3,
	light_intensity:      f32,
	ambient_light_color:  Vec3,
}
