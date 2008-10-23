# 
# $Id$
#
load 'tasks/setup.rb'

ensure_in_path 'lib'
require 'emdrb'

task :default => 'test:run'

PROJ.name = 'emdrb'
PROJ.authors = 'dido@imperium.ph'
PROJ.email = 'dido@imperium.ph'
PROJ.url = 'http://emdrb.rubyforge.org'
PROJ.rubyforge.name = 'emdrb'
PROJ.version = EMDRb::Version::STRING
PROJ.dependencies = ["eventmachine"]

PROJ.spec.opts << '--color'

# EOF
