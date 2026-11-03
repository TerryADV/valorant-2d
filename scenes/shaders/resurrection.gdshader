shader_type canvas_item;

uniform sampler2D agent_texture : filter_nearest;

void fragment() {
    vec4 gradient = texture(TEXTURE, UV);
    float agent_alpha = texture(agent_texture, UV).a;
    COLOR = vec4(gradient.rgb, gradient.a * agent_alpha) * COLOR;
}
