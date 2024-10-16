shader_type spatial;

uniform float strength : hint_range(0.0, 1.0) = 0.0;  // s: 0 = perspective, 1 = stereographic
uniform float height : hint_range(0.0, 10.0) = 1.0;   // h: tan(verticalFOVInRadians / 2)
uniform float aspectRatio : hint_range(0.1, 10.0) = 1.0;  // a: screenWidth / screenHeight
uniform float cylindricalRatio : hint_range(0.0, 1.0) = 1.0;  // c: cylindrical distortion ratio. 1 = spherical

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

varying vec3 vUV;
varying vec2 vUVDot;

void vertex() {
    float scaledHeight = strength * height;
    float cylAspectRatio = aspectRatio * cylindricalRatio;
    float aspectDiagSq = aspectRatio * aspectRatio + 1.0;
    float diagSq = scaledHeight * scaledHeight * aspectDiagSq;
    vec2 signedUV = (2.0 * UV + vec2(-1.0, -1.0));

    float z = 0.5 * sqrt(diagSq + 1.0) + 0.5;
    float ny = (z - 1.0) / (cylAspectRatio * cylAspectRatio + 1.0);

    vUVDot = sqrt(ny) * vec2(cylAspectRatio, 1.0) * signedUV;
    vUV = vec3(0.5, 0.5, 1.0) * z + vec3(-0.5, -0.5, 0.0);
    vUV.xy += UV;
}

void fragment() {
    vec3 uv = dot(vUVDot, vUVDot) * vec3(-0.5, -0.5, -1.0) + vUV;
    vec4 diffuse_color = texture(SCREEN_TEXTURE, uv.xy / uv.z);
    ALBEDO = diffuse_color.rgb;
}