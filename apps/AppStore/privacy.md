# App Store privacy answers (beadster 2.0, mac)

read from the code and the binary 2026-10-07 (mac loop S4). App Store Connect takes these by hand (App Privacy); the API has no door for them. DRAFT for anton.

## what leaves the Mac, and when

- nothing. projects are read and changed in their own folders by beads' own code inside the app; no account, no server, no sync (the 1.x beadster.ai sync is gone)
- Spotlight and notifications are the Mac's own, on this Mac
- Send Feedback and the About card's issue/idea/question open the person's own mail app with a draft to hi@beadster.ai; nothing is sent by the app
- no analytics, no crash reporting service, no advertising, no tracking
- the manifest says the same: macos/Beadster/PrivacyInfo.xcprivacy (no collected data types; required-reason APIs: UserDefaults CA92.1, system boot time 35F9.1 for the Go runtime's clock, file timestamps 3B52.1 + C617.1 for the folders the person grants and the app's own container)

## the answers

- Data Not Collected
- tracking: no

## the privacy page (beadster.ai/privacy, the URL the listing already carries)

beadster.ai serves nothing today (S2 finding), so the page App Review opens is dead. draft words for anton, all of them true of 2.0:

> beadster keeps your projects on your Mac. It reads and changes them in the folders you choose, with beads' own code running inside the app. It has no account and no server, and sends nothing anywhere: no analytics, no crash reports, no tracking. If you write to us from the app, your mail app sends that message, to hi@beadster.ai. Questions: hi@beadster.ai.

## to check once

- the sandbox entitlement com.apple.security.network.client is still on (from the 1.x sync). nothing in 2.0 calls the network (no URLSession; AppCatalog's only fetch, an announcement image, is never shown here). turn it off and run the P4 probe once: if beads' engine opens and writes with it off, ship without it
