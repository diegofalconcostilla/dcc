extends CanvasLayer
class_name ScreenOverlay

## Full-screen post layer between the world and the HUD: a soft vignette that
## always frames the action, a red edge pulse that grows as HP runs low, and a
## brief flash when the player is hit. One ColorRect + a tiny canvas shader —
## no per-frame allocations.

const LOW_HP_THRESHOLD := 0.35  # fraction of max HP where the warning pulse begins

const SHADER_CODE := """
shader_type canvas_item;
uniform float vignette = 0.42;
uniform float danger = 0.0;
uniform float hit = 0.0;
uniform vec4 danger_color : source_color = vec4(0.85, 0.03, 0.08, 1.0);
void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.9);
	float edge = smoothstep(0.28, 0.78, length(p));
	float a = edge * (vignette + danger * 0.75 + hit * 0.6);
	vec3 rgb = mix(vec3(0.0), danger_color.rgb, clamp(danger + hit, 0.0, 1.0) * edge);
	COLOR = vec4(rgb, clamp(a, 0.0, 0.92));
}
"""

var _material: ShaderMaterial
var _hp_fraction := 1.0
var _hit := 0.0
var _time := 0.0

func _ready() -> void:
	layer = 1  # above the world, below the HUD (layer 2)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _material
	add_child(rect)

func set_hp(current: float, max_hp: float) -> void:
	_hp_fraction = clampf(current / maxf(max_hp, 1.0), 0.0, 1.0)

## Brief red pulse on the screen edges — called whenever the player is hit.
func pulse_hit(strength: float = 1.0) -> void:
	_hit = maxf(_hit, clampf(strength, 0.0, 1.0))

func _process(delta: float) -> void:
	_time += delta
	_hit = maxf(0.0, _hit - delta * 3.5)
	var danger := 0.0
	if _hp_fraction < LOW_HP_THRESHOLD:
		var severity := 1.0 - _hp_fraction / LOW_HP_THRESHOLD
		# Heartbeat: quicker and stronger the closer to death.
		danger = severity * (0.45 + 0.4 * (0.5 + 0.5 * sin(_time * (4.0 + 5.0 * severity))))
	_material.set_shader_parameter("danger", danger)
	_material.set_shader_parameter("hit", _hit)
