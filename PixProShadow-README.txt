=============================================================================
 PixProShadow — Multi-Layer Extruded Shadow for Pixelmator Pro
=============================================================================

PixProShadow is a macOS AppleScript applet that creates a deep, extruded
("long shadow" / 3-D block) shadow behind a selected layer in Pixelmator
Pro. It works with text layers, shape layers, and image layers. The user
chooses a two-colour shadow gradient, an angle, and a depth; the applet
builds the extrusion out of a stack of offset copies and merges it into a
single shadow layer.

Applet:   /Applications/PixProShadow.app
Source:   ~/My_Applications/PixProShadow/PixProShadow.applescript
Defaults: plist of saved settings (colors stored as normalized R,G,B)


-----------------------------------------------------------------------------
 HOW TO USE IT
-----------------------------------------------------------------------------

    1. In Pixelmator Pro, select the one layer you want the shadow behind.
       Text, shape and image layers all work.

    2. Run PixProShadow (/Applications/PixProShadow.app).

    3. Pick the two gradient colors. The color picker opens twice: first
       the START color, closest to the layer, then the END color, the
       deepest part of the shadow. The eyedropper samples any color on
       screen.

    4. Enter angle / depth, for example 45 / 25.
           Angle   counter-clockwise: 0=left, 90=down, 180=right, 270=up
           Depth   pixels (25), millimeters (5mm) or math (72/25.4*5)
       The dialog suggests a depth that suits the selected layer.

    5. Click OK and let it build.

You get one group named after the source layer. Your original is the bottom
layer of that group, untouched — delete the group and run again with other
settings to start over.


-----------------------------------------------------------------------------
 HOW THE EFFECT IS BUILT (techniques)
-----------------------------------------------------------------------------

PIXEL SOURCE
    The original layer is duplicated and the duplicate converted into
    pixels; the real original is never modified. This single unified path
    serves all layer types with no "convert?" dialogs.

TRUE PIXEL POSITION
    After conversion the layer position is re-read: text and shape layers
    report their position as a baseline / vector origin, while correct
    shadow placement needs the rendered pixel bounding-box top-left —
    which is exactly what the converted pixel layer reports.

EXTRUSION BY OFFSET STACKING
    A "face" copy is made, then one copy per step of the chosen depth,
    each offset progressively along the shadow angle (0-360 degrees,
    counter-clockwise, 0 = right). Stacked together the copies form a
    solid extrusion connecting the face to the shadow's far end.

GRADIENT ACROSS THE STACK
    The two chosen colours (macOS colour picker with eyedropper) are
    interpolated across ALL the stacked copies, so the extrusion shades
    smoothly from the start colour at the face to the end colour at the
    tail.

MERGE AND INDEX BOOKKEEPING
    The face-to-tail stack is merged into one layer, "<name> shadow".
    Layer indices are tracked arithmetically throughout (pixelLayerIndex,
    faceIndex): Pixelmator's `duplicate layer X` puts the copy AT index X
    and shifts the original down, `current layer` only follows the
    selected layer, and merges collapse N layers to 1 — so every index is
    computed, never read back from the app's selection state.

DEPTH INPUT
    Plain pixels (25), millimetres (5mm), or math expressions
    (72/25.4*5, 5mm+10, 25*2).

RESULT GROUPING
    The output is a group named after the source layer, containing
    (top to bottom):
        <name>.pixel  — pixel copy of the original
        <name> shadow — the merged extruded shadow
        <name>        — the real original, untouched
    Other layers in the document are left completely alone.


-----------------------------------------------------------------------------
 IF THE RESULT IS NOT WHAT YOU EXPECTED
-----------------------------------------------------------------------------

Multiple layers are created in this process. They are collected into one
group named after the source layer.

The BOTTOM layer of that group is your ORIGINAL, untouched. To start over:
drag that bottom layer out of the group to the top level of the Layers list
and make it visible, then delete the group and run PixProShadow again with
adjusted settings.

Nothing is lost by retrying — the original is never modified.


-----------------------------------------------------------------------------
 VERSION HISTORY (v7.x line; v1-v6 predate these records)
-----------------------------------------------------------------------------

v7.0.8  (base)
    Working baseline. Asked "Duplicate & Convert / Convert in Place /
    Cancel" for text and shape layers; image layers processed directly.
    Used `index of current layer` to find the face copy — unreliable
    whenever the pixel layer was not the currently selected layer.

v7.1.0
    Unified, dialog-free path: every layer type is auto-duplicated and
    converted to pixels; the original is never hidden or deleted. Fixed
    the face-index bug by computing faceIndex from pixelLayerIndex
    instead of reading `current layer`.

v7.1.1
    The .pixel copy is moved to just above the merged shadow (was: top
    of the whole document).

v7.1.2
    Debug logging fix: the tsLog handler ran its shell echo even with
    debugMode off; the handler now guards itself with `if debugMode`.

v7.2.0
    Grouped output. The .pixel + shadow + original layers are grouped
    under the source layer's name; the old "force every layer visible"
    step was removed — other layers are no longer touched.

v7.2.1  (2026-06-25)
    No functional change. Added CFBundleShortVersionString /
    CFBundleVersion / copyright to the app's Info.plist so Finder's
    Get Info shows the version, and re-signed the app. Source encoding
    converted from UTF-16 LE to UTF-8 (lossless, bytecode verified
    identical).



v7.3.0  (2026-08-10)
    Targets whichever Pixelmator build is actually in use. Since the Creator
    Studio rebrand there are two installs — com.apple.pixelmator (Creator
    Studio 4.x) and com.pixelmatorteam.pixelmator.x (Pixelmator Pro 3.x) —
    and `tell application "Pixelmator Pro"` bound to a fixed app path at
    compile time. A document open in the other build therefore read as no
    document at all. The build is now resolved at run time by bundle id
    (pixTarget): frontmost first, then any running build with a document.


v7.4.0  (2026-08-10)
    Read Me button. This README is now copied into the app bundle's own
    Contents/Resources at build time and opened via `path to resource`, so it
    travels inside the app — nothing depends on ~/My_Applications or any other
    external path. The button sits on the colour-picker entry prompt and returns you
    to the prompt after the Read Me opens.

v7.5.0  (2026-08-15)
    Targets the running Pixelmator by BUNDLE PATH instead of by bundle id.
    Several COPIES of one build can be installed and copies share an
    identifier, so `tell application id` could not tell them apart: it
    addressed whichever copy macOS preferred, launched that copy if it was not
    already running, and then failed on the empty one. The path and pid of
    every running Pixelmator process are read from `ps`, which is the one
    thing that distinguishes identical copies, and everything is keyed to
    that.


v7.5.1  (2026-08-19)
    Signing release; no change to the effect. Signed with the Developer ID
    certificate under the hardened runtime and notarized, plus the two things
    osacompile does not put in an applet:

        com.apple.security.automation.apple-events. The hardened runtime
        stops an app from ASKING for Automation, so without this entitlement
        the applet keeps working on a Mac that already granted access and
        fails on a fresh one with "Not authorized to send Apple events"
        (-1743) — with no way for the user to switch it on by hand, because
        it never appears in the Automation list.

        A real CFBundleIdentifier (com.timmccoy.pixproshadow). osacompile writes
        none and drops it again on every rebuild, so codesign had been sealing
        the bundle NAME instead: nothing could address the app with
        `tell application id`, and it could hold no defaults domain.


v7.5.2  (2026-09-13)  — current
    Documentation release; no change to the effect. Adds a HOW TO USE IT
    section — numbered steps from selecting the layer, through every dialog
    field and its units, to what the result group contains — and fills in a
    version history that had stopped one release short of the shipping build.
    The copy inside the bundle was refreshed with it, so the Read Me button
    shows the same text.


-----------------------------------------------------------------------------
 Copyright (c) 2026 Tim McCoy. All rights reserved.

 Developed with the support of Claude (Anthropic) — design, code, and
 testing assistance.
=============================================================================
