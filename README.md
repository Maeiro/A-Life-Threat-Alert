# Viewpoint Threat Detector

Project Zomboid Build 42 mod that improves situational awareness with alerts for nearby Project A-Life NPCs, sprinters, and zombies approaching from behind. It does not require Project Viewpoint, Viewpoint Extended Support, or A-Life Stance Dots.

Hostile, Careful, Neutral, Friendly, and Allied NPC warnings can each be enabled independently. Hostile and Careful are enabled by default; the other stance alerts are off by default to preserve the previous behavior. If several enabled stances are nearby, alerts appear from highest to lowest priority—Hostile, Careful, Neutral, Friendly, then Allied—with a distinct color for each. Unknown factions continue to use the A-Life default stance of Hostile. The warning distance is configurable from 5 to 100 tiles, with a default of 40. Alerts report distance and direction, and the optional firearm warning identifies carriers within each enabled stance.

The mod can also warn about regular zombies out of sight behind the player. By default, only zombies on the player's floor with a clear path (not blocked by walls or closed doors) trigger this warning. Both filters are configurable. Balanced range is enabled by default and follows the vanilla perception distance: 3.5 tiles normally and 6.5 with Keen Hearing. Disable balanced range to set a custom distance from 5 to 100 tiles. The rear detection angle is adjustable from 30 to 360 degrees (180 degrees by default), and its directional arrow points toward the nearest detected zombie. Larger angles widen the detection area toward the sides and front. It also works when Project A-Life is not loaded; A-Life NPCs are excluded from the zombie count.

An optional setting (off by default) ignores fallen zombies in rear warnings. The warning stack can be dragged with the mouse; its position is saved between sessions.

Sprinters have their own all-direction warning and dedicated alarm. Configure its distance, same-floor and line-of-sight filters, fallen-zombie handling, sound cue, and volume independently from the other alerts. Sprinter detection excludes A-Life NPCs.

Alerts are disabled while the player is inside a vehicle by default; this can be turned off in Mod Options.

Immersive audio-only alerts can be enabled in Mod Options to hide this mod's HUD cards and display previews while preserving threat detection and all configured alarm sounds.

Alarm sounds are enabled by default: the regular zombie warning uses heartbeat, close Hostile A-Life uses radar ping, and sprinters use a soft beep. Additional choices include sonar ping, short alarm, and ten space-themed cues. The siren has been removed. Each sound can be previewed in-game with the configured preview key; alert-display buttons show temporary A-Life, rear-zombie, and sprinter examples. Alarm volume is configurable from 0% to 200% and defaults to 150%. By default, the regular alarm is limited to zombie warnings; A-Life notifications remain silent except for the separate close Hostile A-Life alarm. Sprinter alarms have separate sound, volume, and distance settings, independent of the visual warning range; close Hostile A-Life alarm distance is configurable independently of the regular NPC warning range. A new alarm stops the previous one so alert sounds do not overlap. No other mod is required. An alarm plays when a new warning type appears, not on every scan. Sound asset licenses and credits are included in `42/SOUND_CREDITS.txt`.

When NeatUI_Framework is active, alerts use its panel textures and styling. Minimal Alert UI removes text labels and shows icons, counts, direction arrows, and tile distances (such as `68t`), keeping the normal text and icon scale while sizing each card to its contents. Arrows are drawn as triangles, rotate continuously toward each threat, and use the A-Life stance colors: red for Hostile, yellow for Careful, white for Neutral, green for Friendly, and blue for Allied. When Viewpoint Compass is active, arrows use its camera heading; otherwise, they fall back to the character's facing direction. Nearby firearm carriers use the vanilla M9 Pistol icon. Without NeatUI_Framework, the same information appears in a compact HUD line.

Small icons distinguish A-Life NPC alerts from zombie alerts.

## Alerts and configuration

Configure the alerts through the in-game Mod Options. Project A-Life is required for NPC stance and firearm-carrier alerts; rear zombie alerts work independently.
