-- ============================================================
-- PixProShadow.applescript
-- Version 7.5.0  (2026-08-15)
--
-- New in 7.5.0: targets the running Pixelmator by BUNDLE PATH rather than by
--   bundle id, so it works with whichever build and whichever COPY of a build
--   is actually open. Several copies of the same version can be installed and
--   they share one bundle id; resolving by id talked to the wrong copy and
--   failed with "Can't get document 1 ... Invalid index (-1719)". See
--   pixTarget.
--
-- New in 7.3.0: targets whichever Pixelmator build is actually in use,
--   resolved at run time by bundle id (see pixTarget). Since the Creator
--   Studio rebrand `tell application "Pixelmator Pro"` bound to a fixed path
--   at compile time, so a document open in the other build read as no
--   document at all.
--
-- Copyright (c) 2026 Tim McCoy. All rights reserved.
-- Developed with assistance from Claude (Anthropic).
--
-- New in 7.2.1: added bundle version + copyright to the app
--   Info.plist (shown in Finder Get Info) and re-signed; no
--   functional change to the script.
--
-- New in 7.2.0: results (.pixel + shadow) and the source layer are grouped
--   under the source layer name; the script no longer forces every other
--   layer visible (old Step 11).
--
-- Creates a multi-layer extruded shadow effect behind a
-- selected layer in Pixelmator Pro. Works with text layers,
-- shape layers, and image layers. Prompts the user for:
--   • Shadow gradient (two-color, interpolated across ALL layers)
--   • Shadow angle (0-360 counter-clockwise, 0=right)
--   • Shadow depth (pixels, mm, or math expression)
--
-- Depth field accepts:
--   • Plain number:       25
--   • Millimetres:        5mm
--   • Math expression:    72/25.4*5
--   • Mixed:              5mm+10   or   25*2
--
-- Color input uses the macOS color picker (choose color).
--   The picker opens twice — once for the START color, once for
--   the END color.  Use the eyedropper to sample any on-screen
--   color.  Colors are saved to plist as normalized R,G,B.
--
-- Layer type handling:
--   ALL TYPES: Original is always duplicated first, then the
--          duplicate is converted to pixels. The real original
--          stays in the document, unchanged and visible, below
--          the result. No dialog is shown — conversion is
--          automatic for text, shape, and image layers alike.
--   After processing (top to bottom):
--          <name>.pixel  — pixel copy of original, on top
--          <name> shadow — merged shadow layer below it
--          <name>        — real original, untouched
--
-- IMPORTANT: After conversion, position is re-read from the
-- converted layer. Text and shape layers report position as
-- their baseline/vector origin, not the pixel bounding box
-- top-left. The pixel bounding box position is required for
-- correct shadow placement.
--
-- pixelLayerIndex tracks the pixel layer throughout the loop.
-- After merge: shadow stack collapses from N layers to 1.
-- pixelLayerIndex is adjusted for this collapse to find the
-- correct post-merge index, then the pixel layer is renamed
-- to <originalLayerName>.pixel and moved above the shadow.
--
-- After duplicate layer X, copy lands AT index X and original
-- shifts to X+1. currentOriginalIndex tracks original throughout.
--
-- The resolved depth integer (not the raw expression) is saved
-- to the plist so no quoting issues arise on subsequent runs.
--
-- Defaults saved to ~/.shadowtext_defaults.plist
-- ============================================================

property debugMode : false

-- ============================================================
-- WHICH PIXELMATOR?  (added 2026-08-10, rewritten 2026-08-15)
-- Resolved at run time, by path, in pixTarget below. Holds the bundle path
-- of the build being driven, e.g. "/Applications/Pixelmator Pro_3.8.app".
-- ============================================================
property kPixIDs : {"com.apple.pixelmator", "com.pixelmatorteam.pixelmator.x"}

property scriptVersion : "7.6.4"

-- ============================================================
-- UPDATE CHECK (reports only, never downloads)
-- ============================================================
-- Asks GitHub for the newest published tag and adds a line to the prompt when
-- this build is behind. It never downloads or replaces anything: a running
-- bundle cannot safely overwrite its own files, and getting that wrong costs
-- the app.
--
-- Checked once a day at most and capped at three seconds, so a slow or absent
-- network barely shows. The tag and the day it was fetched are kept in the
-- same defaults file as the settings.
--
-- The JSON is picked apart with grep and cut rather than a parser: a stranger's
-- Mac is not guaranteed to have python3, and the tag is the only field wanted.
property kSlug : "pixproshadow"
property kDefaults : "$HOME/.shadowtext_defaults"

on versionParts(v)
	set out to {}
	set AppleScript's text item delimiters to "."
	set pieces to text items of v
	set AppleScript's text item delimiters to ""
	repeat with piece in pieces
		set digits to ""
		repeat with c in (characters of (piece as text))
			if c is in "0123456789" then set digits to digits & c
		end repeat
		if digits is "" then set digits to "0"
		set end of out to digits as integer
	end repeat
	return out
end versionParts

on isNewer(tag, mine)
	-- Compared as integers, so 3.10.0 comes out above 3.9.0 rather than below.
	set a to my versionParts(tag)
	set b to my versionParts(mine)
	repeat with i from 1 to 3
		set x to 0
		set y to 0
		if i ≤ (count a) then set x to item i of a
		if i ≤ (count b) then set y to item i of b
		if x > y then return true
		if x < y then return false
	end repeat
	return false
end isNewer

on latestTag()
	set today to do shell script "/bin/date +%Y-%m-%d"
	set lastDay to ""
	try
		set lastDay to do shell script "defaults read " & kDefaults & " updateCheckedOn 2>/dev/null"
	end try
	if lastDay is today then
		try
			return do shell script "defaults read " & kDefaults & " updateLatestTag 2>/dev/null"
		end try
		return ""
	end if
	try
		set tag to do shell script "/usr/bin/curl -sL --max-time 3 -H \"Accept: application/vnd.github+json\" https://api.github.com/repos/spurious-cox/" & kSlug & "/releases/latest | /usr/bin/grep -o '\"tag_name\": *\"[^\"]*\"' | /usr/bin/head -1 | /usr/bin/cut -d'\"' -f4"
		do shell script "defaults write " & kDefaults & " updateLatestTag " & quoted form of tag
		do shell script "defaults write " & kDefaults & " updateCheckedOn " & quoted form of today
		return tag
	on error
		return ""
	end try
end latestTag

on updateNotice(mine)
	set tag to my latestTag()
	if tag is "" then return ""
	if not (my isNewer(tag, mine)) then return ""
	set t to tag
	if t starts with "v" then set t to text 2 thru -1 of t
	return return & return & "Update available: " & t & "  —  brew upgrade --cask " & kSlug
end updateNotice


property pixApp : ""

-- ============================================================
-- READ ME
-- The README is copied into this applet's OWN Contents/Resources at build
-- time and found with `path to resource`, so it travels inside the bundle.
-- Nothing here depends on ~/My_Applications, or on any other external path:
-- move or copy the app anywhere and the Read Me button still works.
-- ============================================================
on showReadMe()
	try
		set rmRef to (path to resource "PixProShadow-README.txt")
		do shell script "open -e " & quoted form of (POSIX path of rmRef)
	on error
		tell me to activate
		display dialog "The Read Me is missing from the app bundle." buttons {"OK"} default button "OK"
	end try
end showReadMe


-- Returns the BUNDLE PATH of the Pixelmator to talk to, or "" if none is
-- running. A path, not a bundle id, because Tim keeps several builds
-- installed and copies of the same version share an identifier:
--
--   com.pixelmatorteam.pixelmator.x   Pixelmator Pro.app, Pixelmator Pro_3.8.app,
--                                     Pixelmator Pro_3.7.1.app
--   com.apple.pixelmator              Pixelmator Pro Creator Studio.app,
--                                     Pixelmator Pro_4.2.app
--
-- `tell application id` cannot tell two processes of the same id apart. It
-- resolves to whichever copy LaunchServices prefers and LAUNCHES it if that
-- one is not running -- so with a document open in Pixelmator Pro_3.8, the
-- script would talk to an empty Pixelmator Pro.app and fail with
-- "Can't get document 1 ... Invalid index (-1719)", leaving two instances
-- running. System Events cannot help: asked for the file of each process it
-- reports the same path for both, because it resolves by id as well.
--
-- ps knows the real executable path of every running process, which is the
-- one thing that distinguishes them. Preference order: frontmost build with a
-- document, then any build with a document, then frontmost, then whatever is
-- running.
on pixTarget()
	set rawPaths to {}
	try
		set psOut to do shell script "/bin/ps -Axo args= | /usr/bin/grep '/Contents/MacOS/Pixelmator' | /usr/bin/grep -v grep | /usr/bin/sed 's|/Contents/MacOS/.*||' | /usr/bin/sort -u"
		-- `do shell script` separates lines with RETURN, not linefeed. Split on
		-- the wrong one and every path arrives glued into a single string.
		set AppleScript's text item delimiters to return
		set rawPaths to text items of psOut
		set AppleScript's text item delimiters to ""
	end try

	-- Keep only genuine Pixelmator Pro builds, identified by the bundle id in
	-- each app's OWN Info.plist. Nothing here depends on what the app is
	-- called or where it lives, so this works on any Mac: renamed bundles,
	-- App Store or Setapp copies, apps in ~/Applications, all fine. It also
	-- excludes the classic Pixelmator (com.pixelmatorteam.pixelmator), whose
	-- dictionary is different and which would fail halfway through.
	set candidates to {}
	repeat with rp in rawPaths
		set p to rp as text
		if p is not "" then
			try
				set theID to do shell script "/usr/bin/defaults read " & quoted form of (p & "/Contents/Info") & " CFBundleIdentifier"
				if theID is in kPixIDs then set end of candidates to p
			end try
		end if
	end repeat
	if candidates is {} then return ""

	-- Which of them, if any, is frontmost. The frontmost process's pid maps
	-- back to its bundle path through ps.
	set frontPath to ""
	try
		-- Bounded: asking System Events which app is frontmost needs Automation
		-- permission, and on a first run that call sits there waiting for a
		-- consent prompt. If the prompt does not appear — and for a freshly
		-- built applet it may not — the app hangs with no window and nothing
		-- to click. Five seconds, then carry on: the frontmost check only
		-- orders the candidates, it does not find them.
		with timeout of 5 seconds
			tell application "System Events"
				set fpid to unix id of (first application process whose frontmost is true)
			end tell
		end timeout
		set frontPath to do shell script "/bin/ps -p " & fpid & " -o args= | /usr/bin/sed 's|/Contents/MacOS/.*||'"
	end try

	set ordered to {}
	repeat with c in candidates
		set cc to c as text
		if cc is equal to frontPath then set end of ordered to cc
	end repeat
	repeat with c in candidates
		set cc to c as text
		if cc is not equal to frontPath then set end of ordered to cc
	end repeat

	repeat with c in ordered
		set cc to c as text
		try
			using terms from application "Pixelmator Pro"
				tell application cc
					if (count of documents) > 0 then return cc
				end tell
			end using terms from
		end try
	end repeat
	return item 1 of ordered
end pixTarget


if debugMode then
	do shell script "echo '' > ~/Desktop/ts_debug.txt"
	set startTime to do shell script "date '+%Y-%m-%d %H:%M:%S'"
	my tsLog("=== PixProShadow started at " & startTime & " ===")
end if

-- ============================================================
-- LOAD SAVED DEFAULTS
-- ============================================================
set defaultAngle to "315"
set defaultDepth to "20"
set defaultStartRGB to "0,0,80"
set defaultEndRGB to "80,0,0"
try
	set defaultAngle to do shell script "defaults read $HOME/.shadowtext_defaults angle 2>/dev/null"
end try
try
	set defaultDepth to do shell script "defaults read $HOME/.shadowtext_defaults depth 2>/dev/null"
end try
try
	set defaultStartRGB to do shell script "defaults read $HOME/.shadowtext_defaults startRGB 2>/dev/null"
end try
try
	set defaultEndRGB to do shell script "defaults read $HOME/.shadowtext_defaults endRGB 2>/dev/null"
end try

-- ============================================================
-- PICK THE PIXELMATOR BUILD (see pixTarget above)
-- ============================================================
set pixApp to pixTarget()
if pixApp is "" then
	tell me to activate
	display dialog "Pixelmator Pro is not running. Open Pixelmator Pro and a document, select a layer, and try again." buttons {"OK"} default button "OK" with title "PixProShadow"
	error number -128
end if


using terms from application "Pixelmator Pro"
tell application pixApp
	activate
	tell front document
		
		if not (count selected layers) = 1 then
			display alert "Make sure a single layer is selected."
		else
			
			-- ── Record original layer info ─────────────────────────────────
			set originalLayerName to name of current layer
			set originalLayerIndex to index of current layer
			set {coordX, coordY} to position of current layer
			set layerKind to (class of current layer) as text
			set isTextLayer to layerKind = "text layer"
			set isShapeLayer to layerKind = "shape layer"
			-- pixelLayerIndex tracks the pixel copy throughout.
			-- Created by duplicating the original and converting to pixels.
			-- Original shifts to originalLayerIndex+1 and is never touched.
			set pixelLayerIndex to originalLayerIndex
			set preservedOriginalIndex to -1 -- unused; kept for guard clauses below
			my tsLog("Got layer info: " & originalLayerName & " index=" & originalLayerIndex & " kind=" & layerKind)
			my tsLog("Pre-conversion position: " & (coordX as text) & "," & (coordY as text))
			
			-- ── Get document DPI ──────────────────────────────────────────
			set docDPI to 72
			try
				set docDPI to resolution of front document
			end try
			my tsLog("Document DPI: " & (docDPI as text))
			
			-- ════════════════════════════════════════════════════════════
			-- PIXEL COPY: Duplicate original and convert to pixels.
			-- Works for all layer types (text, shape, image).
			-- Duplicate puts copy AT originalLayerIndex; original shifts to +1.
			-- Converting to pixels gives the true rendered bounding box
			-- top-left as the layer position. The real original is NEVER
			-- modified or deleted — it stays in the document below the result.
			-- ════════════════════════════════════════════════════════════
			my tsLog("Pixel copy: duplicating original at index " & originalLayerIndex)
			duplicate layer originalLayerIndex
			-- Pixel copy at originalLayerIndex; original shifts to originalLayerIndex+1
			tell layer originalLayerIndex to convert into pixels
			set pixelLayerIndex to originalLayerIndex
			set isTextLayer to false
			set isShapeLayer to false
			set layerKind to "image layer"
			-- Re-read position after conversion — pixel bounding box top-left
			set {coordX, coordY} to position of layer pixelLayerIndex
			my tsLog("Pixel copy at " & pixelLayerIndex & ", original preserved at " & (originalLayerIndex + 1))
			my tsLog("Pixel copy position: " & (coordX as text) & "," & (coordY as text))
			
			-- ── Suggested depth ───────────────────────────────────────────
			set suggestedDepth to defaultDepth as number
			my tsLog("Suggested depth: " & suggestedDepth)
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 1: Pixel-space position.
			-- All layers are now image/pixel layers — coordX/coordY is
			-- the pixel bounding box top-left, correct for all uses.
			-- ════════════════════════════════════════════════════════════
			set pixelX to coordX
			set pixelY to coordY
			my tsLog("Step 1: pixel-space pos=" & (pixelX as text) & "," & (pixelY as text))
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 2: Prompt for shadow colors.
			-- ════════════════════════════════════════════════════════════
			-- Color picker opens twice: START color first, then END color.
			repeat
				set rmChoice to button returned of (display dialog "Pick TWO colors for the shadow gradient:" & return & ¬
					"  1 → START color  (closest to layer / face side)" & return & ¬
					"  2 → END color    (deepest layer)" & return & return & ¬
					"The color picker opens twice." & return & ¬
					¬
						"Use the eyedropper to sample any color on screen." & my updateNotice(scriptVersion) buttons {"Read Me", "Open Color Picker"} default button "Open Color Picker")
				if rmChoice is not "Read Me" then exit repeat
				my showReadMe()
			end repeat
			set startColorDefault to my parseRGB(defaultStartRGB)
			set shadowColor1 to choose color default color startColorDefault
			set endColorDefault to my parseRGB(defaultEndRGB)
			set shadowColor2 to choose color default color endColorDefault
			set saveStartRGB to my colorToRGBString(shadowColor1)
			set saveEndRGB to my colorToRGBString(shadowColor2)
			my tsLog("Colors picked: start=" & saveStartRGB & " end=" & saveEndRGB)
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 3: Prompt for shadow angle and depth.
			-- ════════════════════════════════════════════════════════════
			set angleDepthDefault to defaultAngle & " / " & defaultDepth
			set angleDepthInput to text returned of ¬
				(display dialog "Enter shadow angle and depth:" & return & ¬
					"Format: angle / depth" & return & ¬
					"Angle: 0=left  90=down  180=right  270=up" & return & ¬
					"45=lower-left  135=lower-right" & return & ¬
					"225=upper-right  315=upper-left" & return & ¬
					"(counter-clockwise)" & return & ¬
					"Depth: pixels, mm (e.g. 5mm), or math (e.g. 72/25.4*5)" & return & ¬
					"Suggested depth for this layer: " & suggestedDepth ¬
					default answer angleDepthDefault)
			set AppleScript's text item delimiters to " "
			set angleDepthInput to text items of angleDepthInput
			set AppleScript's text item delimiters to ""
			set angleDepthInput to angleDepthInput as text
			set firstSlash to 0
			repeat with i from 1 to (count characters of angleDepthInput)
				if character i of angleDepthInput is "/" then
					set firstSlash to i
					exit repeat
				end if
			end repeat
			set rawAngle to text 1 thru (firstSlash - 1) of angleDepthInput
			set rawDepth to text (firstSlash + 1) thru -1 of angleDepthInput
			set chosenAngle to rawAngle as number
			my tsLog("Angle=" & chosenAngle & " rawDepth=" & rawDepth)
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 4: Evaluate depth expression via Python 3.
			-- ════════════════════════════════════════════════════════════
			set stripeThickness to suggestedDepth
			try
				set depthScript to "import re; dpi=" & (docDPI as text) & "; expr='" & rawDepth & "'; expr=re.sub(r'([0-9.]+)mm', lambda m: str(float(m.group(1))*dpi/25.4), expr); print(int(round(eval(expr))))"
				set stripeThickness to (do shell script "python3 -c " & quoted form of depthScript) as number
			on error errMsg
				my tsLog("Depth eval failed (" & errMsg & "), using suggestedDepth=" & suggestedDepth)
				set stripeThickness to suggestedDepth
			end try
			my tsLog("Depth resolved to: " & stripeThickness & " px")
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 5: Save defaults for next run.
			-- ════════════════════════════════════════════════════════════
			do shell script "defaults write $HOME/.shadowtext_defaults angle " & chosenAngle
			do shell script "defaults write $HOME/.shadowtext_defaults depth " & stripeThickness
			do shell script "defaults write $HOME/.shadowtext_defaults startRGB " & quoted form of saveStartRGB
			do shell script "defaults write $HOME/.shadowtext_defaults endRGB " & quoted form of saveEndRGB
			my tsLog("Step 5: defaults saved (depth=" & stripeThickness & " startRGB=" & saveStartRGB & " endRGB=" & saveEndRGB & ")")
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 6: Compute direction vector and gradient color list.
			-- dirX negated: shadow falls opposite to angle direction.
			-- dirY not negated: Pixelmator Y increases downward, which
			-- cancels out the counter-clockwise sine inversion.
			-- shadowColorList has one color per shadow layer:
			--   item 1 = start color (closest to face)
			--   item n = end color (deepest)
			-- ════════════════════════════════════════════════════════════
			set angleRad to chosenAngle * (3.14159265 / 180)
			set dirX to (my cosine(angleRad)) * -1
			set dirY to my sine(angleRad)
			set shadowColorList to my interpolateColors(shadowColor1, shadowColor2, stripeThickness)
			my tsLog("Color list built, " & (count shadowColorList) & " entries")
			my tsLog("dirX=" & (dirX as text) & " dirY=" & (dirY as text))
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 7: Create the face layer.
			-- Duplicate pixel layer first (clean copy at pixelLayerIndex).
			-- Set fill color of styles on copy. Position.
			-- After duplicate: copy at pixelLayerIndex (faceIndex),
			-- pixel layer shifts to pixelLayerIndex+1.
			-- currentOriginalIndex starts at pixelLayerIndex+1.
			-- If a preserved original exists, it shifts down by 1 too.
			-- ════════════════════════════════════════════════════════════
			my tsLog("Step 7: creating face layer")
			duplicate layer pixelLayerIndex
			-- Face copy lands AT pixelLayerIndex; pixel source shifts to +1.
			-- Do NOT use index of current layer — duplicating a non-selected
			-- layer does not update current layer in Pixelmator Pro.
			set faceIndex to pixelLayerIndex
			set fill color of styles of layer faceIndex to item 1 of shadowColorList
			set position of layer faceIndex to {coordX, coordY}
			-- Track pixel layer and preserved original after shift
			set pixelLayerIndex to pixelLayerIndex + 1
			if preservedOriginalIndex > -1 then
				set preservedOriginalIndex to preservedOriginalIndex + 1
			end if
			my tsLog("Step 7 done: faceIndex=" & faceIndex & " pixelLayerIndex now=" & pixelLayerIndex)
			set {px, py} to position of layer faceIndex
			set faceColor to my getLayerColor(faceIndex)
			my tsLog("Step 7: face (index " & faceIndex & ") class=" & (class of layer faceIndex as text) & " pos=" & (px as text) & "," & (py as text) & " color=" & faceColor)
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 8: Build the shadow stack.
			-- currentOriginalIndex starts at pixelLayerIndex (the pixel
			-- layer, which is the source for all duplicates).
			-- Each iteration: duplicate pixel layer at currentOriginalIndex,
			-- copy lands AT currentOriginalIndex, pixel layer shifts to +1.
			-- Set fill color of styles on copy. Position. Increment.
			-- pixelLayerIndex and preservedOriginalIndex advance by 1
			-- each iteration as the pixel layer shifts down.
			-- ════════════════════════════════════════════════════════════
			my tsLog("Step 8: building shadow stack, iterations=" & stripeThickness)
			set currentOriginalIndex to pixelLayerIndex
			repeat with i from 1 to stripeThickness
				duplicate layer currentOriginalIndex
				-- Copy lands AT currentOriginalIndex; pixel layer shifts to +1
				set fill color of styles of layer currentOriginalIndex to item i of shadowColorList
				set position of layer currentOriginalIndex to ¬
					{coordX + (dirX * i), coordY + (dirY * i)}
				set currentOriginalIndex to currentOriginalIndex + 1
				set pixelLayerIndex to pixelLayerIndex + 1
				if preservedOriginalIndex > -1 then
					set preservedOriginalIndex to preservedOriginalIndex + 1
				end if
				if i mod 5 = 0 then my tsLog("Step 8: loop iteration " & i & " done")
			end repeat
			my tsLog("Step 8 done: pixelLayerIndex=" & pixelLayerIndex & " preservedOriginalIndex=" & preservedOriginalIndex)
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 9: Merge the shadow stack.
			-- stackTop = faceIndex, stackBottom = faceIndex + stripeThickness
			-- The pixel layer is at pixelLayerIndex (just below the stack).
			-- After merge: stripeThickness+1 layers collapse to 1.
			-- The merged layer lands at stackTop (=faceIndex=1 typically).
			-- pixelLayerIndex adjusts: subtract stripeThickness since that
			-- many layers above it collapsed into one.
			-- ════════════════════════════════════════════════════════════
			set stackTop to faceIndex
			set stackBottom to faceIndex + stripeThickness
			
			my tsLog("Step 9: pre-merge details (stackTop=" & stackTop & " stackBottom=" & stackBottom & ")")
			repeat with i from stackTop to stackBottom
				set {px, py} to position of layer i
				set layerCol to my getLayerColor(i)
				my tsLog("  layer " & i & " [" & (class of layer i as text) & "] pos=" & (px as text) & "," & (py as text) & " color=" & layerCol)
			end repeat
			
			set layersToMerge to {}
			repeat with i from stackTop to stackBottom
				set end of layersToMerge to layer i
			end repeat
			my tsLog("Step 9: merging " & (count layersToMerge) & " layers")
			
			set mergedLayer to merge layers layersToMerge
			set {px, py} to position of mergedLayer
			my tsLog("Step 9: merge done, raw pos=" & (px as text) & "," & (py as text))
			
			set snapX to pixelX
			set snapY to pixelY
			if dirX < 0 then set snapX to pixelX + (round (dirX * stripeThickness))
			if dirY < 0 then set snapY to pixelY + (round (dirY * stripeThickness))
			set position of mergedLayer to {snapX, snapY}
			my tsLog("Step 9: snapped to " & (snapX as text) & "," & (snapY as text))
			
			set name of mergedLayer to originalLayerName & " shadow"
			my tsLog("Step 9 done: merged layer named '" & originalLayerName & " shadow'")
			
			-- Adjust pixelLayerIndex for the merge collapse:
			-- stripeThickness+1 layers became 1, so stripeThickness
			-- layers were removed from above pixelLayerIndex
			set pixelLayerIndex to pixelLayerIndex - stripeThickness
			if preservedOriginalIndex > -1 then
				set preservedOriginalIndex to preservedOriginalIndex - stripeThickness
			end if
			my tsLog("Step 9: post-merge pixelLayerIndex=" & pixelLayerIndex & " preservedOriginalIndex=" & preservedOriginalIndex)
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 10: Rename and move pixel layer above shadow.
			-- Rename the pixel working layer to <name>.pixel.
			-- Move it to sit directly above the merged shadow layer
			-- (merged shadow is at index 1, so move pixel to index 1,
			-- pushing shadow to index 2).
			-- ════════════════════════════════════════════════════════════
			set name of layer pixelLayerIndex to originalLayerName & ".pixel"
			my tsLog("Step 10: pixel layer renamed to '" & originalLayerName & ".pixel'")
			move layer pixelLayerIndex to before mergedLayer
			my tsLog("Step 10: pixel layer moved to just above merged shadow")
			
			-- ════════════════════════════════════════════════════════════
			-- STEP 11: Group result + source; leave other layers as-is.
			-- Group the .pixel + shadow + source layers — safe and robust.
			-- ════════════════════════════════════════════════════════════
			my tsLog("Step 11: grouping result + source layers")
			set theGroup to make group from {layer (originalLayerName & ".pixel"), layer (originalLayerName & " shadow"), layer originalLayerName}
			set name of theGroup to originalLayerName
			my tsLog("Step 11 done: grouped as " & originalLayerName)
			
		end if
	end tell
end tell
end using terms from
my tsLog("=== TextShadowing complete ===")

-- ============================================================
-- HELPER HANDLERS
-- ============================================================

-- tsLog: appends a line to ~/Desktop/ts_debug.txt
on tsLog(msg)
	if debugMode then
		do shell script "echo " & quoted form of msg & " >> ~/Desktop/ts_debug.txt"
	end if
	
end tsLog
-- colorToRGBString: converts a Pixelmator {0-65535} color list to
-- a normalized "R,G,B" string (0-255). Used to save colors to plist
-- in a consistent format regardless of how they were input.
on colorToRGBString(c)
	set r to round ((item 1 of c) / 257)
	set g to round ((item 2 of c) / 257)
	set b to round ((item 3 of c) / 257)
	return (r as text) & "," & (g as text) & "," & (b as text)
end colorToRGBString

-- getLayerColor: returns "R,G,B" string (0-255) for layer at index.
-- Reads fill color of styles — the rendered color for all layer types.
-- Returns "n/a" if the color cannot be read.
on getLayerColor(layerIdx)
	using terms from application "Pixelmator Pro"
	tell application pixApp
		tell front document
			try
				set c to fill color of styles of layer layerIdx
				set r to round ((item 1 of c) / 257)
				set g to round ((item 2 of c) / 257)
				set b to round ((item 3 of c) / 257)
				return (r as text) & "," & (g as text) & "," & (b as text)
			on error
				return "n/a"
			end try
		end tell
	end tell
	end using terms from
end getLayerColor

-- parseRGB: converts a color string to a Pixelmator {0-65535} list.
-- Accepts R,G,B decimal (246,38,8) or hex with or without #
-- (F6260E or #F6260E). Format auto-detected by presence of a comma.
-- Returns {0,0,0} on any parse error rather than crashing.
on parseRGB(colorString)
	set s to colorString
	if length of s > 0 and character 1 of s is "#" then
		set s to text 2 thru -1 of s
	end if
	set hasComma to false
	repeat with i from 1 to (count characters of s)
		if character i of s is "," then
			set hasComma to true
			exit repeat
		end if
	end repeat
	if hasComma then
		try
			set oldDelimiters to AppleScript's text item delimiters
			set AppleScript's text item delimiters to ","
			set parts to text items of s
			set AppleScript's text item delimiters to oldDelimiters
			set r to ((item 1 of parts) as number) * 257
			set g to ((item 2 of parts) as number) * 257
			set b to ((item 3 of parts) as number) * 257
			return {r, g, b}
		on error
			my tsLog("parseRGB: failed to parse decimal '" & colorString & "' — returning black")
			return {0, 0, 0}
		end try
	else
		try
			set hexResult to do shell script "python3 -c 'h=\"" & s & "\"; print(int(h[0:2],16), int(h[2:4],16), int(h[4:6],16))'"
			set oldDelimiters to AppleScript's text item delimiters
			set AppleScript's text item delimiters to " "
			set hexParts to text items of hexResult
			set AppleScript's text item delimiters to oldDelimiters
			set r to ((item 1 of hexParts) as number) * 257
			set g to ((item 2 of hexParts) as number) * 257
			set b to ((item 3 of hexParts) as number) * 257
			return {r, g, b}
		on error
			my tsLog("parseRGB: failed to parse hex '" & colorString & "' — returning black")
			return {0, 0, 0}
		end try
	end if
end parseRGB

-- interpolateColors: returns a list of n colors interpolated between c1 and c2.
-- Item 1 = c1 (start/face color), item n = c2 (end/deepest color).
on interpolateColors(c1, c2, n)
	set colorList to {}
	repeat with i from 1 to n
		if n > 1 then
			set t to (i - 1) / (n - 1)
		else
			set t to 0
		end if
		set r to round ((item 1 of c1) + t * ((item 1 of c2) - (item 1 of c1)))
		set g to round ((item 2 of c1) + t * ((item 2 of c2) - (item 2 of c1)))
		set b to round ((item 3 of c1) + t * ((item 3 of c2) - (item 3 of c1)))
		set colorList to colorList & {{r, g, b}}
	end repeat
	return colorList
end interpolateColors

-- cosine: Taylor series approximation (AppleScript has no built-in trig).
-- cos(x) ≈ 1 - x²/2! + x⁴/4! - x⁶/6!
on cosine(x)
	set pi to 3.14159265359
	set twoPi to 2 * pi
	set x to x - (twoPi * (round (x / twoPi)))
	set x2 to x * x
	return 1 - (x2 / 2) + (x2 * x2 / 24) - (x2 * x2 * x2 / 720)
end cosine

-- sine: Taylor series approximation (AppleScript has no built-in trig).
-- sin(x) ≈ x - x³/3! + x⁵/5! - x⁷/7!
on sine(x)
	set pi to 3.14159265359
	set twoPi to 2 * pi
	set x to x - (twoPi * (round (x / twoPi)))
	set x3 to x * x * x
	return x - (x3 / 6) + (x3 * x * x / 120) - (x3 * x * x * x * x / 5040)
end sine