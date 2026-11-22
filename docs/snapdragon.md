# Snapdragon X

For a Snapdragon X Elite or X Plus machine, and for someone checking that Adreno is the device actually serving.

Local AI serves one model on this GPU: LFM2.5-2.6B QAD-Q4_0, recipe `lfm25-26b-qad-q4-adreno-16gb`, on any Snapdragon X whose RAM covers that tier (a 15 GB machine does). The registry has not measured this card, so the recipe lives in `recipes.snapdragon.json` and is merged at startup. A registry refresh cannot drop it.

The engine is llama.cpp's Vulkan server image, digest `sha256:15fd15e1f1d2ab2daf4b0b88f5849d95764c155237f36e8f5d36b32a4cec1be9` (build b12211), with Mesa Turnip. The host still needs `vulkan-freedreno` so `vulkaninfo` can see the GPU. Setup installs it on aarch64 when the machine looks like a Snapdragon.

## What the start forces

Turnip's compute shaders are the fragile part, so this recipe does not try to go faster than the measured path:

- flash attention off
- KV cache in f16 for both K and V
- `GGML_VK_DISABLE_INTEGER_DOT_PRODUCT=1` (Turnip's shared memory is 32 KB, and the integer-dot shader does not fit)
- `-lv 4`, because this build does not print the device name at the default verbosity

A start that does not log an Adreno device with at least one layer offloaded is stopped. A reply that does not look like the counting check is stopped too. Quantized Vulkan shaders on Adreno can still miscompile.

## Check the GPU

1. Run `omarchy-local-ai gpu`.
2. Confirm a render node and the name Adreno X1-85 or Adreno X1-45.
3. On X1 Plus the display node is `msm_dpu` and has no PCI vendor file. The GPU is the platform device `qcom,adreno-<chipid>` (`43030c00` is X1-45, `43050c01` is X1-85).
4. If there is no render node, install `linux-firmware-qcom`. X1-85 loads `gen70500_sqe.fw`. X1P-42-100 (Adreno X1-45) loads `gen71500_sqe.fw`, `gen71500_gmu.bin` and `qcom/x1p42100/gen71500_zap.mbn`.

Start it:

```bash
omarchy-local-ai run lfm25-26b-qad-q4-adreno-16gb adreno-vulkan:0
```

The engine log should contain both of these (a timestamp and a level letter may sit in front):

```text
llama_prepare_model_devices: using device Vulkan0 (Adreno X1-45) (unknown id)
load_tensors: offloaded 31/31 layers to GPU
```

`ggml_vulkan: No devices found` means the container did not see the GPU. See [troubleshooting.md](troubleshooting.md).

If the host's `vulkaninfo` sees Adreno and the container does not, build llama.cpp on the machine so the binary and Mesa match, then start again:

```bash
docker build -f docker/adreno/Dockerfile -t omarchy-local-ai/adreno-vulkan:local docker/adreno
```

That image is used automatically once it exists. Build it on the Snapdragon. First-generation Oryon has NEON, dotprod, fp16 and i8mm, and does not have SVE.
