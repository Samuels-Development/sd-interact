<div align="center">

# sd-interact

<img width="960" alt="sd-interact banner: a bank lobby straight on, an Open the vault prompt held on the vault door's wheel" src="docs/previews/sd-interact-banner.webp">

sd-interact puts the interaction on the thing itself. Look at something you can use and a small prompt opens on it: an icon on the spot, what it does, and the key that does it. Several options stack on a drum you scroll. Hold options draw an outline round the tile as you hold, and on a controller the key becomes the pad button. It has its own API, and it can also answer ox_target, qtarget and qb-target calls, so the scripts you already run use it without changing a line.

[![Stars](https://img.shields.io/github/stars/Samuels-Development/sd-interact?label=Stars&logo=github)](https://github.com/Samuels-Development/sd-interact)
[![Discord](https://img.shields.io/discord/842045164951437383?label=Discord&logo=discord&logoColor=white)](https://discord.gg/FzPehMQaBQ)

![Standalone](https://img.shields.io/badge/Needs-ox__lib%20only-3b82f6)
![Input](https://img.shields.io/badge/Input-keyboard%20%7C%20controller-3b82f6)
![Stands in for](https://img.shields.io/badge/Stands%20in%20for-ox__target%20%7C%20qtarget%20%7C%20qb--target-3b82f6)

[**Download**](https://github.com/Samuels-Development/sd-interact/releases/latest) · [**Docs**](https://docs.samueldev.shop/resources/interact/) · [**Store**](https://fivem.samueldev.shop) · [**Discord**](https://discord.gg/FzPehMQaBQ)

**Works together:** **sd-interact** · [**sd-gunracks**](https://github.com/Samuels-Development/sd-gunracks)

</div>

---

## Support Me

If you're enjoying sd-interact and want to support my work, consider picking up a script from [Samuel's Development](https://fivem.samueldev.shop). Every purchase helps me keep building and improving free resources like this one.

## Preview

<p align="center"><img src="docs/previews/prompt-demo.gif" alt="A prompt opening on a pistol, scrolling to Inspect, holding Seize while the outline fills, and closing" width="960" /></p>

<p align="center"><sub>Recorded from the prompt page itself (the same page the game draws), over a rendered room.</sub></p>

## Screenshots

The rooms are rendered in Blender. The prompts are captured from the page and placed exactly where the game draws them: the tile on the point, at the size the default config draws at 4K. Click an image for the full 1920×1080 version.

<p align="center"><a href="docs/previews/01-on-anything.webp"><img src="docs/previews/01-on-anything.webp" alt="Crack the safe: a hold prompt on a safe, with a dot on the workbench beside it" width="960" /></a></p>

<p align="center"><a href="docs/previews/02-states.webp"><img src="docs/previews/02-states.webp" alt="The prompt's states: three options, scrolled with a second line, held, and on a controller" width="960" /></a></p>

<p align="center"><a href="docs/previews/03-gun-racks.webp"><img src="docs/previews/03-gun-racks.webp" alt="Take Combat Pistol: a prompt on one slot of an sd-gunracks pistol board" width="960" /></a></p>

---

## Highlights

- **On the thing, not on the screen.** The prompt is painted into the game's own frame at the point (an off-screen page drawn with `DrawSprite`). It stays pinned to the world with no lag, and it renders at the screen's own resolution, so its text stays sharp.
- **Quiet until you need it.** Only the point nearest the middle of the screen opens. Other points in range show as small dots, a ring once you're close enough, and dots that crowd together merge into one. A prompt behind a wall doesn't open.
- **Press, scroll, hold.** Options stack on a drum, and the one on the point is the one the key uses. An option can ask to be held: an outline runs round its tile as you hold and runs back if you let go. It can carry a second line, or change its label as things change ("Rack Assault Rifle").
- **Keyboard and controller.** Confirm, next and previous are FiveM key mappings (E and the wheel, the d-pad on a pad), so every player can rebind them in Settings > Key Bindings > FiveM. The prompt shows whichever device you're using.
- **Anything you can point at.** Coordinates, local or networked entities (on an offset or a bone), every entity of some models, or every vehicle, ped, object or player nearby.
- **A stand-in for the target you use.** Turned on, it answers `exports.ox_target`, `exports.qtarget` and `exports['qb-target']` with prompts: zones, entities, models, bones, global options, item, job and gang checks, and every way of handling an option.

## Compatibility

| Layer | Supported |
|---|---|
| Frameworks | Any. Job, gang and item checks read QBox, QBCore or ESX when one is running, and ox_inventory for items |
| Input | Keyboard and mouse, controller |
| Languages | English, Danish, Swedish (`Locale` in `configs/config.lua`) |
| Stands in for | ox_target (its 1.17 API), qtarget, qb-target (its 5.5 API) |
| Needs | [ox_lib](https://github.com/CommunityOx/ox_lib). Client only: no server script, no database |

## Installation

Download **`sd-interact.zip`** from the [latest release](https://github.com/Samuels-Development/sd-interact/releases/latest) and unzip it into your resources folder: it is the resource with its prompt page already built, ready to drop in. Start it after ox_lib, and before the resources that add prompts:

```cfg
ensure ox_lib
ensure sd-interact
```

> [!IMPORTANT]
> Download the `sd-interact.zip` asset, not **Source code (zip)** or the green **Code** button. Those are the source, without the built page: the resource would start, but no prompt would ever draw until you [build it yourself](#building-from-source).

Distances, the default keys, the prompt's size and the dots are in `configs/client/`.

## Documentation

The full guide is at **[docs.samueldev.shop/resources/interact](https://docs.samueldev.shop/resources/interact/)**:

| | |
|---|---|
| [Installation](https://docs.samueldev.shop/resources/interact/installation) | Start order, a first prompt to check it works, rebinding keys |
| [Adding prompts](https://docs.samueldev.shop/resources/interact/adding-prompts) | Points, distances, where the prompt sits, options, who sees them, what they do |
| [Examples](https://docs.samueldev.shop/resources/interact/examples) | A shopkeeper, every ATM, a car's boot that says Open or Close, police-only options, item checks, server entities, moving over from ox_target |
| [Client exports](https://docs.samueldev.shop/resources/interact/exports-client) | Every export with its parameters and what it returns |
| [Configuration](https://docs.samueldev.shop/resources/interact/configuration) | Every option in `configs/client/` |
| [Replacing ox_target / qb-target](https://docs.samueldev.shop/resources/interact/target-compatibility) | Answering their exports, what is supported, the known differences |

A first prompt, to see the shape of it:

```lua
exports['sd-interact']:addLocalEntity(ped, {
    offset = vec3(0.0, 0.0, 0.3),
    options = {
        { label = 'Browse the shop', icon = 'fa-solid fa-basket-shopping', serverEvent = 'myshop:open' },
        { label = 'Rob the till', icon = 'fa-solid fa-sack-dollar', hold = 3000, groups = { ballas = 0 }, onSelect = robTill },
    },
})
```

Options take ox_target's handler fields (`onSelect`, `export`, `event`, `serverEvent`, `command`) and `groups`, so option tables move over as they are.

## Replacing ox_target, qtarget or qb-target

Scripts written for a target resource can use prompts without being changed. Name the ones to answer in your `server.cfg`, before `ensure sd-interact`, then take the real resource out of your server (two resources answering one export fight):

```cfg
setr sd_interact:replace "ox_target,qtarget"
ensure sd-interact
```

Scripts that list ox_target as a dependency also need something by that name to start: an empty stand-in resource or a `provide` line. Both, every supported export, and the known differences are on [Replacing ox_target / qb-target](https://docs.samueldev.shop/resources/interact/target-compatibility).

## For developers

### Building from source

The repository is the source: the built prompt page (`web/build`) is not committed, and each [release](https://github.com/Samuels-Development/sd-interact/releases) builds it into its zip. To run a clone, or after changing the page, build it with Node.js (LTS):

```bash
cd web
npm ci
npm run build   # what the game draws (web/build)
npm run dev     # the page in a browser: /#mock runs through every state (#mock&step=0..4 freezes one)
```

A source zip unpacks to `sd-interact-main`: rename the folder to `sd-interact`, the name its exports are called by. `#shot=<messages>` shows one state, given as the JSON messages the game sends, for pictures like the ones above. `CANVAS` and `ANCHOR` in `web/src/Prompt.tsx` must match `Canvas` and `Anchor` in `configs/client/draw.lua`.

### Tests

`lua tests/run.lua` runs focus picking, the point registry, and the ox_target, qtarget and qb-target layers offline under stock Lua 5.4: option conversion, handler data, checks, removal and the self target.

## Licence

GPL-3.0. Fonts, icons and other third-party material are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
