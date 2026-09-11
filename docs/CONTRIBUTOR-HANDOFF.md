# BarShelf: what we changed, why, and what is ready to review

Harry,

We now have a substantially more usable BarShelf on Jon's Mac. Jon reports that most functions work, and the shelf no longer presents icons that macOS currently reports as unavailable. We have also removed the failure loop that could make even Quit unusable. This is a good point to share the work for your review and testing. It is not yet a claim that every menu-bar app works perfectly on every Mac.

The remaining concrete issue is Tailscale's return order: it can get back into overflow but land beside the wrong neighbor. The app now tells the user what actually happened and lets them continue. We should keep that issue visible rather than call the entire project finished.

## What this means in GitHub terms

A **commit** is a recorded set of changes. A **branch** holds a proposed line of work separately from the main version. A **pull request**, usually called a PR, is a proposal to bring a branch's changes into the project. It gives you the explanation, a line-by-line comparison, test results, and a place to discuss improvements before accepting anything.

A **draft PR** is a useful way to share this particular work: you can inspect and test it while the remaining issues and product choices are discussed. GitHub prevents a draft from being merged until it is marked ready. **Merging** means accepting the changes into the target branch; **releasing** means packaging a version for people to install. Those are separate decisions.

This contribution is based on upstream commit 6ba474d793a702466b3cbc615d3217d883c4ef5c, verified as the upstream HEAD at publication preparation. It is being proposed through Jon’s fork so you can review the changes without changing your main branch. The source proposal is not an installer or a public release.

GitHub's explanation: https://docs.github.com/en/pull-requests/reference/pull-requests

## The central discovery: “hidden” had two different meanings

There are two independent controls:

1. macOS's **Allow in the Menu Bar** determines whether an app's status icon is allowed to participate in the menu bar.
2. BarShelf's **Always hidden** controls where an available icon is kept and accessed.

An app could be running and visible to Accessibility even though its macOS menu-bar switch was off. BarShelf discovered that record and put it in the shelf, but there was no usable icon to expose. Trying to use it then produced an error about missing section boundaries. That message pointed the user toward the wrong problem.

With Jon's permission, Chrome's system switch was enabled. That removed one obstacle, but then exposed separate problems in the move logic. Jon later reproduced the system-setting problem directly: switching an item off caused the error, and switching it back on fixed that part of the failure.

So disabled system items were a substantial part of the initial access problem. We cannot honestly assign a percentage, and we did not establish who originally switched them off. It would also be incorrect to attribute all the failures to macOS, because independent BarShelf movement and recovery bugs were demonstrated.

The earlier theory that an OS-version defect made the app fundamentally unfixable was too strong. We do not have a controlled comparison that proves the difference between the reported macOS versions caused these failures.

## How the user experience now differs

**Unavailable icons are left out of the shelf and search picker.** They remain in Settings so they are not impossible to discover or recover. Enabling an icon and refreshing makes it eligible again. This is based on what macOS currently reports about the icon's position, not on reading the system switch directly. Truly hidden icons still have menu-bar-row positions, even when their horizontal coordinates are far off-screen, so they remain in the shelf.

**The original interaction is retained.** Selecting a shelf entry brings out its real icon. The user clicks that icon to open the app's native controls, then requests its return. We briefly tested automatic menu opening during development, but the final proposal follows your documented expose-first interaction. It does not attempt to recreate another app's menu inside BarShelf.

**There is an extra placement option on a crowded bar.** BarShelf first tries your existing position before the leftmost drawable icon. If that cannot fit outside the notch, it tries beside its own dots control. This made useful progress on Jon's layout. It is worth your explicit review because inserting an icon there can push another visible icon toward the notch.

**Settings reports success only when the icon is really usable.** Previously an icon could be on the nominal “visible” side of the divider but still behind the notch. A second check now requires the whole icon to be drawable before a visible-section move is saved as successful. Settings also provides Open Shelf and Return Icon, and reopening the running app brings up its existing Settings window.

## Why the move fixes mattered

Moving a status icon is not the same as moving a normal app window. BarShelf uses Accessibility information to identify the item and a window-directed event mechanism to ask macOS to reposition it. That mechanism already existed in the project. The fixes improve the geometry and confirmation around it.

One problem involved reading the divider while macOS was still changing its size. The closed hidden-section divider is extremely wide; treating that stale frame as a compact open divider led to an invalid destination. The updated code waits for a compact boundary and stable measurements before a Settings move.

Another problem was the return point. Rectangle could move back left but land before the wrong neighbor. The return calculation needed to account for the selected icon's actual window width. That helped normal-size icons, but Weather exposed a second case: its window was 66 points wide and its return neighbor was only 38–40 points wide. Applying the full adjustment carried the release point past that neighbor. The correction caps that adjustment at the neighbor's width for a left-edge return.

These are shared rules about widths and positions. There is no special “if this app is Weather” or “if this app is Chrome” code.

## Why Tailscale looked as though it returned only after “Leave Here”

The trace showed that Tailscale was already back in overflow when the warning appeared. It had not returned between the exact original neighbors, however. BarShelf's strict check rejected that as an exact restoration.

The old wording made this sound as though the icon had never returned at all. The new wording distinguishes **back in overflow** from **original order restored**. Keep Current Order accepts the position already reached; it does not move the icon again. Retry Return requests another attempt. Quit can exit even after the return fails.

This fixes the misleading explanation and the trapped interaction, while preserving the evidence that there is still an ordering bug to investigate. It deliberately does not weaken the confirmation check to make a failed ordering test look successful.

## What was actually tested

The automated suite passed on the development checkout. It also passed on a separate copy of your upstream source with only the focused patch applied, which checks that the proposal does not secretly depend on our local diagnostic tooling. That focused source also passed a Release build with signing disabled.

Live computer-use checks verified complete shelf exposure and original-neighbor return for Weather, Rectangle, and Chrome on the return-geometry build. Chrome's Settings move was tested in both directions. Recovery tests verified that continuing after a failed return and quitting both work. Jon subsequently confirmed that many icons work and that filtering unavailable entries is better. We inspected the latest build's shelf after installing it.

Those statements have limits: we did not rerun every app and every path after each later message/filter change. The live movement tests do not prove that every native menu or popover opens correctly, and multi-display behavior still needs testing. The existing code's undocumented macOS event routing remains a compatibility dependency.

## Accessibility permissions and the app you receive

Jon repeatedly encountered a stale-looking Accessibility grant during the earlier build process. Removing and re-adding the app helped, but repeated ad-hoc builds can also change the identity macOS uses to recognize a grant. We moved the local builds to an existing stable development signing identity and kept the installed path consistent; subsequent installs retained access.

That is a local build improvement, not a guarantee that Jon's signed app is the right public distribution artifact. You should build and sign through your own intended process. No signing keys or credentials are part of the contribution, and this work is not a notarized public release.

## Suggested handoff

Review the source patch and PR description first. In particular, decide whether the fallback position beside the dots and the two Settings access buttons fit your preferred product behavior. Then test the proposed build on your own Mac with a crowded bar, including Weather, Rectangle, Chrome, Tailscale, an app switched off in macOS, and a return failure that exercises recovery. Confirm the off/on filtering behavior and verify that accepting a failed return never traps Quit.

The review branch contains the focused changes rather than the entire experimental branch. The patch excludes local agent coordination, diagnostic command-line tools, and local signing-script work. Tailscale's remaining ordering issue should be tracked explicitly; whether it must block merging is your call, but it should block any claim of universal reliability.

The deliverable is a tested source proposal plus the explanation needed to evaluate it. Your main branch and releases remain unchanged until you choose to accept and publish changes.
