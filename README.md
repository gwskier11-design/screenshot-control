# Screenshot Control

A focused companion app for the Screenshot Test app. It uses forcequitOS's worse_query proof of concept to locate Screenshot Test's data container and edit only `Documents/ScreenshotSettings.plist`.

Open Screenshot Test once before using this app. Tap Disable, then reopen Screenshot Test and take a screenshot. The event counter should still increase while its alert stays hidden. Tap Enable to restore the alert.

This repository includes code from [forcequitOS/worse_query](https://github.com/forcequitOS/worse_query) under GPL-3.0. The app requires an authorized App Group entitlement and a supported iOS build. Device behavior has not been verified.

## Local export

In Files, open Snapchat and tap **Export Snapchat Files**. The app copies readable files to a dated folder under its own Documents directory. Find the folder in Apple's Files app under **On My iPhone > Screenshot Control**. The status reports copied and skipped items. This is a local snapshot and can be incomplete if files are inaccessible or change during the copy.
