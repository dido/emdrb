#  -*- Ruby -*-
# $Id$
#
load 'tasks/setup.rb'

ensure_in_path 'lib'
require 'emdrb/version'

task :default => 'test:run'

PROJ.name = 'emdrb'
PROJ.authors = 'dido@imperium.ph'
PROJ.email = 'dido@imperium.ph'
PROJ.url = 'http://emdrb.rubyforge.org'
PROJ.rubyforge.name = 'emdrb'
PROJ.version = EMDRb::Version::STRING
PROJ.dependencies = ["eventmachine"]
PROJ.rcov.opts += ["-Ilib"] # Why is this necessary?

PROJ.spec.opts << '--color'

# EOF
