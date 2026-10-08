# Viewpoint Threat Detector

Project Zomboid Build 42 mod that improves situational awareness with alerts for nearby Project A-Life NPCs and zombies approaching from behind. It does not require Project Viewpoint, Viewpoint Extended Support, or A-Life Stance Dots.

Hostile, Careful, Neutral, Friendly, and Allied NPC warnings can each be enabled independently. Hostile and Careful are enabled by default; the other stance alerts are off by default to preserve the previous behavior. If several enabled stances are nearby, alerts appear from highest to lowest priority—Hostile, Careful, Neutral, Friendly, then Allied—with a distinct color for each. Unknown factions continue to use the A-Life default stance of Hostile. The warning distance is configurable from 5 to 100 tiles, with a default of 40. Alerts report distance and direction, and the optional firearm warning identifies carriers within each enabled stance.

The mod can also warn about regular zombies out of sight behind the player. By default, only zombies on the player's floor with a clear path (not blocked by walls or closed doors) trigger this warning. Both filters are configurable. Balanced range is enabled by default and follows the vanilla perception distance: 3.5 tiles normally and 6.5 with Keen Hearing. Disable balanced range to set a custom distance from 5 to 100 tiles. The rear detection angle is adjustable from 30 to 360 degrees (180 degrees by default), and its directional arrow points toward the nearest detected zombie. Larger angles widen the detection area toward the sides and front. It also works when Project A-Life is not loaded; A-Life NPCs are excluded from the zombie count.

An optional setting (off by default) ignores fallen zombies in rear warnings. The warning stack can be dragged with the mouse; its position is saved between sessions.

Alerts are disabled while the player is inside a vehicle by default; this can be turned off in Mod Options.

Alarm sounds are enabled by default, with the bundled heartbeat selected. Choose the radar ping, siren, heartbeat, or soft beep in Mod Options. Alarm volume is configurable from 0% to 200% and defaults to 150% to make warnings easier to hear. By default, sounds are limited to zombie warnings; A-Life notifications remain silent. Turn that restriction off to play sounds for all threat types. A new alarm stops the previous one so alert sounds do not overlap. No other mod is required. An alarm plays when a new warning type appears, not on every scan. Sound asset licenses and credits are included in `42/SOUND_CREDITS.txt`.

When NeatUI_Framework is active, alerts use its panel textures and styling. Without it, the alert falls back to the standard HUD text.

Small icons distinguish A-Life NPC alerts from zombie alerts.

## Alerts and configuration

Configure the alerts through the in-game Mod Options. Project A-Life is required for NPC stance and firearm-carrier alerts; rear zombie alerts work independently.
