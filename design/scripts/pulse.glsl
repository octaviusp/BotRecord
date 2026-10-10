precision mediump float;
/** @resolution */
uniform vec2 u_resolution;
/** @time */
uniform float u_time;
/**
 * @label Color
 * @color
 * @default #2563EB
 */
uniform vec3 u_color;
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float d = distance(uv, vec2(0.5));
  float ring = smoothstep(0.02, 0.0, abs(d - fract(u_time * 0.5) * 0.5));
  gl_FragColor = vec4(u_color * ring, ring);
}
