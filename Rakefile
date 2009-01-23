#  -*- Ruby -*-
#
# Author:: Rafael R. Sevilla (mailto:dido@imperium.ph)
# Copyright:: Copyright © 2008, 2009 Rafael R. Sevilla
# Homepage:: http://emdrb.rubyforge.org/
# License:: GNU General Public License / Ruby License
#
# $Id$
#
#----------------------------------------------------------------------------
#
# Copyright © 2008, 2009 Rafael Sevilla
# This file is part of EMDRb
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of either: 1) the GNU General Public License
# as published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version; or 2) Ruby's License.
# 
# See the file COPYING for complete licensing information.
#----------------------------------------------------------------------------
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
