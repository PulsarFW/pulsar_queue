fx_version 'cerulean'
games { 'gta5' }

name 'Pulsar Queue'
description 'Connection queue with join order, whitelists, and max-player enforcement'
author 'Artmines - maintained for Pulsar Framework'
url 'https://pulsarframe.work'
version 'v1.0.0'

version_check 'yes'
github 'https://github.com/PulsarFW/pulsar_queue'

client_script '@pulsar_core/components/cl_error.lua'
shared_script '@pulsar_core/core/sh_pulsar.lua'
client_script '@pulsar_pwnzor/client/check.lua'

server_only 'yes'

server_scripts({
	'config.lua',
	'server/*.lua',
})

lua54 'yes'