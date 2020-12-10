shader_type canvas_item;

uniform float size = 512.0;
uniform sampler2D input_texture;
uniform float distance = 0.1;


float invLerp(float from, float to, float value){
	return (value - from) / (to - from);
}

float remap(float origFrom, float origTo, float targetFrom, float targetTo, float value){
	float rel = invLerp(origFrom, origTo, value);
	return mix(targetFrom, targetTo, rel);
}

void fragment() {
	vec4 lodded_texture = textureLod(input_texture, UV - vec2(0.0, distance), 0.0);
	float remapped = remap(0.9, 1.0, 0.0, 1.0, lodded_texture.r);
	COLOR = vec4(remapped, remapped, remapped, 1.0);
}