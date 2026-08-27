project('eswitch_probe', 'C',
    version: '1.0.0',
    license: 'Proprietary',
    default_options: ['buildtype=debug', 'warning_level=2'],
    meson_version: '>= 0.61.2'
)

APP_NAME = 'eswitch_probe'

# Allow experimental DOCA APIs
add_project_arguments('-D DOCA_ALLOW_EXPERIMENTAL_API', language: 'c')

# ARM-specific optimization flags (BlueField-3, Cortex-A78AE)
add_project_arguments([
    '-mcpu=cortex-a72+crc',
    '-Wno-missing-braces',
], language: 'c')

# Dependencies
dependencies = []
dependencies += dependency('doca')
dependencies += dependency('libdpdk')

sources = [
    'probe.c',
]

executable(APP_NAME,
    sources,
    dependencies: dependencies,
    install: false
)
