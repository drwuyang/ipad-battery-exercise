#include <metal_stdlib>
using namespace metal;

kernel void stressKernel(device float4 *values [[buffer(0)]],
                         uint index [[thread_position_in_grid]]) {
    float4 value = values[index] + float4(float(index & 255u) * 0.001f);
    for (uint iteration = 0; iteration < 192; ++iteration) {
        value = fma(value, float4(0.6f), sin(value) * 0.2f + 0.01f);
    }
    values[index] = value;
}
