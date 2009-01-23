#  -*- Ruby -*-
# $Id$
#
load 'tasks/setup.rb'

ensure_in_path 'lib'
require 'emdrb/version'

task :default => 'spec:run'

PROJ.name = 'emdrb'
PROJ.authors = 'dido@imperium.ph'
PROJ.email = 'dido@imperium.ph'
PROJ.url = 'http://emdrb.rubyforge.org'
PROJ.rubyforge.name = 'emdrb'
PROJ.version = EMDRb::Version::STRING
PROJ.dependencies = ["eventmachine"]

PROJ.spec.opts << '--color'

# EOF
