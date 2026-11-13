fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sd-interact'
author 'Samuels Development'
version '1.0.2'
description 'Interact: minimal floating prompts on points, entities, models and bones, drawn into the world, keyboard and controller'

shared_scripts {
    '@ox_lib/init.lua',
}

client_scripts {
    'client/main.lua',
}

-- The prompt is a page rendered off screen (a DUI) and painted into the frame with DrawSprite, so it
-- is listed in files{} (not ui_page). A `dir/**.lua` glob does not match files sitting directly in
-- `dir`, so folders with top-level modules are listed in both forms.
files {
    'configs/config.lua',
    'configs/client/*.lua',
    'client/*.lua',
    'client/**.lua',
    'locales/*.json',
    'assets/*.png',
    'web/build/index.html',
    'web/build/assets/*',
}

dependencies {
    'ox_lib',
}

-- Replacing a target resource (configs/client/replace.lua): sd-interact answers its exports, but a
-- script that lists it as a `dependency` only starts if something by that name exists. Once you have
-- removed ox_target / qtarget / qb-target from your server, either uncomment the matching line(s) here
-- or add the empty stand-in described in the README. Never while the real resource is installed.
-- provide 'ox_target'
-- provide 'qtarget'
-- provide 'qb-target'
