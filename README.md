# NotnHeavy's Old Flamethrower Mechanics

Making use of `CTFFlameEntity`, which is still present in the game files, this plugin reintroduces pre-Jungle Inferno flames. I may look into other things as well with this plugin in the future.

Note that due to flame visuals being client-side and I'm not really sure how to get around truly re-creating them, the original `CTFFlameManager` entity is still spawned for flame visuals. If you would like to utilise old flame visuals, [check out this mod.](https://gamebanana.com/mods/12497)

## Installation

Download the latest release from the release tabs, and just drag the addons folder to your server's /tf/ directory. This plugin uses SourceMod 1.11.

## Dependencies

- nosoop's fork of TF2Attributes
- Scags' SM-Memory extension.

## ConVars

- notnheavy_flamethrower_enable (1 by default): enable this plugin.
- notnheavy_flamethrower_damage (6.80 by default): default flame damage.
- notnheavy_flamethrower_oldafterburn_damage (0 by default): enable old afterburn damage (3 per tick instead of 4).
- notnheavy_flamethrower_oldafterburn_duration (0 by default): enable old afterburn duration (full 10s, 6s with Cow Mangler, 0.25s if Pyro or afterburn immune).
- notnheavy_flamethrower_falloff (0.70 by default): falloff multiplier at `tf_flamethrower_maxdamagedist` distance.

AlliedModders post: https://forums.alliedmods.net/showthread.php?p=2787580
