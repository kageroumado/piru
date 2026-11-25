# Replications: a live-camera effect reference

Point the camera at a room and see what a named visual effect looks like on it, at a chosen
level, with a split to compare against the plain image. The tool shows effects; it never
shows a substance or a dose.

`index.html` is the effect lab: one file, WebGL 2, a built-in test scene, and Camera/File
sources. Open it locally. `file://` and `localhost` both allow the camera.

## Effects and where each model comes from

| Effect | Model | Source |
|---|---|---|
| Tracers | Three layers, as in QRI's Tracer Replication Tool: **trails** (exponential feedback, set by half-life in seconds), **strobe** (snapshots held at a rate in Hz), **replay** (continuously moving copies delayed by k/f s), plus a color pulse that rotates hue toward its opposite in Oklab | QRI 2020 post; rates of 15–20 Hz (LSD) and 25–30 Hz (DMT) as reported there; Dubois & VanRullen 2011 (PLoS Biol, doi:10.1371/journal.pbio.1001056) |
| Drifting | Breathing, morphing and flowing displacement fields (curl noise, looped two-phase advection), stronger on textured surfaces, with a periphery-only mode for level 1 and a 6 fps "jittery" option | PsychonautWiki Drifting: four levels plus style variants |
| Color | Oklab chroma scale, lightness contrast, and a spatially varying hue rotation | PW Color enhancement / Color shifting (no published scale, so the levels are ours) |
| Symmetry | Each cell's quadrant is mirrored four ways, gated by a local texture-energy mask, so smooth walls stay smooth | PW Symmetrical texture repetition (no scale) |
| Geometry | Stripes and lattices drawn in cortical coordinates (log r, θ) and mapped to the field, which yields Klüver's tunnels, spirals, funnels, lattices and cobwebs | Bressloff et al. 2001 (doi:10.1098/rstb.2000.0769); PW Geometry levels 1–4 of 8 |

Geometry levels 5 and above (3D geometry, geometry that overrides vision) are beyond what an
overlay on a camera image can show.

Moving objects are found without segmentation. A slow running average (τ ≈ 1 s) stands in for
the static background. A tracer copy is drawn where it differs from that average, and the live
frame is protected where it differs. That is why trails follow objects and leave walls alone. At
"whole field" scope the gate opens.

## Hallucination: shaders for early vision, a generative model for expectation

The lab splits the visual hierarchy into two kinds of process.

- **Early vision is shaders.** Form constants come from V1's retinotopic geometry (Ermentrout &
  Cowan 1979, doi:10.1007/BF00336965; Bressloff et al. 2001). Tracers come from the temporal
  sampling of perception: perceptual echoes at ~10 Hz (VanRullen & Macdonald 2012,
  doi:10.1016/j.cub.2012.03.050) and tracer strobes at 15–20 Hz. These are cheap,
  parametric and run at 60 fps.
- **High-level expectation is a generative model.** In predictive processing, perception
  combines a top-down prediction with bottom-up evidence, each weighted by its precision.
  SD-Turbo img2img plays the prediction: it re-imagines the frame toward what it "expects"
  (the content prompt), and *Prior strength* is how far it may move away from the input. The same
  split appears in Suzuki et al. 2017's Hallucination Machine (doi:10.1038/s41598-017-16316-2).
  There, DeepDream on panoramic video scored close to psilocybin on several dimensions of the
  Altered States of Consciousness questionnaire, and lower network layers gave patterns while
  higher layers gave objects.

**The precision map** decides, per pixel, whether the prior or the senses win. The prior wins
where sensory evidence is weak:

- busy textures, the classic site of pareidolia;
- the low-acuity periphery;
- the scene after a long stare. The prior builds over ~6 s of camera stillness and resets on a
  glance away, the way reported effects intensify with fixation and reset on a double take.

The senses win wherever the image has changed since the prior last saw it, because fresh change
is a large prediction error. This also keeps moving things solid while the prior lags behind at
~1.5 fps. *Show → Precision map* renders the map in amber.

**The model takes no side in the theory debate.** REBUS (Carhart-Harris & Friston 2019,
doi:10.1124/pr.118.017160) argues that psychedelics *relax* high-level priors. Work on
hallucination (Corlett et al. 2019, doi:10.1016/j.tics.2018.12.001) finds that *strong* priors
produce it. The tool shows the balance as two sliders instead of choosing a side.

**Running it.** On an M1 Max the prior takes 480–760 ms a frame for 512×288 (MPS, fp16, 1–2
steps). The browser runs every shader effect at full rate and cross-fades each prior frame in
over the time the next one takes.

```bash
cd prototypes/replication-camera
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python prior_server.py        # first run downloads stabilityai/sd-turbo (fp16, ~2.4 GB)
open -a "Google Chrome" index.html      # then Camera → Hallucination
```

Set `HF_HOME` to keep the weights somewhere other than `~/.cache/huggingface`. The server
listens on `ws://127.0.0.1:8799` and picks MPS, then CUDA, then CPU.
`prior_server.py bench <image> "<prompt>"` times three strengths and saves the outputs.
Without the server, every shader effect still works; the Hallucination panel shows how to
start it.

**The phone question.** The prior can't run live on an iPhone. A port would either run the
shaders live with the prior on a "capture, then imagine" photo, or stream to the Mac.

## Native port

The passes map one-to-one, and the shaders are short, so the GLSL ports almost line for line.

1. **iOS / Mac:** `AVCaptureSession` (back camera, 1080p at 60 fps) → `CVMetalTextureCache` →
   an `MTKView` render loop. Passes: warp → background EMA (`rgba16Float`, half resolution) →
   trail EMA (`rgba16Float`) → history ring (one `texture2d_array` of 90 slices at half
   resolution, ≈47 MB at 480×270) → snapshot ring (4 slices) → composite. Port GLSL to MSL.
   The Mac gets the built-in or Continuity Camera through the same AVFoundation path.
2. **Android:** CameraX `SurfaceTexture` → GLES 3.0. The prototype's shaders are already GLSL
   ES 3.00, so they move across unchanged apart from the `samplerExternalOES` input.
3. **State:** one `@Observable` `ReplicationStore` holding the same model as `EFFECTS` and
   `state.fx` here (level presets and parameters). The level copy and sources go in the bundled
   DB beside the effect rows, keyed by PW effect name, per the no-pharma-data-in-Swift rule.
4. **Entry:** on a substance page, each visual effect row in *All effects* that has a
   replication (Tracers, Drifting, Color enhancement, Color shifting, Symmetrical texture
   repetition, Geometry) gets a "See it" action. It opens the camera on that effect at level 2.

## Things the native build must do that the prototype doesn't

- **Photosensitivity.** The strobe and color-pulse layers flicker at 2–40 Hz. Cap full-field
  luminance flicker at 3 per second (WCAG 2.3.1) unless the user raises it. Show a one-time
  warning before the first open, and start with Reduce Motion's settings (no pulse, no strobe)
  when Reduce Motion is on.
- **Camera framing.** The test scene stands still, but a handheld phone moves the whole image.
  On a real camera the background average lags the motion, so "moving objects" tracers smear
  the whole frame. Either stabilize (`AVCaptureConnection.preferredVideoStabilizationMode =
  .cinematicExtended`) or subtract the global motion (Vision's `VNTranslationalImageRegistration`)
  before the history ring. This is the one open technical question, and it needs a phone in hand.
- **Thermals.** Eight copy samplers plus three warp taps per pixel at 1080p60 is fine on an A17
  or later. Process at 960 px on the long side as the prototype does, then upscale.
