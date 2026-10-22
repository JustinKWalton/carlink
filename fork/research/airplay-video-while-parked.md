# CarPlay "video while parked" through the CPC200-CCPA: feasibility (2026-10-22)

Read-only research. Nothing was flashed, pushed or changed. **[V]** = verified in a cited source;
**[I]** = inference; **[U]** = unverified / unknown.

## 1. How the iPhone decides a head unit can play video

**Primary gate: the CarPlay/AirPlay session-level feature `videoPlayback` (a string in the AirPlay
SETUP `features` array), backed by the CarKit `supportsVideo` identification flag — NOT the mDNS
`features` bitfield.**

- [V] During AirPlay SETUP (RTSP over TCP 5000, after pair-verify) the iPhone sends its own `features`
  array. In the iOS 26.5 capture it includes `videoPlayback` alongside `viewAreas`, `altScreen`,
  `hevc`, `h.264Level5.1`, `vehicleStateProtocol`, `sessionManagement`, etc. The box answers with
  `enabledFeatures: ["viewAreas"]` — **the intersection of HU capability and the phone's offer.**
  (CPC200 RE: `_evidence/MFi_research/CAPTURE_SESSION.md` §9.3.4; `carplay_handshake.md` Phase G.)
  So `videoPlayback` is a named capability the phone already understands; the box simply never
  echoes it back as enabled.
- [V] At the CarKit/iAP2 identification layer, iOS 26.5 exposes `supportsVideo` ("Video stream to
  accessory display"), and the stock CCPA already claims it (that is how ordinary CarPlay UI
  projection works). (`carkit_ios26_master.md` §3.3, §5.1.) Plain `supportsVideo` is NOT the
  video-playback gate — every CarPlay head unit sets it. iOS 26.4/27 added a *separate* "video
  playback" notion on top.
- [V] Apple's own framing (WWDC 2025/2026, iOS 26.4 beta code, iOS 27 SDK): video playback is an
  **AirPlay hand-off** — the iPhone streams the video to the car, playback is allowed **only when
  parked**, and **the automaker must opt in** ("extra hardware demands for video and detect when the
  vehicle is parked"). iOS 27 adds a `CPSessionConfiguration.supportsVideoPlayback` boolean that the
  app reads; Apple says the parked-state lock is **enforced by the system, not the app**, and in some
  cars "no infotainment update is required" while others need one. (9to5mac, MacRumors, Apple
  Developer Forums thread 838529, heise.) These describe the *phone→car app* contract, not the exact
  accessory wire bytes.
- [U] The exact new wire token the accessory must send to flip video-playback on is **not** in any
  source I have. Candidates, in order of likelihood: (a) the box echoing `videoPlayback` in
  `enabledFeatures` during SETUP; (b) a new CarKit `setSupports…` identification flag not yet
  enumerated in the iOS 26.5 RE (the RE lists 62 `supports*` getters but no `supportsVideoPlayback`
  among them — meaning it may be an AirPlay-session key, consistent with (a)); (c) a vehicle-state
  (`IsVehicleParkedKey`, `vehicleStateProtocol`) requirement the box must also satisfy.

**Confidence:** high that it is the AirPlay SETUP `videoPlayback` feature + parked state; low on the
precise bytes.

### The mDNS `features=0x44440B80,0x61` (what the box advertises today)
- [V] This is the AirPlay TXT-record feature bitfield, decoded against the public AirPlay spec
  (openairplay). `0x44440B80,0x61` = low word `0x44440B80`, high word `0x61`.
  Low word bits set: 7 Screen, 8 ScreenRotate, 9 Audio, 11 AudioRedundant, 18/19 AudioFormat1/2,
  22, 26 UnifiedAdvertiserInfo, 30 RAOP. High word (`0x61` → bits 32,37,38): 32 IsCarPlay,
  38 CoreUtilsPairingAndEncryption.
  **Notably clear: bit 0 Video, bit 4 VideoHTTPLiveStreams, bit 33 SupportsAirPlayVideoPlayQueue,
  bit 42 ScreenMultiCodec.** The box advertises itself as a *screen-mirroring CarPlay* receiver, not
  an AirPlay *video* receiver.
- [I] Flipping these mDNS bits alone is almost certainly **not** how iOS 26 CarPlay gates video —
  CarPlay negotiates capability over the encrypted RTSP SETUP channel (the `features` array above),
  not from the discovery TXT record. But bit 0/4/33 are the cleanest thing to toggle as a cheap probe
  (see §4). The real `_carplay._tcp`/`_carplay-ctrl._tcp` path is driven by the SETUP exchange.

## 2. What the box firmware would need

The box (AppleCarPlay / ARMiPhoneIAP2 / ARMadb-driver on armv7l) is the AirPlay receiver and does all
negotiation. To support video playback it would have to:

- **(a) Advertise the capability.** Make `AppleCarPlay` include `videoPlayback` (and whatever the
  parked/vehicle-state prerequisite is) in the SETUP response `enabledFeatures`, and/or set the new
  CarKit video-playback identification flag in `ARMiPhoneIAP2`'s identify engine. Today `enabledFeatures`
  is computed as HU∩phone and only `viewAreas` is enabled because the HU globals
  (`g_bSupportViewarea`, `g_bSupportNaviScreen`) gate it — the same gating machinery would need a new
  `g_bSupportVideoPlayback`-style path that the stock binary does not contain. [I]
- **(b) Handle the hand-off.** iOS 26/27 video playback is an **AirPlay media hand-off**, not the
  H.264 screen stream: the phone hands the car a *media item* (URL/stream) and transport commands
  (`play`/`pause`/`stop`/`scrub`, plus `playback-info`/`rate`), and the car plays it in its **own
  player** (confirmed by CarCast and rPlayFling below). The CCPA's existing AirPlay server only knows
  the **screen** stream path (`AirPlayReceiverSessionScreen_ProcessFrames`, NAL parse, forward raw
  H.264 over USB as `VIDEO_DATA 0x06`). It has **no media-playback / play-queue handler**. [V for the
  screen-only path: `key_binaries.md` "Key Functions (AppleCarPlay)"; the `/command` RTSP endpoint and
  `AirPlay video control commands use HTTP-over-RTSP` exist (`firmware_internals.md`) but are the
  mirroring control channel.]
- **(c) Get URL + transport to the app over USB.** Two sub-problems:
  - If the box were to **decode** the handed-off video itself and keep shipping H.264 as `VIDEO_DATA
    0x06`, the app needs **no** new message type — it already renders that stream. But the armv7
    box has no spare budget to fetch+decode+re-encode a 1080p stream, and that is not how the modern
    path works.
  - If the box passes the **media URL + transport commands** up for the *app* to play (the sane
    design on this SoC), that needs a **new box→app USB message type**. The app's `MessageType` enum
    (`protocol/MessageTypes.kt`) has no such type; unknown types already fall through to
    `UnknownMessage` and are logged under `PROTO_UNKNOWN` (so nothing breaks, but nothing plays).
    `MEDIA_DATA 0x2A` (NaviJSON/metadata) is the closest existing sideband and could in principle
    carry a new JSON subtype, but the receiver side in the firmware does not emit it. [V enum +
    unknown handling]
- **(d) Does the firmware already contain video-playback handlers?** **No evidence that it does.**
  The RE corpus (string tables, memory dumps, 50+ agent cross-check) documents only screen-mirroring
  H.264 + AirPlay audio + the `/command` mirroring control channel. There is **no** AirPlay
  play-queue, `playback-info`, HLS, or media-URL handler in the AppleCarPlay strings, and
  `carkit_ios26_master.md` lists video playback nowhere in the CCPA claim inventory. The CCPA's own
  AirPlay/AirTunes banner is **320.17**; the iPhone is **950.7.1** — the box's receiver is many
  generations behind the feature. [V — absence across `key_binaries.md`, `video_protocol.md`,
  `firmware_internals.md`, `carkit_ios26_master.md` §5.2]

**Effort:** very high — new receiver-side capability negotiation **and** a new media-playback engine
in a closed, UPX-LZMA-packed armv7 binary whose video code only knows screen mirroring, plus a new
USB message and a new app player. This is a different order of magnitude from the shipped NAV/CALL/COMM
patches, which only *reformat existing* iAP2 messages into the metadata sideband via a 1224-byte code
cave. There is no code to "unlock" here; it would have to be **written** into the binary. [I]

**Brick/rollback risk:** the *mechanism* is low-risk — dropbear SSH starts in `rcS` before
`start_main_service.sh`, and deploys via `/tmp/bin` push (SendFile `0x99`) revert on reboot; a bad UPX
pack just fails to load and CarPlay won't connect (non-bricking). (`iap2_binary_patches.md` §3.4-3.6.)
But the *scope* of the change (replacing the AirPlay receiver's media path) makes a working result
unlikely regardless of rollback safety.

## 3. Alternatives that avoid box-firmware changes

- **App-side AirPlay video receiver on the radio's Wi-Fi: NOT viable.** The iPhone, when connected
  through the CCPA, is on the **box's** 5 GHz SoftAP (`192.168.43.x`), not on gminfo3.7's Wi-Fi, and
  the app only sees the box over USB. For the phone to hand video to the *radio*, the radio would have
  to be the AirPlay receiver the phone is paired to — i.e. replace the box. An Android 12 AAOS app
  *can* advertise `_airplay._tcp` via `NsdManager`, but (i) the iPhone is not on the same L2 network,
  and (ii) **CarPlay video playback is gated behind MFi + the CarPlay pairing**, which a bare Android
  app cannot satisfy (no MFi coprocessor, no CarPlay trust). A plain AirPlay-mirroring receiver (à la
  UxPlay) is a *different* feature and still wouldn't be on the phone's network here. [I, strong]
- **Swap the box for a receiver that already does it.** CarCast (rPlayAI) is a closed-source CarPlay
  receiver that **already supports iOS 26.4/27.2 video playback** on Android head units: "CarCast tells
  the iPhone it is a head unit that can play video. The phone then hands the video to the car, and
  CarCast plays it with its own player." It runs on Android head units (and as OEM firmware on the same
  Allwinner-class SoCs these boxes use), fetches the video "through the iPhone, as a real car does, or
  directly when online," and reports position/state back. Pairing app rPlayFling casts YouTube/DLNA to
  it. This confirms the hand-off model and shows the realistic path is a **different receiver**, not a
  patched CCPA. CarCast is OEM/licensed, so it is not a drop-in for the fork. [V — carcast-public
  README + docs; rPlayFling-public README/user-guide]
- **AAOS will block video while driving regardless.** gminfo3.7 is AAOS; the app's projection
  activities are `distractionOptimized` and the system enforces no-video-while-moving. This *aligns*
  with Apple's parked-only rule, but it means even a working path only shows video in Park. H.264 HW
  decode on the Intel VPU is ample (720x480 @ ~900 fps; 1080p @ ~340 fps). ExoPlayer/`media3-exoplayer`
  is **not** a current dependency (only `media3-session`/`-common`), so playing an HLS/MP4 URL in-app
  would mean adding `media3-exoplayer` + HLS and a Park-gated Surface. That is the easy half; the hard
  half is getting the URL/commands out of a box that never produces them. [V — AndroidManifest,
  build.gradle.kts, gminfo README]

## 4. Go / no-go and the smallest proving experiment

**No-go for a shipped feature on the CCPA.** The box's AirPlay receiver is screen-mirroring only, lacks
any media-playback/play-queue engine, runs AirPlay 320.17, and would need that engine *written* into a
packed armv7 binary plus a new USB path and app player — with the exact capability token still unknown.
Realistic route to the feature is a different receiver (CarCast-class) or waiting for Carlinkit firmware.

**Smallest experiment to learn whether the phone will even offer video to this box** (safe, volatile,
reversible via reboot — do only if you want the data point, not as a fix):

1. Arm SSH-over-USB-NCM (box Wi-Fi SSH once to set it up): stop the cycler
   (`killall ARMadb-driver ARMiPhoneIAP2`), switch the external gadget to NCM, `ssh root@192.168.50.2`.
   (`CPC200-CCPA_SSH_over_USB_NCM.md`.) Confirm dropbear is up (it is, on the custom 2025.10.15.1127 FW).
2. **Capture-first, do not patch:** with a normal CarPlay session running, grab the firmware `ttyLog`
   and the RTSP SETUP exchange and confirm the phone's `features` array still lists `videoPlayback`
   and the box's `enabledFeatures` omits it. This alone tells you the phone offers it and the box
   declines — the whole question in one capture. No write needed.
3. Only if you want to probe the discovery layer: temporarily set mDNS `features` bit 0 (Video) and
   bit 4 (VideoHTTPLiveStreams) — i.e. advertise `0x44440B91,0x61` instead of `0x44440B80,0x61` — by
   restarting `AppleCarPlay` with a modified TXT record, reconnect, and watch for any new SETUP
   behaviour or a video affordance in CarPlay. **Expectation: no change** (CarPlay gates on the SETUP
   `features`, not the TXT bits), which is itself the useful negative result. Rollback: reboot the box
   (everything in steps 1-3 is RAM/tmpfs-only). [I for the bit positions and the expected negative]
4. Do **not** attempt a persistent `/usr/sbin` AppleCarPlay replacement — there is no patch to deploy,
   and a persistent bad binary needs the factory backup to restore.

**Bottom line:** the phone almost certainly *offers* `videoPlayback`; the CCPA declines it and has no
machinery to accept or play it. Proving the offer is a 10-minute read-only capture; making it work is a
receiver rewrite, not a patch.
